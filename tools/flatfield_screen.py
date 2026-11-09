#!/usr/bin/env python3
"""Flat-field light estimate screen (CPU only): light = brightness relative to the lit level of
pixels with the same material colour, borrowing astronomy flat-fielding / MRI bias-field ideas.

At the 1/8 lane: soft bins over log chromaticity (ln R/G, ln B/G) stand in for materials. Per bin the
lit reference R_b = weighted mean + 1.28 sd of log2 luminance (~p90, GPU-reducible). A pixel's light
is ly - sum_b m_b R_b (stops below its material's lit level). Colourful pixels are trusted; neutral and
near-black ones take a confidence-weighted spatial average (normalised convolution). JBU to full res.
Variants:
  ff_iso    isotropic bins (sigma .12)
  ff_aniso  bins wide along the Planck (warm<->blue) axis, narrow across it: daylight shade and warm
            bounce shift colour mostly along that axis, so the material keeps its bin in shadow
Compared with production and col4_jbu (colour_edge_eval) on the 7 oracle scenes (region-balanced
error of the stronger lift curve and the oracle curve) and rendered as per-frame 0-100 light maps
(p1 black, p99 white, even in stops) for game frames.
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
import shadow_oracle as so

EPS = 0.002

def gauss_blur(a, sigma):
    r = int(3 * sigma) + 1; x = np.arange(-r, r + 1); k = np.exp(-x * x / (2 * sigma * sigma)); k /= k.sum()
    p = np.pad(a, ((r, r), (0, 0)), mode='edge'); a = sum(k[i] * p[i:i + a.shape[0]] for i in range(len(k)))
    p = np.pad(a, ((0, 0), (r, r)), mode='edge'); return sum(k[i] * p[:, i:i + a.shape[1]] for i in range(len(k)))

def flatfield_low(s, aniso, sig=0.12, sig_along=0.40, step=0.15, rng=1.5, min_n=12.0, spatial=3.0):
    ly = np.log2(np.maximum(s @ so.LUMA, EPS)); lc = inv.logchroma(np.maximum(s, EPS))
    e = ce.sky_dir(); n = np.array([-e[1], e[0]])
    ax = np.arange(-rng, rng + 1e-9, step); cx, cy = np.meshgrid(ax, ax); cen = np.stack([cx.ravel(), cy.ravel()], 1)
    d = lc.reshape(-1, 1, 2) - cen[None]
    if aniso:
        q = (d @ e) ** 2 / (2 * sig_along ** 2) + (d @ n) ** 2 / (2 * sig ** 2)
    else:
        q = (d ** 2).sum(-1) / (2 * sig ** 2)
    m = np.exp(-q); m /= np.maximum(m.sum(1, keepdims=True), 1e-12)          # soft membership, P x B
    v = ly.reshape(-1)
    nb = m.sum(0); mu = (m * v[:, None]).sum(0) / np.maximum(nb, 1e-9)
    sd = np.sqrt(np.maximum((m * v[:, None] ** 2).sum(0) / np.maximum(nb, 1e-9) - mu ** 2, 0))
    ref = mu + 1.2816 * sd
    valid = (nb >= min_n).astype(float)
    mv = m * valid[None]; cover = mv.sum(1)
    dstops = (v - (mv * ref[None]).sum(1) / np.maximum(cover, 1e-9)).reshape(ly.shape)
    dstops = np.minimum(dstops, 0.5)
    sat = np.linalg.norm(lc, axis=-1)
    conf = (so.smooth(0.05, 0.25, sat) * cover.reshape(ly.shape)
            * so.smooth(np.log2(0.003), np.log2(0.01), ly)) + 1e-4
    fill = gauss_blur(conf * dstops, spatial) / gauss_blur(conf, spatial)
    return conf * dstops + (1 - conf) * fill

def estimate(src, kind, fac=8):
    s = ce.down(src, fac)
    if kind == 'col4_jbu':
        dirs = [ce.shade_direction(s), ce.sky_dir()] + ce.kmeans_dirs(s, 2)
        low = ce.light_rule(s, dirs=dirs)
    else:
        low = flatfield_low(s, aniso=(kind == 'ff_aniso'))
    return ce.up_jbu(low, s, src, fac)

def norm01(lg):
    lo, hi = np.percentile(lg, [1, 99]); return np.clip((lg - lo) / max(hi - lo, 1e-6), 0, 1)

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--cache', required=True, type=Path)
    ap.add_argument('--game', nargs='*', default=[], type=Path)
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    a = argparse.Namespace(cache=args.cache, width=1280, height=720, sun_samples=16, sky_samples=96, noise_codes=0.8, seed=7)
    kinds = ['col4_jbu', 'ff_iso', 'ff_aniso']
    res = {}
    for name in osc.ALL:
        f = osc.frame(name, a); src, surf = f['src'], f['surf']; y = src @ so.LUMA
        reg = {r: mk for r, mk in bo.regions_of(f).items() if mk.sum() > 500}
        med = float(np.median(np.log2(np.maximum(y, 0.001))[surf]))
        row = {}
        ests = {'production': bo.production_base_log(np.log2(np.maximum(y, 0.001)))}
        for k in kinds:
            lg = estimate(src, k); ests[k] = lg + med - float(np.median(lg[surf]))
        for curve, fn in (('strong', gp.strong), ('oracle', bo.gain_stops)):
            tr = np.where(surf, fn(f['x_light']), fn(y))
            for k, lg in ests.items():
                row.setdefault(k, {})[curve] = float(np.mean([np.abs(fn(np.exp2(lg)) - tr)[mk].mean() for mk in reg.values()]))
        res[name] = row
        tl = np.log2(np.maximum(np.where(surf, f['x_light'], y), 1e-4))
        Image.fromarray((np.concatenate([norm01(tl)] + [norm01(ests[k]) for k in ['production'] + kinds], 1) * 255).astype(np.uint8)).save(args.output / f'{name}_maps.png')
        print(name, '  '.join(f'{k} {v["strong"]:.3f}/{v["oracle"]:.3f}' for k, v in row.items()), flush=True)
    keys = list(next(iter(res.values())))
    for c in ('strong', 'oracle'):
        print(f'\n{c}: MEAN ' + '  '.join(f'{k} {np.mean([r[k][c] for r in res.values()]):.3f}' for k in keys)
              + '   WINS vs prod ' + ' '.join(f'{k}:{sum(r[k][c] < r["production"][c] for r in res.values())}' for k in keys[1:]))
    for g in args.game:
        im = np.array(Image.open(g).convert('RGB'), np.float64) / 255
        src = np.where(im <= 0.04045, im / 12.92, ((im + 0.055) / 1.055) ** 2.4)
        h, w = src.shape[0] // 8 * 8, src.shape[1] // 8 * 8; src = src[:h, :w]
        tiles = [im[:h, :w]] + [norm01(estimate(src, k))[..., None].repeat(3, -1) for k in kinds]
        top = np.concatenate(tiles[:2], 1); bot = np.concatenate(tiles[2:], 1)
        Image.fromarray((np.concatenate([top, bot], 0) * 255).astype(np.uint8)).resize((w, h)).save(args.output / f'game_{g.stem}.jpg', quality=88)
        print('game', g.stem, flush=True)
    (args.output / 'report.json').write_text(json.dumps(res, indent=1))

if __name__ == '__main__':
    main()
