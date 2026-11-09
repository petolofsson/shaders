#!/usr/bin/env python3
"""Screen illuminant-invariant chromaticity edge rules against the brightness oracle.

Extends tools/retinex_screen.py. The 2026-11-08 chromaticity rule (Funt, Drew &
Brockington 1992) discarded real shadow edges because skylit shade is bluer.
Finlayson, Hordley, Lu & Drew (PAMI 2006) remove that: in 2-D log chromaticity
(log R/G, log B/G) an illuminant change along the Planckian/daylight locus moves a
pixel along a fixed direction e, so only the component orthogonal to e is a
material change. Variants:
  inv_planck_*: e from approximate sRGB blackbody chromaticities (no scene knowledge);
  inv_scene_*:  e from this renderer's own sun and sky colours (calibrated bound);
  inv_entropy_*: e chosen per frame by minimum entropy of the projection (Finlayson & Drew 2004).
An edge counts as light when its orthogonal chromaticity change is below the threshold.
CPU only; no shader work.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

import brightness_oracle as bo
import retinex_screen as rs
import shadow_oracle as so

# Approximate gamma-encoded sRGB of blackbody radiators (normalized to max 1).
BLACKBODY_SRGB = {3000: (1.0, .706, .420), 4000: (1.0, .820, .640), 5000: (1.0, .894, .808),
                  6500: (1.0, .976, .961), 8000: (.890, .920, 1.0), 10000: (.790, .850, 1.0)}

def to_lin(c):
    c = np.asarray(c, float)
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)

def logchroma(rgb):
    lg = np.log(np.maximum(rgb, 1e-6))
    return np.stack([lg[..., 0] - lg[..., 1], lg[..., 2] - lg[..., 1]], -1)

def unit(v):
    v = np.asarray(v, float); return v / np.linalg.norm(v)

def planck_direction():
    pts = np.array([logchroma(to_lin(c)) for c in BLACKBODY_SRGB.values()])
    pts -= pts.mean(0)
    return unit(np.linalg.svd(pts)[2][0])

def scene_direction():
    sunsky = so.SUN_RGB / np.pi + so.SKY_RGB
    return unit(logchroma(sunsky) - logchroma(so.SKY_RGB))

def entropy_direction(src, mask):
    lc = logchroma(src)[mask]
    best = None
    for deg in np.arange(0, 180, 1.0):
        e = np.array([np.cos(np.radians(deg)), np.sin(np.radians(deg))])
        proj = lc @ np.array([-e[1], e[0]])
        lo, hi = np.percentile(proj, [5, 95])
        p = proj[(proj >= lo) & (proj <= hi)]
        bw = 3.5 * p.std() * len(p) ** (-1 / 3) + 1e-9
        hist, _ = np.histogram(p, bins=max(8, int((hi - lo) / bw)))
        q = hist[hist > 0] / hist.sum()
        H = -(q * np.log2(q)).sum()
        if best is None or H < best[0]:
            best = (H, e)
    return best[1]

def sky_keep(dl, dperp, dalong, t, k_max, tol):
    """Light edge: invariant chroma steady, and any shift along the daylight axis is
    warm-on-the-brighter-side and bounded by k_max per stop of brightness change."""
    return (np.abs(dperp) < t) & (dalong * dl >= -tol * np.abs(dl) - 1e-9) & (np.abs(dalong) <= k_max * np.abs(dl) + tol)

def auto_keep(dl, dperp, dalong, t, k, slack, tol):
    """Light edge: invariant chroma steady and the daylight-axis shift follows this
    frame's own light-edge slope k (per stop), within slack per stop plus tol."""
    return (np.abs(dperp) < t) & (np.abs(dalong - k * dl) <= slack * np.abs(dl) + tol)

def frame_slope(gx, gy, px, py, ax, ay, t):
    """Robust per-frame slope of daylight-axis chroma vs log2 luminance over clear,
    invariant-steady edges (a stand-in for a GPU reduction)."""
    dl = np.concatenate([gx.ravel(), gy.ravel()]); dp = np.concatenate([px.ravel(), py.ravel()])
    da = np.concatenate([ax.ravel(), ay.ravel()])
    m = (np.abs(dl) > 0.15) & (np.abs(dp) < t)
    return float(np.median(da[m] / dl[m])) if m.sum() > 100 else 0.0

def invariant_light(src, e, t, smooth_r=1, sky=None, auto=None):
    eps = 0.002
    lin = np.stack([bo.box_blur(np.maximum(src[..., c], eps), smooth_r) for c in range(3)], -1)
    ly = np.log2(np.maximum(bo.box_blur(src @ so.LUMA, smooth_r), eps))
    gx = np.diff(ly, axis=1); gy = np.diff(ly, axis=0)
    lc = logchroma(lin)
    inv = lc @ np.array([-e[1], e[0]])          # component orthogonal to e
    if auto is not None:
        e = e if e[0] > 0 else -e
        al = lc @ e
        px, py = np.diff(inv, axis=1), np.diff(inv, axis=0); ax, ay = np.diff(al, axis=1), np.diff(al, axis=0)
        k = frame_slope(gx, gy, px, py, ax, ay, t)
        keep_x = auto_keep(gx, px, ax, t, k, *auto); keep_y = auto_keep(gy, py, ay, t, k, *auto)
        invariant_light.last_k = k
    elif sky is None:
        keep_x = np.abs(np.diff(inv, axis=1)) < t; keep_y = np.abs(np.diff(inv, axis=0)) < t
    else:
        e = e if e[0] > 0 else -e                 # oriented toward warm (R/G up)
        al = lc @ e
        keep_x = sky_keep(gx, np.diff(inv, axis=1), np.diff(al, axis=1), t, *sky)
        keep_y = sky_keep(gy, np.diff(inv, axis=0), np.diff(al, axis=0), t, *sky)
    return rs.poisson_neumann(gx * keep_x, gy * keep_y), float((keep_x.mean() + keep_y.mean()) / 2)

