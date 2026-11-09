#!/usr/bin/env python3
"""Screen colour-aware range weights in the production tonal base, against the brightness oracle.

Production's TonalIlluminationLog (grade.fx:583; CPU replica brightness_oracle.production_base_log)
stops averaging across any log-luminance step of .5-1 stop, so a large dark material becomes its own
"dark light". Here each centre/sample pair is also classified by colour (research/
2026-11-09_colour_edge_light_material.md): a step that looks like a material edge keeps full weight
(average across it); a step that looks like light keeps production's cutoff. No reintegration and
no new passes; the shader would need the guide's chromaticity next to its log luminance.
Rules (pair difference, log chromaticity after a 3x3 box):
  chroma: |dlog R/G| + |dlog B/G| >= t is material (Funt-Drew style);
  inv:    |component orthogonal to the Planckian direction| >= t is material (Finlayson);
  sky:    inv, or darker side warmer, or daylight-axis shift > k per stop (+.03) is material.
Classification is soft (smoothstep over [t, 2t]). CPU only.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

import brightness_oracle as bo
import invariant_screen as inv
import shadow_oracle as so

def light_prob(rule, dl, dperp, dalong, draw, t, k=0.40, tol=0.03):
    """Probability that a pair difference is a light (not material) change."""
    if rule == 'chroma':
        return 1 - so.smooth(t, 2 * t, draw)
    p = 1 - so.smooth(t, 2 * t, np.abs(dperp))
    if rule == 'sky':
        warm_dark = -(dalong * np.sign(dl)) - tol            # >0 when the darker side is warmer
        p = p * (1 - so.smooth(0.0, tol, warm_dark))
        excess = np.abs(dalong) - (k * np.abs(dl) + tol)
        p = p * (1 - so.smooth(0.0, tol, excess))
    return p

def colour_base_log(native_log, lc, e, rule, t, stride=8, quadrants=True, dark=None):
    c = native_log
    ee = e if e[0] > 0 else -e
    perp = lc @ np.array([-e[1], e[0]]); along = lc @ ee
    full_sum = np.zeros_like(c); full_w = np.zeros_like(c)
    side_sum = np.zeros((4,) + c.shape); side_w = np.zeros((4,) + c.shape)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            smp = bo.shifted(c, dy * stride, dx * stride)
            d = smp - c
            draw = (np.abs(bo.shifted(lc[..., 0], dy * stride, dx * stride) - lc[..., 0])
                    + np.abs(bo.shifted(lc[..., 1], dy * stride, dx * stride) - lc[..., 1]))
            pl = light_prob(rule, d, bo.shifted(perp, dy * stride, dx * stride) - perp,
                            bo.shifted(along, dy * stride, dx * stride) - along, draw, t)
            if dark is not None:                           # chroma unreliable near black: production rule
                pl = np.where(dark | bo.shifted(dark, dy * stride, dx * stride), 1.0, pl)
            wt = 1 - so.smooth(0.5, 1.0, np.abs(d)) * pl
            full_sum += smp * wt; full_w += wt
            quad = (dx <= 0 and dy <= 0, dx >= 0 and dy <= 0, dx <= 0 and dy >= 0, dx >= 0 and dy >= 0)
            for q in range(4):
                if quad[q]:
                    side_sum[q] += smp * wt; side_w[q] += wt
    full_d = full_sum / np.maximum(full_w, 1) - c
    if not quadrants:
        return c + full_d
    side_d = side_sum / np.maximum(side_w, 1) - c
    scale = np.maximum(np.maximum(np.abs(full_d), np.abs(side_d).max(0)), 1e-5)
    cd = full_d / scale; sd = side_d / scale
    cd2 = cd * cd; sd2 = sd * sd
    cw = sd2[0] * sd2[1] * sd2[2] * sd2[3]
    sw = np.stack([cd2 * sd2[1] * sd2[2] * sd2[3], cd2 * sd2[0] * sd2[2] * sd2[3],
                   cd2 * sd2[0] * sd2[1] * sd2[3], cd2 * sd2[0] * sd2[1] * sd2[2]])
    return c + scale * (cw * cd + (sw * sd).sum(0)) / np.maximum(cw + sw.sum(0), 1e-20)

VARIANTS = {}
for rule, ts in (('chroma', (0.15,)), ('inv', (0.05, 0.10)), ('sky', (0.05, 0.10))):
    for t in ts:
        for stride in (8, 16):
            for quads in (True, False):
                VARIANTS[f'{rule}_{t:.2f}_s{stride}{"" if quads else "_full"}'] = dict(rule=rule, t=t, stride=stride, quadrants=quads)

def screen(name, cfg, args):
    f = bo.frame(name, cfg, args)
    src, surf = f['src'], f['surf']
    y = src @ so.LUMA
    stops_oracle = np.where(surf, bo.gain_stops(f['x_light']), bo.gain_stops(y))
    native_log = np.log2(np.maximum(y, 0.001))
    lin = np.stack([bo.box_blur(np.maximum(src[..., c], 0.002), 1) for c in range(3)], -1)
    lc = inv.logchroma(lin); e = inv.planck_direction(); dark = y < 0.004
    apply = lambda base: bo.gain_stops(y * np.exp2(base - native_log))
    stops = {'production': apply(bo.production_base_log(native_log)),
             'production_s16': apply(bo.production_base_log(native_log, stride=16))}
    for k, v in VARIANTS.items():
        stops[k] = apply(colour_base_log(native_log, lc, e, v['rule'], v['t'], v['stride'], v['quadrants'], dark))
    regions = bo.regions_of(f)
    rows = {}
    for k, st in stops.items():
        per_region = {r: float(np.abs(st - stops_oracle)[m].mean()) for r, m in regions.items() if m.sum()}
        rows[k] = {'error_vs_oracle': float(np.abs(st - stops_oracle)[surf].mean()),
                   'balanced_error': float(np.mean(list(per_region.values()))), 'region_error': per_region,
                   'gain_roughness': float(np.abs(st - bo.box_blur(st, 4))[surf].mean())}
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
    args.output.mkdir(parents=True, exist_ok=True)
    report = {'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'variants': VARIANTS, 'scenes': {}}
    for name in args.scenes:
        report['scenes'][name] = screen(name, bo.SCENES[name], args)
    (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    sc = list(report['scenes'])
    print(f'{"variant":26s}' + ''.join(f'{s[:8]:>10s} bal' for s in sc) + '   mean bal')
    for k in report['scenes'][sc[0]]:
        b = [report['scenes'][s][k]['balanced_error'] for s in sc]
        a = [report['scenes'][s][k]['error_vs_oracle'] for s in sc]
        print(f'{k:26s}' + ''.join(f'{x:7.3f}/{y:.3f}' for x, y in zip(a, b)) + f'   {np.mean(b):.3f}')

if __name__ == '__main__':
    main()
