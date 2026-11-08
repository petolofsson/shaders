#!/usr/bin/env python3
"""Screen single-image light/material separation against the brightness oracle.

Gradient-classification Retinex (Land & McCann 1971; Horn 1974; the chromaticity
rule follows Funt, Drew & Brockington 1992): classify each log-luminance edge as
material or light, drop material edges, and reintegrate the remaining gradient
field (Neumann Poisson solve) as an illumination estimate. The oracle tonal
curve is then evaluated on that estimate and scored against the exact-light
oracle on the same 8-bit frames. CPU only; no shader work.
"""
import argparse
import hashlib
import html
import json
from pathlib import Path

import numpy as np

import brightness_oracle as bo
import shadow_oracle as so

def poisson_neumann(gx, gy):
    """Least-squares integration of forward-difference gradients with zero-flux
    borders: mirror the divergence and solve the periodic Poisson problem by FFT."""
    h, w = gy.shape[0] + 1, gx.shape[1] + 1
    div = np.zeros((h, w))
    div[:, :-1] += gx; div[:, 1:] -= gx
    div[:-1, :] += gy; div[1:, :] -= gy
    big = np.concatenate([div, div[::-1]], 0)
    big = np.concatenate([big, big[:, ::-1]], 1)
    ky = 2 * np.cos(2 * np.pi * np.arange(2 * h) / (2 * h)) - 2
    kx = 2 * np.cos(2 * np.pi * np.arange(2 * w) / (2 * w)) - 2
    lam = ky[:, None] + kx[None, :]
    lam[0, 0] = 1.0
    sol = np.fft.ifft2(np.fft.fft2(big) / lam)
    sol = np.real(sol)[:h, :w]
    return sol - sol.mean()

def classified_light(src, mag_t=None, chroma_t=None, smooth_r=1):
    """Illumination log2 estimate, offset arbitrary. An edge counts as light when it is
    below every supplied threshold; material edges are removed before integration."""
    eps = 0.002
    logc = np.log2(np.maximum(src, eps))
    logc = np.stack([bo.box_blur(logc[..., c], smooth_r) for c in range(3)], -1)
    ly = np.log2(np.maximum(bo.box_blur(src @ so.LUMA, smooth_r), eps))
    gx = np.diff(ly, axis=1); gy = np.diff(ly, axis=0)
    keep_x = np.ones_like(gx, dtype=bool); keep_y = np.ones_like(gy, dtype=bool)
    if mag_t is not None:
        keep_x &= np.abs(gx) < mag_t; keep_y &= np.abs(gy) < mag_t
    if chroma_t is not None:
        c1 = logc[..., 0] - logc[..., 1]; c2 = logc[..., 2] - logc[..., 1]
        cx = np.abs(np.diff(c1, axis=1)) + np.abs(np.diff(c2, axis=1))
        cy = np.abs(np.diff(c1, axis=0)) + np.abs(np.diff(c2, axis=0))
        keep_x &= cx < chroma_t; keep_y &= cy < chroma_t
    return poisson_neumann(gx * keep_x, gy * keep_y), float((keep_x.mean() + keep_y.mean()) / 2)

VARIANTS = {
    'mag_025': {'mag_t': 0.25},
    'mag_050': {'mag_t': 0.50},
    'mag_100': {'mag_t': 1.00},
    'chroma_015': {'chroma_t': 0.15},
    'mag050_chroma015': {'mag_t': 0.50, 'chroma_t': 0.15},
}

