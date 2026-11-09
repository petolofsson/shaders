#!/usr/bin/env python3
"""Evaluate colour-edge light estimates on the extended oracle set (tools/oracle_scenes.py).

Methods (edge rules from research/2026-11-09_colour_edge_light_material.md; Poisson at 1/8 res):
  production   production tonal base (CPU replica of TonalIlluminationLog)
  inv          Finlayson-invariant edges, t .05
  sky          inv + daylight sign/magnitude rule, t .10, k .40
  shade1       sky-style rule along the frame's own lit->shade direction
  colN         union of shade1, sky and N-2 k-means shade directions (N = 3, 4, 5)
Curves:
  oracle       brightness_oracle.gain_stops (idealised lift/deepen curve)
  prodlift     production shadow lift: log2(1 + P*0.1875*smoothstep(.35, 0, base)), P = 1
               (grade.fx:727-731, GZW SHADOW_LIFT_STRENGTH .75; scene P held fixed)
Error = |curve(estimate) - curve(true light)| in stops, region-balanced. CPU only.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

import brightness_oracle as bo
import invariant_screen as inv
import oracle_scenes as osc
import retinex_screen as rs
import shadow_oracle as so

def down(a, f):
    h, w = a.shape[0] // f * f, a.shape[1] // f * f
    return a[:h, :w].reshape(h // f, f, w // f, f, *a.shape[2:]).mean((1, 3))

def up(a, shape):
    return np.array(Image.fromarray(a.astype(np.float32)).resize((shape[1], shape[0]), Image.BILINEAR))

def up_jbu(low, src_low, src, f, r=2, sigma_s=1.0, sigma_l=0.35, sigma_c=0.08):
    """Joint bilateral upsampling (Kopf et al. 2007): each full-res pixel averages nearby
    low-res light samples weighted by spatial distance and by guide similarity
    (log2 luminance and log chromaticity of the full-res pixel vs the low-res sample)."""
    eps = 0.002
    h, w = src.shape[:2]; hl, wl = low.shape
    gl_full = np.log2(np.maximum(src @ so.LUMA, eps)); gc_full = inv.logchroma(np.maximum(src, eps))
    gl_low = np.log2(np.maximum(src_low @ so.LUMA, eps)); gc_low = inv.logchroma(np.maximum(src_low, eps))
    yy = (np.arange(h) + 0.5) / f - 0.5; xx = (np.arange(w) + 0.5) / f - 0.5
    y0 = np.floor(yy).astype(int); x0 = np.floor(xx).astype(int)
    acc = np.zeros((h, w)); wsum = np.zeros((h, w))
    for dy in range(-r + 1, r + 1):
        for dx in range(-r + 1, r + 1):
            yi = np.clip(y0 + dy, 0, hl - 1); xi = np.clip(x0 + dx, 0, wl - 1)
            ds = (yy - (y0 + dy))[:, None] ** 2 + (xx - (x0 + dx))[None, :] ** 2
            L = low[yi][:, xi]; Gl = gl_low[yi][:, xi]; Gc = gc_low[yi][:, xi]
            wt = (np.exp(-ds / (2 * sigma_s ** 2)) * np.exp(-(gl_full - Gl) ** 2 / (2 * sigma_l ** 2))
                  * np.exp(-((gc_full - Gc) ** 2).sum(-1) / (2 * sigma_c ** 2)))
            acc += wt * L; wsum += wt
    fallback = up(low, (h, w))
    return np.where(wsum > 1e-6, acc / np.maximum(wsum, 1e-12), fallback)

def sky_dir():
    e = inv.planck_direction()
    return -e if e[0] > 0 else e          # warm -> blue (lit -> skylit shade)

def shade_direction(src):
    y = src @ so.LUMA; m = y > 0.004
    hi = y >= np.percentile(y[m], 90); lo = m & (y <= np.percentile(y[m], 50))
    d = inv.logchroma(src[lo].mean(0)) - inv.logchroma(src[hi].mean(0)); n = np.linalg.norm(d)
    return d / n if n > 1e-3 else sky_dir()

def kmeans_dirs(src, n, seed=0):
    if n <= 0:
        return []
    y = src @ so.LUMA; m = y > 0.004; hi = y >= np.percentile(y[m], 90); lo = m & (y <= np.percentile(y[m], 50))
    lc = inv.logchroma(src[lo]); rng = np.random.default_rng(seed); c = lc[rng.choice(len(lc), n, replace=False)]
    for _ in range(20):
        lab = np.argmin(((lc[:, None] - c[None]) ** 2).sum(-1), 1)
        c = np.array([lc[lab == i].mean(0) if (lab == i).any() else c[i] for i in range(n)])
    ref = inv.logchroma(src[hi].mean(0)); out = []
    for ci in c:
        d = ci - ref; nn = np.linalg.norm(d)
        if nn > 1e-3: out.append(d / nn)
    return out

def keep(dl, cd, e, t, k=0.40, tol=0.03):
    """Light edge along shade direction e (lit -> shade)."""
    perp = cd @ np.array([-e[1], e[0]]); al = cd @ e
    return (np.abs(perp) < t) & (al * (-dl) >= -tol * np.abs(dl) - 1e-9) & (np.abs(al) <= k * np.abs(dl) + tol)

def light_rule(src, dirs=None, inv_t=None, t=0.10):
    eps = 0.002
    ly = np.log2(np.maximum(src @ so.LUMA, eps)); lc = inv.logchroma(np.maximum(src, eps))
    gx, gy = np.diff(ly, axis=1), np.diff(ly, axis=0); cx, cy = np.diff(lc, axis=1), np.diff(lc, axis=0)
    if inv_t is not None:
        e = sky_dir(); n = np.array([-e[1], e[0]])
        kx = np.abs(cx @ n) < inv_t; ky = np.abs(cy @ n) < inv_t
    else:
        kx = np.zeros_like(gx, bool); ky = np.zeros_like(gy, bool)
        for d in dirs:
            kx |= keep(gx, cx, d, t); ky |= keep(gy, cy, d, t)
    return rs.poisson_neumann(gx * kx, gy * ky)

def estimates(src, y, surf, fac=8):
    native = np.log2(np.maximum(y, 0.001))
    out = {'production': bo.production_base_log(native)}
    s = down(src, fac); gb = shade_direction(s); sk = sky_dir()
    rules = {'inv': dict(inv_t=0.05), 'sky': dict(dirs=[sk]), 'shade1': dict(dirs=[gb])}
    for n in (3, 4, 5):
        rules[f'col{n}'] = dict(dirs=[gb, sk] + kmeans_dirs(s, n - 2))
    med = float(np.median(native[surf]))
    for k, kw in rules.items():
        low = light_rule(s, **kw)
        lg = up(low, y.shape)
        out[k] = lg + med - float(np.median(lg[surf]))
        if k == 'col4':
            lj = up_jbu(low, s, src, fac)
            out['col4_jbu'] = lj + med - float(np.median(lj[surf]))
    return out

def prodlift_stops(x, P=1.0):
    return np.log2(1 + P * 0.1875 * so.smooth(0.35, 0.0, np.clip(x, 0, 1)))

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
    ap.add_argument('--scenes', nargs='+', default=osc.ALL, choices=osc.ALL)
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    rep = {'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'scenes': {}}
    for name in args.scenes:
        f = osc.frame(name, args); src, surf = f['src'], f['surf']; y = src @ so.LUMA
        regions = {r: m for r, m in bo.regions_of(f).items() if m.sum() > 500}
        truth_o = np.where(surf, bo.gain_stops(f['x_light']), bo.gain_stops(y))
        truth_p = np.where(surf, prodlift_stops(f['x_light']), prodlift_stops(y))
        row = {}
        for k, lg in estimates(src, y, surf).items():
            x = np.exp2(lg)
            so_, sp = bo.gain_stops(x), prodlift_stops(x)
            row[k] = {c: {'balanced': float(np.mean([np.abs(st - tr)[m].mean() for m in regions.values()])),
                          'regions': {r: float(np.abs(st - tr)[m].mean()) for r, m in regions.items()}}
                      for c, st, tr in (('oracle', so_, truth_o), ('prodlift', sp, truth_p))}
        rep['scenes'][name] = row
        print(name, '  '.join(f'{k} {v["oracle"]["balanced"]:.3f}/{v["prodlift"]["balanced"]:.3f}' for k, v in row.items()), flush=True)
    (args.output / 'report.json').write_text(json.dumps(rep, indent=2) + '\n')
    methods = list(next(iter(rep['scenes'].values())))
    for c in ('oracle', 'prodlift'):
        print(f'\n{c}: balanced error per scene (rows) and mean')
        print(f'{"scene":16s}' + ''.join(f'{m:>11s}' for m in methods))
        for sc, row in rep['scenes'].items():
            print(f'{sc:16s}' + ''.join(f'{row[m][c]["balanced"]:11.3f}' for m in methods))
        print(f'{"MEAN":16s}' + ''.join(f'{np.mean([r[m][c]["balanced"] for r in rep["scenes"].values()]):11.3f}' for m in methods))
        print(f'{"WINS vs prod":16s}' + ''.join(f'{sum(r[m][c]["balanced"] < r["production"][c]["balanced"] for r in rep["scenes"].values()):>11d}' for m in methods))

if __name__ == '__main__':
    main()
