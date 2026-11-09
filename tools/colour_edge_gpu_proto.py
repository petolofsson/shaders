#!/usr/bin/env python3
"""GPU-shaped CPU prototype of the colour-edge light estimate (col4 + edge-aware upsampling).

Differences from colour_edge_eval (exact reference):
  directions  one sparse reduction (S x S samples of the 1/8 lane): frame shade direction from
              soft dark/bright means; two extra directions from dark samples split by the sign of
              their component across the sky axis (replaces k-means)
  solver      cascadic multigrid: divergence at 1/8, restricted to 1/16..1/128, J0 Jacobi sweeps at
              the coarsest level, then per level bilinear prolongation + J weighted-Jacobi sweeps
              (each sweep = one GPU pass); Neumann borders via clamped reads
  anchor      sparse-sample means instead of medians
Every pass corresponds to one full-screen pass on a low-resolution target.
"""
import argparse
import json
from pathlib import Path

import numpy as np

import brightness_oracle as bo
import colour_edge_eval as ce
import invariant_screen as inv
import oracle_scenes as osc
import shadow_oracle as so

EPS = 0.002

def directions(s, S=24):
    """Sparse reduction over an S x S grid of the 1/8 lane (one GPU pass to a 1x1 target)."""
    h, w = s.shape[:2]
    ys = ((np.arange(S) + 0.5) * h / S).astype(int); xs = ((np.arange(S) + 0.5) * w / S).astype(int)
    smp = s[ys][:, xs].reshape(-1, 3)
    y = smp @ so.LUMA; ly = np.log2(np.maximum(y, EPS))
    lo_t, hi_t = np.percentile(ly, 50), np.percentile(ly, 90)   # GPU: highway percentiles
    w_dark = (1 - so.smooth(lo_t - 0.25, lo_t + 0.25, ly)) * (y > 0.004)
    w_lit = so.smooth(hi_t - 0.25, hi_t + 0.25, ly)
    lit = inv.logchroma((smp * w_lit[:, None]).sum(0) / max(w_lit.sum(), 1e-6))
    sky = ce.sky_dir(); n_sky = np.array([-sky[1], sky[0]])
    side = inv.logchroma(np.maximum(smp, EPS)) @ n_sky
    out = []
    for wsel in (w_dark, w_dark * (side > np.median(side[w_dark > 0.5]) if (w_dark > 0.5).any() else 0),
                 w_dark * (side <= np.median(side[w_dark > 0.5]) if (w_dark > 0.5).any() else 0)):
        if np.sum(wsel) < 1e-3:
            continue
        d = inv.logchroma((smp * np.asarray(wsel)[:, None]).sum(0) / np.sum(wsel)) - lit
        n = np.linalg.norm(d)
        if n > 1e-3: out.append(d / n)
    dirs = [sky] + out
    anchor = float(ly.mean())
    return dirs, anchor, smp

def masked_gradients(s, dirs, t=0.10):
    ly = np.log2(np.maximum(s @ so.LUMA, EPS)); lc = inv.logchroma(np.maximum(s, EPS))
    gx, gy = np.diff(ly, axis=1), np.diff(ly, axis=0); cx, cy = np.diff(lc, axis=1), np.diff(lc, axis=0)
    kx = np.zeros_like(gx, bool); ky = np.zeros_like(gy, bool)
    for d in dirs:
        kx |= ce.keep(gx, cx, d, t); ky |= ce.keep(gy, cy, d, t)
    return gx * kx, gy * ky, ly

def divergence(gx, gy):
    h, w = gy.shape[0] + 1, gx.shape[1] + 1
    div = np.zeros((h, w))
    div[:, :-1] += gx; div[:, 1:] -= gx; div[:-1, :] += gy; div[1:, :] -= gy
    return div

def neighbours(u):
    p = np.pad(u, 1, mode='edge')
    return p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]

