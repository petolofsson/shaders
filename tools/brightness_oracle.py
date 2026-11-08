#!/usr/bin/env python3
"""SDR-to-SDR brightness oracle: global tonal allocation vs illumination-only reshaping.

Every variant starts from the same game-like 8-bit sRGB frame. The global variant
applies a luminance-dependent gain to each pixel's own display luminance. The
oracle applies the identical gain function to the display luminance an 18% gray
surface would have under that pixel's exact illumination, so lighting is reshaped
while each material's relation to its neighbors is kept. Only the oracle uses
renderer ground truth. No GPU, display or network is used.
"""
import argparse
import hashlib
import html
import json
from pathlib import Path

import numpy as np

import shadow_oracle as so

INTERIOR_BOXES = {
    # Room x 0..6, z 0..8, height 3; west wall (x=0) has a window z 3..5, y 1..2.4.
    'w_low':   ((-0.2, 0.0, -0.2), (0.0, 1.0, 8.2), (0.50, 0.47, 0.42)),
    'w_high':  ((-0.2, 2.4, -0.2), (0.0, 3.0, 8.2), (0.50, 0.47, 0.42)),
    'w_left':  ((-0.2, 1.0, -0.2), (0.0, 2.4, 3.0), (0.50, 0.47, 0.42)),
    'w_right': ((-0.2, 1.0, 5.0), (0.0, 2.4, 8.2), (0.50, 0.47, 0.42)),
    'e_wall':  ((6.0, 0.0, -0.2), (6.2, 3.0, 8.2), (0.50, 0.47, 0.42)),
    'n_wall':  ((-0.2, 0.0, 8.0), (6.2, 3.0, 8.2), (0.50, 0.47, 0.42)),
    's_wall':  ((-0.2, 0.0, -0.4), (6.2, 3.0, -0.2), (0.50, 0.47, 0.42)),
    'ceiling': ((-0.2, 3.0, -0.4), (6.2, 3.2, 8.2), (0.60, 0.58, 0.55)),
    'shelf':   ((5.3, 0.0, 4.0), (6.0, 2.0, 7.0), (0.32, 0.18, 0.09)),      # warm timber
    'shelf_b': ((5.25, 0.9, 4.0), (6.0, 1.0, 7.0), (0.32, 0.18, 0.09)),
    'cabinet': ((3.0, 0.0, 7.2), (4.6, 1.2, 8.0), (0.24, 0.25, 0.27)),      # gray metal
    'leather': ((1.0, 0.0, 6.6), (2.2, 0.6, 7.8), (0.05, 0.03, 0.02)),      # dark material
    'pack':    ((3.2, 1.2, 7.4), (3.8, 1.6, 7.9), (0.06, 0.10, 0.25)),      # blue pack
    'crate':   ((2.2, 0.0, 4.6), (3.0, 0.7, 5.4), (0.55, 0.45, 0.30)),      # beige, near sun patch
    'table':   ((3.6, 0.7, 2.0), (4.8, 0.78, 3.4), (0.30, 0.17, 0.09)),
    'tleg1':   ((3.6, 0.0, 2.0), (3.7, 0.7, 2.1), (0.30, 0.17, 0.09)),
    'tleg2':   ((4.7, 0.0, 3.3), (4.8, 0.7, 3.4), (0.30, 0.17, 0.09)),
    'dark_box': ((4.2, 0.0, 2.3), (4.6, 0.4, 2.8), (0.04, 0.04, 0.045)),    # under the table: dark + occluded
}

def ground_planks(x, z):
    plank = np.floor(x * 5)
    base = np.array([0.30, 0.20, 0.12])
    var = 0.8 + 0.4 * so.hash2(plank, np.floor(z * 0.7 + plank * 0.37))
    seam = (x * 5) % 1 < 0.05
    alb = base[None] * (var * np.where(seam, 0.55, 1.0))[:, None]
    rug = (x > 1.0) & (x < 2.3) & (z > 4.5) & (z < 6.0)                   # dark rug in the sun patch
    alb[rug] = np.array([0.045, 0.03, 0.035]) * (0.85 + 0.3 * so.hash2(np.floor(x[rug] * 30), np.floor(z[rug] * 30)))[:, None]
    return alb

WINDOW = np.array([0.0, 1.7, 4.0]); SUN_PATCH = np.array([1.6, 0.0, 5.2])

