#!/usr/bin/env python3
"""Material-veto light estimate screen (CPU only).

Colour-edge col4 keeps a luminance step only when a light colour explains it (default: material).
On game frames that default failed where shade is not bluer (warm bounce, foliage, uniformly dim
rooms). This screen flips the default: every 1/8-lane step is light (production-like) unless its
chromaticity change is large AND unexplained by every shade direction (sky, frame shade, 2 k-means):
  material  <=>  |dc| > t  and  min_d |perp_d(dc)| > t
Variants veto_t.15 / .25 / .35; Poisson (Neumann) of the kept steps, JBU to full res. Scored like
flatfield_screen (stronger lift curve, oracle curve; region-balanced) and rendered as 0-100 maps
with a 3-zone overlay (shadow / mid / light, relative to the frame lit level) for game frames.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

import brightness_oracle as bo
import colour_edge_eval as ce
import colour_edge_gpu_proto as gp
import invariant_screen as inv
import oracle_scenes as osc
import retinex_screen as rs
import shadow_oracle as so

EPS = 0.002

def directions(s):
    return [ce.sky_dir(), ce.shade_direction(s)] + ce.kmeans_dirs(s, 2)

def veto_low(s, t):
    ly = np.log2(np.maximum(s @ so.LUMA, EPS)); lc = inv.logchroma(np.maximum(s, EPS))
    gx, gy = np.diff(ly, axis=1), np.diff(ly, axis=0); cx, cy = np.diff(lc, axis=1), np.diff(lc, axis=0)
    dirs = directions(s)
    def material(c):
        perp = np.min([np.abs(c @ np.array([-d[1], d[0]])) for d in dirs], 0)
        return (np.linalg.norm(c, axis=-1) > t) & (perp > t)
    return rs.poisson_neumann(gx * ~material(cx), gy * ~material(cy)), (material(cx).mean() + material(cy).mean()) / 2

def estimate(src, kind, fac=8):
    s = ce.down(src, fac)
    if kind == 'col4_jbu':
        low = ce.light_rule(s, dirs=directions(s)); frac = None
    else:
        low, frac = veto_low(s, float(kind.split('_t')[1]))
    return ce.up_jbu(low, s, src, fac), frac

def norm01(lg):
    lo, hi = np.percentile(lg, [1, 99]); return np.clip((lg - lo) / max(hi - lo, 1e-6), 0, 1)

def zones(lg):
    """Shadow (blue) > 2 stops below lit level, mid (green) 0.75-2, light (amber) within 0.75."""
    lit = lg.mean() + 1.2816 * lg.std(); d = lit - lg
    z = np.where(d > 2.0, 0, np.where(d > 0.75, 1, 2))
    return np.array([[0.25, 0.45, 1.0], [0.3, 0.8, 0.4], [1.0, 0.75, 0.2]])[z]

KINDS = ['col4_jbu', 'veto_t.15', 'veto_t.25', 'veto_t.35']

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--cache', required=True, type=Path)
    ap.add_argument('--game', nargs='*', default=[], type=Path)
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    a = argparse.Namespace(cache=args.cache, width=1280, height=720, sun_samples=16, sky_samples=96, noise_codes=0.8, seed=7)
    res = {}
    for name in osc.ALL:
        f = osc.frame(name, a); src, surf = f['src'], f['surf']; y = src @ so.LUMA
        reg = {r: mk for r, mk in bo.regions_of(f).items() if mk.sum() > 500}
        med = float(np.median(np.log2(np.maximum(y, 0.001))[surf]))
        ests = {'production': bo.production_base_log(np.log2(np.maximum(y, 0.001)))}
        for k in KINDS:
            lg, _ = estimate(src, k); ests[k] = lg + med - float(np.median(lg[surf]))
        row = {}
        for curve, fn in (('strong', gp.strong), ('oracle', bo.gain_stops)):
            tr = np.where(surf, fn(f['x_light']), fn(y))
            for k, lg in ests.items():
                row.setdefault(k, {})[curve] = float(np.mean([np.abs(fn(np.exp2(lg)) - tr)[mk].mean() for mk in reg.values()]))
        res[name] = row
        print(name, '  '.join(f'{k} {v["strong"]:.3f}/{v["oracle"]:.3f}' for k, v in row.items()), flush=True)
    keys = list(next(iter(res.values())))
    for c in ('strong', 'oracle'):
        print(f'\n{c}: MEAN ' + '  '.join(f'{k} {np.mean([r[k][c] for r in res.values()]):.3f}' for k in keys)
              + '   WINS vs prod ' + ' '.join(f'{k}:{sum(r[k][c] < r["production"][c] for r in res.values())}' for k in keys[1:]))
    for g in args.game:
        im = np.array(Image.open(g).convert('RGB'), np.float64) / 255
        src = np.where(im <= 0.04045, im / 12.92, ((im + 0.055) / 1.055) ** 2.4)
        h, w = src.shape[0] // 8 * 8, src.shape[1] // 8 * 8; src, im = src[:h, :w], im[:h, :w]
        y = src @ so.LUMA
        prod = bo.production_base_log(np.log2(np.maximum(y, 0.001)))
        cols = [('production', prod)] + [(k, estimate(src, k)[0]) for k in ('col4_jbu', 'veto_t.25')]
        top = np.concatenate([im] + [norm01(l)[..., None].repeat(3, -1) for _, l in cols], 1)
        bot = np.concatenate([im] + [0.45 * zones(l) + 0.55 * (im ** 1.0) * zones(l) for _, l in cols], 1)
        Image.fromarray((np.concatenate([top, bot], 0) * 255).astype(np.uint8)).resize((w * 2, h)).save(args.output / f'game_{g.stem}.jpg', quality=88)
        fr = {k: estimate(src, k)[1] for k in KINDS[1:]}
        print('game', g.stem, 'vetoed edge fraction', {k: round(v, 3) for k, v in fr.items()}, flush=True)
    (args.output / 'report.json').write_text(json.dumps(res, indent=1))

if __name__ == '__main__':
    main()