def screen(name, cfg, args, out):
    f = bo.frame(name, cfg, args)
    src, surf = f['src'], f['surf']
    y = src @ so.LUMA
    stops_oracle = np.where(surf, bo.gain_stops(f['x_light']), bo.gain_stops(y))
    native_log = np.log2(np.maximum(y, 0.001))
    stops = {'global': bo.gain_stops(y),
             'production': bo.gain_stops(y * np.exp2(bo.production_base_log(native_log) - native_log))}
    kept = {}
    med_y = float(np.median(np.log2(np.maximum(y[surf], 0.001))))
    for v, prm in VARIANTS.items():
        light, kept[v] = classified_light(src, **prm)
        light = light + (med_y - float(np.median(light[surf])))     # same scale as the pixel median
        stops[v] = bo.gain_stops(np.exp2(light))
        so.write_png(out / f'{name}_{v}_light.png', np.repeat(so.to_srgb(np.clip(np.exp2(light), 0, 1))[..., None], 3, -1))
    # Naive control: one uniform gain everywhere (the oracle's median surface gain).
    stops['uniform'] = np.full_like(y, float(np.median(stops_oracle[surf])))
    stops['oracle'] = stops_oracle
    regions = bo.regions_of(f)
    err_prod = float(np.abs(stops['production'] - stops_oracle)[surf].mean())
    rows = {'kept_edge_fraction': kept, 'variants': {}}
    vis = lambda st: np.clip(0.5 + st / (2 * max(bo.LIFT_STOPS, bo.DEEPEN_STOPS)), 0, 1)
    for k, st in stops.items():
        err = float(np.abs(st - stops_oracle)[surf].mean())
        per_region = [float(np.abs(st - stops_oracle)[m].mean()) for m in regions.values() if m.sum()]
        row = {'error_vs_oracle': err, 'gap_closed_vs_production': (err_prod - err) / err_prod,
               # Each material/light region weighted equally, so a dominant region cannot hide failures.
               'balanced_error': float(np.mean(per_region)),
               'gain_roughness': float(np.abs(st - bo.box_blur(st, 4))[surf].mean())}
        for r, m in regions.items():
            if m.sum():
                row[f'{r}_mean_stops'] = float(st[m].mean())
        rows['variants'][k] = row
        so.write_png(out / f'{name}_{k}.png', so.to_srgb(bo.apply_gain(src, st)))
        g = np.stack([vis(st)] * 3, -1); g[..., 2] = 1 - g[..., 0]
        so.write_png(out / f'{name}_gain_{k}.png', g)
    so.write_png(out / f'{name}_source.png', so.to_srgb(src))
    so.write_png(out / f'{name}_light_truth.png', np.repeat(so.to_srgb(f['x_light'])[..., None], 3, -1))
    return rows

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path, help='new or empty directory')
    ap.add_argument('--cache', type=Path, required=True, help='brightness_oracle frame cache')
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
    report = {'tool_sha256': digest(__file__), 'oracle_tool_sha256': digest(bo.__file__),
              'renderer_sha256': digest(so.__file__), 'args': {k: str(v) for k, v in vars(args).items()},
              'variants': VARIANTS, 'classification': 'log2 luminance and log chromaticity after 3x3 box; edge kept as light below all thresholds',
              'scenes': {}}
    for name in args.scenes:
        report['scenes'][name] = screen(name, bo.SCENES[name], args, out)
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    names = ['source', 'global', 'production', *VARIANTS, 'uniform', 'oracle']
    blocks = []
    for sc in args.scenes:
        row = report['scenes'][sc]['variants']
        btn = ''.join(f'<button data-s="{sc}" data-k="{k}">{html.escape(k)}</button>' for k in names)
        gbtn = ''.join(f'<button data-s="{sc}" data-k="gain_{k}">gain {html.escape(k)}</button>' for k in names[1:])
        lbtn = ''.join(f'<button data-s="{sc}" data-k="{k}_light">light {html.escape(k)}</button>' for k in VARIANTS) \
            + f'<button data-s="{sc}" data-k="light_truth">light truth</button>'
        tab = '<table><tr><th>variant</th><th>error vs oracle</th><th>region-balanced error</th><th>gap closed vs production</th><th>roughness</th></tr>' + ''.join(
            f'<tr><td>{k}</td><td>{v["error_vs_oracle"]:.3f}</td><td>{v["balanced_error"]:.3f}</td><td>{100 * v["gap_closed_vs_production"]:+.0f}%</td><td>{v["gain_roughness"]:.3f}</td></tr>'
            for k, v in row.items()) + '</table>'
        blocks.append(f'<h2>{sc}</h2><div>{btn}</div><div>{gbtn}</div><div>{lbtn}</div><img id="img_{sc}" src="{sc}_source.png">{tab}')
    page = f'''<!doctype html><meta charset="utf-8"><title>Retinex screen</title>
<style>body{{background:#16181b;color:#e8e8e8;font:15px system-ui;margin:1.5rem}}button{{margin:2px;padding:.3rem .5rem;background:#2a2d31;color:#eee;border:1px solid #555;cursor:pointer}}
button.on{{background:#4a6;color:#000}}img{{width:100%;display:block;margin:.5rem 0}}table{{border-collapse:collapse;margin-bottom:2rem}}td,th{{border:1px solid #444;padding:.25rem .5rem}}</style>
<h1>Light/material separation screen</h1><p>Same 8-bit frames and tonal curve as the brightness oracle. Each Retinex variant reintegrates the edges it classifies as light. Gain maps: yellow = lift, blue = deepen.</p>
{"".join(blocks)}
<script>document.querySelectorAll('button').forEach(b=>b.onclick=()=>{{document.getElementById('img_'+b.dataset.s).src=b.dataset.s+'_'+b.dataset.k+'.png';
document.querySelectorAll('button[data-s="'+b.dataset.s+'"]').forEach(x=>x.classList.toggle('on',x===b));}});</script>'''
    (out / 'review.html').write_text(page)
    for sc in args.scenes:
        print(sc, {k: (round(v['error_vs_oracle'], 3), round(v['balanced_error'], 3)) for k, v in report['scenes'][sc]['variants'].items()})

if __name__ == '__main__':
    main()