def interior_fill(hp):
    """Radiance of blocking surfaces: a one-bounce stand-in that falls off with
    distance from the window and the sun patch, so the room has a light gradient."""
    dw = np.linalg.norm(hp - WINDOW, axis=1); dp = np.linalg.norm(hp - SUN_PATCH, axis=1)
    k = 0.06 + 0.55 * np.exp(-dw / 1.6) + 0.45 * np.exp(-dp / 1.2)
    return k[:, None] * np.array([0.11, 0.098, 0.082])

SCENES = {
    'daylight': {'scene': so.DAYLIGHT, 'exposure': 1.0},
    'interior': {'scene': {'boxes': INTERIOR_BOXES, 'ground': ground_planks, 'cam': (5.4, 1.6, 0.4),
                           'target': (1.5, 0.8, 6.0), 'fov': 70, 'fill_fn': interior_fill},
                 'exposure': 5.0},
}
LIFT_STOPS, DEEPEN_STOPS = 0.6, 0.4

def gain_stops(x):
    """One tonal-allocation curve in stops, as a function of display-linear luminance x.
    Lifts the partial-shadow band (~.008-.12) and deepens the deepest band (< ~.006),
    leaving black (x→0 keeps x→0) and lit levels (> ~.3) unchanged."""
    lx = np.log2(np.maximum(x, 1e-6))
    lift = so.smooth(np.log2(0.004), np.log2(0.02), lx) * (1 - so.smooth(np.log2(0.05), np.log2(0.3), lx))
    deep = 1 - so.smooth(np.log2(0.0015), np.log2(0.006), lx)
    return LIFT_STOPS * lift - DEEPEN_STOPS * deep

def apply_gain(lin, stops):
    g = np.exp2(stops)[..., None]
    out = lin * g
    peak = np.max(out, axis=-1, keepdims=True)
    return np.where(peak > 1, out / np.maximum(peak, 1e-9), out)   # hue-preserving ceiling

def shifted(a, dy, dx):
    """a[y+dy, x+dx] with edge clamping (CLAMP addressing, POINT sampling)."""
    h, w = a.shape
    yi = np.clip(np.arange(h) + dy, 0, h - 1); xi = np.clip(np.arange(w) + dx, 0, w - 1)
    return a[yi][:, xi]

def production_base_log(native_log, stride=8):
    """CPU replica of grade.fx TonalIlluminationLog: 5x5 taps at an 8-px stride,
    range weight 1 - smoothstep(.5, 1, |dlog|), center/quadrant window selection."""
    c = native_log
    full_sum = np.zeros_like(c); full_w = np.zeros_like(c)
    side_sum = np.zeros((4,) + c.shape); side_w = np.zeros((4,) + c.shape)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            smp = shifted(c, dy * stride, dx * stride)
            wt = 1 - so.smooth(0.5, 1.0, np.abs(smp - c))
            full_sum += smp * wt; full_w += wt
            quad = (dx <= 0 and dy <= 0, dx >= 0 and dy <= 0, dx <= 0 and dy >= 0, dx >= 0 and dy >= 0)
            for q in range(4):
                if quad[q]:
                    side_sum[q] += smp * wt; side_w[q] += wt
    full_d = full_sum / np.maximum(full_w, 1) - c
    side_d = side_sum / np.maximum(side_w, 1) - c
    scale = np.maximum(np.maximum(np.abs(full_d), np.abs(side_d).max(0)), 1e-5)
    cd = full_d / scale; sd = side_d / scale
    cd2 = cd * cd; sd2 = sd * sd
    cw = sd2[0] * sd2[1] * sd2[2] * sd2[3]
    sw = np.stack([cd2 * sd2[1] * sd2[2] * sd2[3], cd2 * sd2[0] * sd2[2] * sd2[3],
                   cd2 * sd2[0] * sd2[1] * sd2[3], cd2 * sd2[0] * sd2[1] * sd2[2]])
    wsum = cw + sw.sum(0)
    return c + scale * (cw * cd + (sw * sd).sum(0)) / np.maximum(wsum, 1e-20)

def box_blur(a, r):
    k = 2 * r + 1
    p = np.pad(a, r, mode='edge')
    c = np.cumsum(np.cumsum(p, 0), 1)
    c = np.pad(c, ((1, 0), (1, 0)))
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)