THRESH = (0.05, 0.10, 0.15)

def screen(name, cfg, args, out):
    f = bo.frame(name, cfg, args)
    src, surf = f['src'], f['surf']
    y = src @ so.LUMA
    stops_oracle = np.where(surf, bo.gain_stops(f['x_light']), bo.gain_stops(y))
    native_log = np.log2(np.maximum(y, 0.001))
    stops = {'production': bo.gain_stops(y * np.exp2(bo.production_base_log(native_log) - native_log))}
    light, _ = rs.classified_light(src, chroma_t=0.15)
    med_y = float(np.median(np.log2(np.maximum(y[surf], 0.001))))
    stops['chroma_015 (2026-11-08)'] = bo.gain_stops(np.exp2(light + med_y - float(np.median(light[surf]))))
    dirs = {'planck': planck_direction(), 'scene': scene_direction(), 'entropy': entropy_direction(src, surf & (y > 0.01))}
    kept = {}
    for dn, e in dirs.items():
        for t in THRESH:
            k = f'inv_{dn}_{t:.2f}'
            light, kept[k] = invariant_light(src, e, t)
            light = light + (med_y - float(np.median(light[surf])))
            stops[k] = bo.gain_stops(np.exp2(light))
            so.write_png(out / f'{name}_{k}_light.png', np.repeat(so.to_srgb(np.clip(np.exp2(light), 0, 1))[..., None], 3, -1))
    for t in THRESH:
        for k_max in (0.25, 0.40):
            k = f'sky_planck_{t:.2f}_k{k_max:.2f}'
            light, kept[k] = invariant_light(src, dirs['planck'], t, sky=(k_max, 0.03))
            light = light + (med_y - float(np.median(light[surf])))
            stops[k] = bo.gain_stops(np.exp2(light))
            so.write_png(out / f'{name}_{k}_light.png', np.repeat(so.to_srgb(np.clip(np.exp2(light), 0, 1))[..., None], 3, -1))
    rows_k = {}
    for t in (0.10, 0.15):
        for slack in (0.10, 0.20):
            k = f'auto_planck_{t:.2f}_s{slack:.2f}'
            light, kept[k] = invariant_light(src, dirs['planck'], t, auto=(slack, 0.03))
            rows_k[k] = invariant_light.last_k
            light = light + (med_y - float(np.median(light[surf])))
            stops[k] = bo.gain_stops(np.exp2(light))
            so.write_png(out / f'{name}_{k}_light.png', np.repeat(so.to_srgb(np.clip(np.exp2(light), 0, 1))[..., None], 3, -1))
    regions = bo.regions_of(f)
    err_prod = float(np.abs(stops['production'] - stops_oracle)[surf].mean())
    rows = {'frame_slope': rows_k, 'directions_deg': {k: float(np.degrees(np.arctan2(v[1], v[0]))) for k, v in dirs.items()},
            'kept_edge_fraction': kept, 'variants': {}}
    for k, st in stops.items():
        err = float(np.abs(st - stops_oracle)[surf].mean())
        per_region = {r: float(np.abs(st - stops_oracle)[m].mean()) for r, m in regions.items() if m.sum()}
        rows['variants'][k] = {'error_vs_oracle': err, 'gap_closed_vs_production': (err_prod - err) / err_prod,
                               'balanced_error': float(np.mean(list(per_region.values()))),
                               'region_error': per_region,
                               'region_mean_stops': {r: float(st[m].mean()) for r, m in regions.items() if m.sum()}}
    rows['oracle_region_mean_stops'] = {r: float(stops_oracle[m].mean()) for r, m in regions.items() if m.sum()}
    return rows

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--cache', type=Path, required=True)
    ap.add_argument('--width', type=int, default=1280)
    ap.add_argument('--height', type=int, default=720)
    ap.add_argument('--sun-samples', type=int, default=16)
    ap.add_argument('--sky-samples', type=int, default=96)
    ap.add_argument('--noise-codes', type=float, default=0.8)
    ap.add_argument('--seed', type=int, default=7)
    ap.add_argument('--scenes', nargs='+', default=list(bo.SCENES), choices=list(bo.SCENES))
    args = ap.parse_args()
    out = args.output
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        ap.error('output directory must be new or empty')
    out.mkdir(parents=True, exist_ok=True)
    report = {'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'args': {k: str(v) for k, v in vars(args).items()}, 'scenes': {}}
    for name in args.scenes:
        report['scenes'][name] = screen(name, bo.SCENES[name], args, out)
        r = report['scenes'][name]
        print(name, 'dirs', {k: round(v, 1) for k, v in r['directions_deg'].items()})
        for k, v in r['variants'].items():
            print(f'  {k:26s} all {v["error_vs_oracle"]:.3f} balanced {v["balanced_error"]:.3f}')
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

if __name__ == '__main__':
    main()