def jacobi(u, f, sweeps, omega=0.8):
    """Solve sum(nb) - 4u = -f (Neumann via edge clamp): u <- (1-w)u + w(sum(nb) + f)/4."""
    for _ in range(sweeps):
        u = (1 - omega) * u + omega * (neighbours(u) + f) / 4
    return u

def restrict(f):
    h, w = f.shape[0] // 2 * 2, f.shape[1] // 2 * 2
    g = f[:h, :w].reshape(h // 2, 2, w // 2, 2).sum((1, 3))     # sum: h^2 scaling of the Laplacian
    return g

def prolong(u, shape):
    return ce.up(u, shape)

def multigrid(f, levels=4, j0=40, j=2):
    fs = [f]
    for _ in range(levels):
        fs.append(restrict(fs[-1]))
    u = jacobi(np.zeros_like(fs[-1]), fs[-1], j0)
    passes = j0
    for lv in range(levels - 1, -1, -1):
        u = jacobi(prolong(u, fs[lv].shape), fs[lv], j)
        passes += j
    return u, passes + levels + 1          # + restriction passes + divergence pass

def estimate(src, fac=8, levels=4, j0=40, j=2, S=24):
    s = ce.down(src, fac)
    dirs, anchor, _ = directions(s, S)
    gx, gy, ly = masked_gradients(s, dirs)
    # Laplacian(u) = div (retinex_screen.poisson_neumann convention) -> Jacobi rhs f = -div.
    u, passes = multigrid(-divergence(gx, gy), levels, j0, j)
    lj = ce.up_jbu(u, s, src, fac)
    lj = lj - lj.mean() + anchor
    return lj, passes + 2      # + reduction pass + JBU pass

def strong(x):
    lx = np.log2(np.maximum(x, 1e-6))
    return bo.LIFT_STOPS * so.smooth(np.log2(0.004), np.log2(0.02), lx) * (1 - so.smooth(np.log2(0.05), np.log2(0.3), lx))

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--cache', type=Path, required=True)
    args = ap.parse_args()
    a = argparse.Namespace(cache=args.cache, width=1280, height=720, sun_samples=16, sky_samples=96, noise_codes=0.8, seed=7)
    configs = {'exact col4_jbu': None, 'gpu L4 j0=40 j=2': (4, 40, 2), 'gpu L4 j0=20 j=2': (4, 20, 2),
               'gpu L4 j0=20 j=1': (4, 20, 1), 'gpu L5 j0=10 j=2': (5, 10, 2), 'gpu L3 j0=40 j=2': (3, 40, 2)}
    res = {}
    for name in osc.ALL:
        f = osc.frame(name, a); src, surf = f['src'], f['surf']; y = src @ so.LUMA
        reg = {r: m for r, m in bo.regions_of(f).items() if m.sum() > 500}
        tr = np.where(surf, strong(f['x_light']), strong(y))
        err = lambda lg: float(np.mean([np.abs(strong(np.exp2(lg)) - tr)[m].mean() for m in reg.values()]))
        row = {'production': (err(bo.production_base_log(np.log2(np.maximum(y, 0.001)))), 0)}
        for k, cfg in configs.items():
            if cfg is None:
                row[k] = (err(ce.estimates(src, y, surf)['col4_jbu']), 0)
            else:
                lg, p = estimate(src, 8, *cfg); row[k] = (err(lg), p)
        res[name] = row
        print(name, '  '.join(f'{k}: {v[0]:.3f}' for k, v in row.items()), flush=True)
    keys = list(next(iter(res.values())))
    print('\nMEAN  ' + '  '.join(f'{k}: {np.mean([r[k][0] for r in res.values()]):.3f}' + (f' ({next(iter(res.values()))[k][1]} passes)' if next(iter(res.values()))[k][1] else '') for k in keys))
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'gpu_proto.json').write_text(json.dumps(res, indent=1))

if __name__ == '__main__':
    main()