def frame(name, cfg, args):
    """Render (or load from --cache) one scene; return the 8-bit source and truths."""
    key = f'{name}_{args.width}x{args.height}_s{args.sun_samples}_k{args.sky_samples}_seed{args.seed}_n{args.noise_codes}'
    cache = getattr(args, 'cache', None)
    path = Path(cache) / f'{key}.npz' if cache else None
    if path is not None and path.is_file():
        d = np.load(path)
        return {k: d[k] for k in d.files}
    s = so.render(args.width, args.height, args.sun_samples, args.sky_samples, args.seed, cfg['scene'])
    exp = cfg['exposure']
    rng = np.random.default_rng(args.seed + 1)
    disp = so.to_srgb(so.aces(s['hdr'] * exp))
    disp = disp + rng.normal(0, args.noise_codes / 255, disp.shape)           # game-like noise before 8-bit
    src8 = np.round(np.clip(disp, 0, 1) * 255) / 255
    src = so.from_srgb(src8)
    surf = s['surface']
    # Display luminance the scene's median material would show under this pixel's exact
    # illumination, so every attribution shares one brightness scale.
    ya = s['albedo'] @ so.LUMA
    ref = float(np.median(ya[surf]))
    x_light = np.where(surf, so.aces(ref * s['irr_luma'] * exp), src @ so.LUMA)
    f = {'src': src, 'surf': surf, 'ya': ya, 'x_light': x_light, 'albedo': s['albedo'], 'ref': np.array(ref)}
    if path is not None:
        path.parent.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(path, **f)
    return f

def regions_of(f):
    surf, xl, ya = f['surf'], f['x_light'], f['ya']
    return {
        'lit_dark_material':     surf & (xl > 0.12) & (ya < 0.07),
        'partial_bright':        surf & (xl > 0.008) & (xl < 0.08) & (ya > 0.15),
        'partial_dark_material': surf & (xl > 0.008) & (xl < 0.08) & (ya < 0.07),
        'deep_occlusion':        surf & (xl < 0.006),
        'lit_bright':            surf & (xl > 0.12) & (ya > 0.15),
    }

def build(name, cfg, args, out):
    f = frame(name, cfg, args)
    src, surf, ya, x_light, ref = f['src'], f['surf'], f['ya'], f['x_light'], float(f['ref'])
    s = {'albedo': f['albedo']}
    y = src @ so.LUMA
    stops_global = gain_stops(y)
    stops_oracle = np.where(surf, gain_stops(x_light), stops_global)
    # Production attribution: the shared tonal base luma * exp2(illumination_log - native_log).
    native_log = np.log2(np.maximum(y, 0.001))
    base_luma = y * np.exp2(production_base_log(native_log) - native_log)
    stops_prod = gain_stops(base_luma)
    stops = {'global': stops_global, 'production': stops_prod, 'oracle': stops_oracle}
    variants = {'source': src, **{k: apply_gain(src, st) for k, st in stops.items()}}
    for k, v in variants.items():
        so.write_png(out / f'{name}_{k}.png', so.to_srgb(v))
    vis = lambda st: np.clip(0.5 + st / (2 * max(LIFT_STOPS, DEEPEN_STOPS)), 0, 1)
    for k, st in stops.items():
        m = np.stack([vis(st)] * 3, -1); m[..., 2] = 1 - m[..., 0]                 # yellow lift, blue deepen
        so.write_png(out / f'{name}_gain_{k}.png', m)
    so.write_png(out / f'{name}_light_truth.png', np.repeat(so.to_srgb(x_light)[..., None], 3, -1))
    so.write_png(out / f'{name}_albedo.png', so.to_srgb(s['albedo']))
    regions = regions_of(f)
    rows = {'reference_albedo_luma': ref,
            # Texture-scale gain variation: mean |gain - 9x9 box mean| on surfaces, stops.
            'gain_roughness': {k: float(np.abs(st - box_blur(st, 4))[surf].mean()) for k, st in stops.items()},
            # Agreement with the oracle: mean |gain - oracle gain| on surfaces, stops.
            'error_vs_oracle': {k: float(np.abs(st - stops_oracle)[surf].mean()) for k, st in stops.items()}}
    for r, m in regions.items():
        rows[r] = {'pixels': int(m.sum())}
        if m.sum():
            for k, st in stops.items():
                rows[r][f'{k}_mean_stops'] = float(st[m].mean())
            rows[r]['source_mean_y'] = float(y[m].mean())
    return rows

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path, help='new or empty directory')
    ap.add_argument('--width', type=int, default=1280)
    ap.add_argument('--height', type=int, default=720)
    ap.add_argument('--sun-samples', type=int, default=16)
    ap.add_argument('--sky-samples', type=int, default=96)
    ap.add_argument('--noise-codes', type=float, default=0.8, help='Gaussian noise std in 8-bit codes before quantization')
    ap.add_argument('--seed', type=int, default=7)
    ap.add_argument('--scenes', nargs='+', default=list(SCENES), choices=list(SCENES))
    ap.add_argument('--cache', type=Path, help='optional directory for reusable rendered frames')
    args = ap.parse_args()
    out = args.output
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        ap.error('output directory must be new or empty')
    out.mkdir(parents=True, exist_ok=True)
    report = {'tool_sha256': digest(__file__), 'renderer_sha256': digest(so.__file__),
              'args': {k: str(v) for k, v in vars(args).items()},
              'curve': {'lift_stops': LIFT_STOPS, 'deepen_stops': DEEPEN_STOPS,
                        'lift_band': 'smoothstep(log2 .004, log2 .02) * (1 - smoothstep(log2 .05, log2 .3))',
                        'deep_band': '1 - smoothstep(log2 .0015, log2 .006)'},
              'oracle_argument': 'ACES(scene median albedo luma * exact illumination luma * exposure)',
              'scope': 'CPU reference; no production grade stages applied', 'scenes': {}}
    for name in args.scenes:
        report['scenes'][name] = build(name, SCENES[name], args, out)
        print(name, json.dumps(report['scenes'][name], indent=1))
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    write_review(out, args.scenes)

