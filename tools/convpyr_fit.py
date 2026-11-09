#!/usr/bin/env python3
"""Fit convolution-pyramid kernels (Farbman, Fattal & Lischinski 2011) for Neumann Poisson
integration of the colour-edge masked gradients at 1/8 resolution.

Pyramid (per level one GPU pass each way, MIRROR addressing):
  forward   a[l+1] = downsample2(h1 * a[l])
  coarsest  b[L]   = g * a[L]
  backward  b[l]   = h2 * upsample2_zero(b[l+1]) + g * a[l]
h1: separable symmetric 5-tap (3 params), h2 = k * h1, g: separable symmetric 3-tap (2 params).
Target: retinex_screen.poisson_neumann (exact) on the same gradients; loss = mean |du| after
removing means. Fit on 5 scenes, validate on the other 2. Nelder-Mead in numpy.
"""
import argparse
import json
from pathlib import Path

import numpy as np

import colour_edge_eval as ce
import colour_edge_gpu_proto as gp
import oracle_scenes as osc
import retinex_screen as rs

def conv_sep(a, k):
    r = len(k) // 2
    p = np.pad(a, ((r, r), (0, 0)), mode='symmetric')
    a = sum(k[i] * p[i:i + a.shape[0]] for i in range(len(k)))
    p = np.pad(a, ((0, 0), (r, r)), mode='symmetric')
    return sum(k[i] * p[:, i:i + a.shape[1]] for i in range(len(k)))

def kernels(prm):
    a, b, c, k, d, e = prm
    h1 = np.array([a, b, c, b, a]); g = np.array([d, e, d])
    return h1, k * h1, g

def pyramid(f, prm, levels):
    h1, h2, g = kernels(prm)
    a = [f]
    for _ in range(levels):
        a.append(conv_sep(a[-1], h1)[::2, ::2])
    b = conv_sep(a[-1], g)
    for l in range(levels - 1, -1, -1):
        up = np.zeros_like(a[l]); up[::2, ::2] = b[:up[::2, ::2].shape[0], :up[::2, ::2].shape[1]]
        b = conv_sep(up, h2) + conv_sep(a[l], g)
    return b

def nelder_mead(fun, x0, step, iters=400):
    n = len(x0); pts = [np.array(x0, float)] + [np.array(x0, float) + np.eye(n)[i] * step[i] for i in range(n)]
    vals = [fun(p) for p in pts]
    for _ in range(iters):
        o = np.argsort(vals); pts = [pts[i] for i in o]; vals = [vals[i] for i in o]
        c = np.mean(pts[:-1], 0); xr = c + (c - pts[-1]); fr = fun(xr)
        if fr < vals[0]:
            xe = c + 2 * (c - pts[-1]); fe = fun(xe)
            pts[-1], vals[-1] = (xe, fe) if fe < fr else (xr, fr)
        elif fr < vals[-2]:
            pts[-1], vals[-1] = xr, fr
        else:
            xc = c + 0.5 * (pts[-1] - c); fc = fun(xc)
            if fc < vals[-1]:
                pts[-1], vals[-1] = xc, fc
            else:
                pts = [pts[0]] + [pts[0] + 0.5 * (p - pts[0]) for p in pts[1:]]; vals = [vals[0]] + [fun(p) for p in pts[1:]]
    i = int(np.argmin(vals)); return pts[i], vals[i]

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--cache', type=Path, required=True)
    ap.add_argument('--levels', type=int, default=5)
    args = ap.parse_args()
    a = argparse.Namespace(cache=args.cache, width=1280, height=720, sun_samples=16, sky_samples=96, noise_codes=0.8, seed=7)
    data = {}
    for name in osc.ALL:
        f = osc.frame(name, a); s = ce.down(f['src'], 8)
        dirs, _, _ = gp.directions(s)
        gx, gy, _ = gp.masked_gradients(s, dirs)
        u = rs.poisson_neumann(gx, gy)
        data[name] = (gp.divergence(gx, gy), u - u.mean())
    train = ['daylight', 'interior', 'colourful_noon', 'overcast', 'lamp_interior']
    val = [n for n in data if n not in train]
    def loss(prm, names):
        return float(np.mean([np.abs((lambda v: v - v.mean())(pyramid(data[n][0], prm, args.levels)) - data[n][1]).mean() for n in names]))
    x0 = [0.15, 0.5, 0.7, 1.0, 0.1, 0.8]
    best, bl = nelder_mead(lambda p: loss(p, train), x0, [0.05, 0.1, 0.1, 0.3, 0.05, 0.2], iters=600)
    res = {'levels': args.levels, 'params': best.tolist(), 'train_loss': bl, 'val_loss': loss(best, val),
           'per_scene_stops': {n: loss(best, [n]) for n in data},
           'solution_range_stops': {n: float(np.ptp(data[n][1])) for n in data}}
    print(json.dumps(res, indent=1))
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / f'convpyr_L{args.levels}.json').write_text(json.dumps(res, indent=1))

if __name__ == '__main__':
    main()
