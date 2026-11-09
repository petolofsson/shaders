#!/usr/bin/env python3
"""Contained material correction screen (CPU only). Follows tools/material_veto_screen.py.

light = log2 luminance (production-like default: all darkness is light) + c, where c removes only
confident paint steps, kept local:
  paint edge   both sides chromatic (|log chroma| > s0) and hue angle between them > theta.
               Neutral<->colour edges (black gun on yellow, white light into red-lit areas) stay light,
               so coloured lights and dark neutrals are not taken for paint.
  local        c solves the screened Poisson equation (Lap - 1/l^2) c = div(-paint steps): each
               correction fades over ~l lane pixels instead of spreading across open regions.
  cap          |c| <= cap stops.
Kinds 'loc_th{theta}_l{l}' (cap 1.0, s0 .12). Same scoring/rendering as material_veto_screen, plus
diff maps (orange: treated as more lit than luminance says; blue: less).
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
import material_veto_screen as mv
import oracle_scenes as osc
import shadow_oracle as so

EPS = 0.002

def screened(gx, gy, length):
    h, w = gy.shape[0] + 1, gx.shape[1] + 1
    div = np.zeros((h, w))
    div[:, :-1] += gx; div[:, 1:] -= gx; div[:-1, :] += gy; div[1:, :] -= gy
    big = np.concatenate([div, div[::-1]], 0); big = np.concatenate([big, big[:, ::-1]], 1)
    ky = 2 * np.cos(2 * np.pi * np.arange(2 * h) / (2 * h)) - 2
    kx = 2 * np.cos(2 * np.pi * np.arange(2 * w) / (2 * w)) - 2
    lam = ky[:, None] + kx[None, :] - 1.0 / length ** 2
    return np.real(np.fft.ifft2(np.fft.fft2(big) / lam))[:h, :w]

def paint(a, b, theta, s0):
    sa = np.linalg.norm(a, axis=-1); sb = np.linalg.norm(b, axis=-1)
    cosang = (a * b).sum(-1) / np.maximum(sa * sb, 1e-9)
    return (sa > s0) & (sb > s0) & (cosang < np.cos(np.radians(theta)))

def local_low(s, theta, length, cap=1.0, s0=0.12):
    ly = np.log2(np.maximum(s @ so.LUMA, EPS)); lc = inv.logchroma(np.maximum(s, EPS))
    gx, gy = np.diff(ly, axis=1), np.diff(ly, axis=0)
    px = paint(lc[:, :-1], lc[:, 1:], theta, s0); py = paint(lc[:-1], lc[1:], theta, s0)
    c = screened(-gx * px, -gy * py, length)
    return ly + np.clip(c, -cap, cap), (px.mean() + py.mean()) / 2

def parse(kind):
    th, l = kind.split('_')[1:]; return float(th[2:]), float(l[1:])

def estimate(src, kind, fac=8):
    s = ce.down(src, fac)
    if kind == 'veto_t.35':
        low, frac = mv.veto_low(s, 0.35)
    elif kind == 'col4_jbu':
        low, frac = ce.light_rule(s, dirs=mv.directions(s)), None
    else:
        low, frac = local_low(s, *parse(kind))
    return ce.up_jbu(low, s, src, fac), frac, low, s

KINDS = ['col4_jbu', 'veto_t.35', 'loc_th35_l4', 'loc_th35_l8', 'loc_th60_l4', 'loc_th60_l8']

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--cache', required=True, type=Path)
    ap.add_argument('--game', nargs='*', default=[], type=Path)
    ap.add_argument('--show', default='loc_th35_l4')
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
            lg = estimate(src, k)[0]; ests[k] = lg + med - float(np.median(lg[surf]))
        row = {}
        for curve, fn in (('strong', gp.strong), ('oracle', bo.gain_stops)):
            tr = np.where(surf, fn(f['x_light']), fn(y))
            for k, lg in ests.items():
                row.setdefault(k, {})[curve] = float(np.mean([np.abs(fn(np.exp2(lg)) - tr)[mk].mean() for mk in reg.values()]))
        res[name] = row
        print(name, '  '.join(f'{k} {v["strong"]:.3f}' for k, v in row.items()), flush=True)
    keys = list(next(iter(res.values())))
    for c in ('strong', 'oracle'):
        print(f'\n{c}: MEAN ' + '  '.join(f'{k} {np.mean([r[k][c] for r in res.values()]):.3f}' for k in keys)
              + '   WINS vs prod ' + ' '.join(f'{k}:{sum(r[k][c] < r["production"][c] for r in res.values())}' for k in keys[1:]))
    for g in args.game:
        im = np.array(Image.open(g).convert('RGB'), np.float64) / 255
        src = np.where(im <= 0.04045, im / 12.92, ((im + 0.055) / 1.055) ** 2.4)
        h, w = src.shape[0] // 8 * 8, src.shape[1] // 8 * 8; src, im = src[:h, :w], im[:h, :w]
        prod = bo.production_base_log(np.log2(np.maximum(src @ so.LUMA, 0.001)))
        full, frac, low, s = estimate(src, args.show)
        ly = np.log2(np.maximum(s @ so.LUMA, EPS)); d = low - ly
        dd = np.array(Image.fromarray(d.astype(np.float32)).resize((w, h), Image.BILINEAR))
        gry = 0.4 * im.mean(-1, keepdims=True) * np.ones(3)
        pos = np.clip(dd / 1.0, 0, 1)[..., None]; neg = np.clip(-dd / 1.0, 0, 1)[..., None]
        diff = gry * (1 - pos - neg) + pos * np.array([1, .55, .1]) + neg * np.array([.2, .5, 1])
        z = lambda l: 0.45 * mv.zones(l) + 0.55 * im * mv.zones(l)
        top = np.concatenate([im, mv.norm01(full)[..., None].repeat(3, -1), diff], 1)
        bot = np.concatenate([z(prod), z(full), mv.norm01(prod)[..., None].repeat(3, -1)], 1)
        Image.fromarray((np.concatenate([top, bot], 0) * 255).astype(np.uint8)).resize((w * 3 // 2, h)).save(args.output / f'game_{g.stem}.jpg', quality=88)
        print('game', g.stem, f'paint edges {frac:.3f}', 'diff p5/p95 %.2f/%.2f  |d|>.5 %.1f%%' % (*np.percentile(d, [5, 95]), 100 * (np.abs(d) > .5).mean()), flush=True)
    (args.output / 'report.json').write_text(json.dumps(res, indent=1))

if __name__ == '__main__':
    main()