def write_review(out, scenes):
    views = [('source', 'Source 8-bit'), ('global', 'Global curve (own luminance)'),
             ('production', 'Production base (TonalIlluminationLog)'),
             ('oracle', 'Oracle (exact light only)'), ('gain_global', 'Gain map: global'),
             ('gain_production', 'Gain map: production'), ('gain_oracle', 'Gain map: oracle'), ('light_truth', 'Truth: light on median material'), ('albedo', 'Truth: material')]
    blocks = []
    for sc in scenes:
        btn = ''.join(f'<button data-s="{sc}" data-k="{k}">{html.escape(t)}</button>' for k, t in views)
        blocks.append(f'<h2>{sc}</h2><div>{btn}</div><img id="img_{sc}" src="{sc}_source.png" data-cur="source" data-last="source">')
    page = f'''<!doctype html><meta charset="utf-8"><title>Brightness oracle</title>
<style>body{{background:#16181b;color:#e8e8e8;font:15px system-ui;margin:1.5rem}}button{{margin:2px;padding:.4rem .6rem;background:#2a2d31;color:#eee;border:1px solid #555;cursor:pointer}}
button.on{{background:#4a6;color:#000}}img{{width:100%;display:block;margin:.5rem 0 1.5rem}}</style>
<h1>Brightness oracle (SDR → SDR)</h1><p>All variants start from the same noisy 8-bit frame and use one tonal curve: lift partial shadows, deepen the deepest band, keep black and lit levels. <b>Global</b> evaluates it on each pixel's own luminance; <b>production</b> on a CPU replica of the grade's shared tonal base (range-limited 40-px local average); <b>oracle</b> evaluates it on the exact light falling on the pixel, so dark materials in light are not lifted and lit shadows of bright materials are. Gain maps: yellow = lift, blue = deepen, gray = none. Click an image to toggle with source.</p>
{"".join(blocks)}
<script>document.querySelectorAll('button').forEach(b=>b.onclick=()=>{{const i=document.getElementById('img_'+b.dataset.s);i.dataset.last=i.dataset.cur;i.dataset.cur=b.dataset.k;i.src=b.dataset.s+'_'+b.dataset.k+'.png';
document.querySelectorAll('button[data-s="'+b.dataset.s+'"]').forEach(x=>x.classList.toggle('on',x===b));}});
document.querySelectorAll('img').forEach(i=>i.onclick=()=>{{const s=i.id.slice(4);const k=i.dataset.cur==='source'?i.dataset.last:'source';i.dataset.last=i.dataset.cur;i.dataset.cur=k;i.src=s+'_'+k+'.png';}});</script>'''
    (out / 'review.html').write_text(page)

if __name__ == '__main__':
    main()
