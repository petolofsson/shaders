#!/usr/bin/env python3
"""Ground-truth shadow scene and oracle test for the experimental shadow-color helper.

A deterministic CPU ray caster renders a small sun/sky scene and records exact
per-pixel material albedo and illumination. It then compares, on the same 8-bit
display image, the current luminance-gated helper with oracle variants that are
driven by the known illumination (and optionally the known material color).
Only the helper is modelled; the rest of the grade chain is not applied.
No GPU, display or network is used.
"""
import argparse
import hashlib
import html
import json
from pathlib import Path

import numpy as np
from PIL import Image

LUMA = np.array([0.2126, 0.7152, 0.0722])
SUN_TO = np.array([-0.6, 0.65, -0.45]); SUN_TO /= np.linalg.norm(SUN_TO)
SUN_RGB = np.array([1.0, 0.9, 0.75]) * np.pi      # irradiance at normal incidence
SKY_RGB = np.array([0.18, 0.24, 0.36])            # sky radiance
BOUNCE_RGB = 0.38 * 0.55 * np.array([1.0, 0.9, 0.75])  # radiance from below horizon
SUN_CONE = np.radians(1.0)
BLACKS, WHITES, OFFSET = 0.0, 0.995, 0.0025       # isolated darker-range profile values

# name: (min, max, albedo, group). group: bright/dark material class for metrics.
BOXES = {
    'wall':        ((-2.0, 0.0, -8.0), (-1.7, 5.0, 14.0), (0.45, 0.44, 0.42)),
    'red_shade':   ((-1.2, 0.0, 3.0), (-0.2, 0.8, 4.0), (0.55, 0.12, 0.06)),
    'blue_shade':  ((0.0, 0.0, 5.0), (0.9, 1.4, 5.3), (0.06, 0.12, 0.40)),
    'green_shade': ((-1.0, 0.0, 7.0), (0.0, 0.7, 8.0), (0.12, 0.30, 0.06)),
    'dkred_shade': ((0.2, 0.0, 2.2), (1.0, 0.6, 2.8), (0.08, 0.02, 0.012)),
    'red_sun':     ((3.0, 0.0, 3.0), (4.0, 0.8, 4.0), (0.55, 0.12, 0.06)),
    'dkred_sun':   ((4.5, 0.0, 3.0), (5.5, 0.8, 4.0), (0.08, 0.02, 0.012)),
    'dknavy_sun':  ((3.2, 0.0, 5.5), (4.2, 1.4, 5.8), (0.012, 0.02, 0.06)),
    'dkgreen_sun': ((4.6, 0.0, 7.0), (5.6, 0.7, 8.0), (0.02, 0.045, 0.012)),
    'roof':        ((6.6, 1.6, 2.6), (9.4, 1.8, 6.4), (0.40, 0.40, 0.40)),
    'back':        ((6.6, 0.0, 6.2), (9.4, 1.6, 6.4), (0.40, 0.40, 0.40)),
    'side':        ((9.2, 0.0, 2.6), (9.4, 1.6, 6.4), (0.40, 0.40, 0.40)),
    'side_l':      ((6.6, 0.0, 3.6), (6.8, 1.6, 6.4), (0.40, 0.40, 0.40)),
    'beige_deep':  ((7.4, 0.0, 4.4), (8.4, 0.8, 5.4), (0.60, 0.50, 0.35)),
}
PAVING = np.array([0.40, 0.38, 0.34])
ASPHALT = np.array([0.035, 0.035, 0.04])
ASPHALT_RECT = (2.6, 6.5, 0.2, 2.4)               # x0, x1, z0, z1 on the ground

def hash2(a, b):
    return np.modf(np.sin(a * 127.1 + b * 311.7) * 43758.5453)[0] % 1.0

def intersect(o, d, tmin=1e-4, boxes=None):
    """Nearest hit over the ground plane and boxes: t, normal, object id (-1 none, 0 ground)."""
    n = len(o)
    t = np.full(n, np.inf); nrm = np.zeros((n, 3)); oid = np.full(n, -1)
    with np.errstate(divide='ignore', invalid='ignore'):
        tg = -o[:, 1] / d[:, 1]
        hit = (d[:, 1] < 0) & (tg > tmin)
        t[hit] = tg[hit]; nrm[hit] = (0, 1, 0); oid[hit] = 0
        inv = 1.0 / d
        for k, (lo, hi, _) in enumerate((boxes or BOXES).values(), start=1):
            t0 = (np.array(lo) - o) * inv; t1 = (np.array(hi) - o) * inv
            tn = np.minimum(t0, t1); tf = np.maximum(t0, t1)
            near = np.nanmax(tn, axis=1); far = np.nanmin(tf, axis=1)
            ok = (near <= far) & (near > tmin) & (near < t)
            t[ok] = near[ok]; oid[ok] = k
            axis = np.argmax(tn[ok], axis=1)
            nn = np.zeros((ok.sum(), 3)); nn[np.arange(len(axis)), axis] = -np.sign(d[ok][np.arange(len(axis)), axis])
            nrm[ok] = nn
    return t, nrm, oid

def occluded(o, d, boxes=None):
    return np.isfinite(intersect(o, d, boxes=boxes)[0])

def basis(nrm):
    a = np.where(np.abs(nrm[:, :1]) > 0.9, [[0, 1, 0]], [[1, 0, 0]])
    u = np.cross(a, nrm); u /= np.linalg.norm(u, axis=1, keepdims=True)
    return u, np.cross(nrm, u)

def ground_paving(x, z):
    tile = 0.85 + 0.3 * hash2(np.floor(x * 2), np.floor(z * 2))
    grout = ((x * 2) % 1 < 0.06) | ((z * 2) % 1 < 0.06)
    gal = PAVING[None] * tile[:, None] * np.where(grout, 0.6, 1.0)[:, None]
    ax0, ax1, az0, az1 = ASPHALT_RECT
    asp = (x > ax0) & (x < ax1) & (z > az0) & (z < az1)
    gal[asp] = ASPHALT * (0.9 + 0.2 * hash2(np.floor(x[asp] * 20), np.floor(z[asp] * 20)))[:, None]
    return gal

def albedo_at(p, oid, boxes=None, ground=None):
    alb = np.zeros((len(p), 3))
    for k, (_, _, rgb) in enumerate((boxes or BOXES).values(), start=1):
        alb[oid == k] = rgb
    g = oid == 0
    alb[g] = (ground or ground_paving)(p[g, 0], p[g, 2])
    # Fine material texture on every surface.
    q = np.floor(p * 24)
    alb *= (0.92 + 0.16 * hash2(q[:, 0] + q[:, 1] * 3.1, q[:, 2]))[:, None]
    return alb

DAYLIGHT = {'boxes': None, 'ground': None, 'cam': (2.8, 1.5, -1.8), 'target': (3.2, 0.5, 6.0),
            'fov': 55, 'fill': (0.0, 0.0, 0.0)}

def render(width, height, sun_samples, sky_samples, seed, scene=None):
    """scene: boxes, ground albedo fn, camera, fov and 'fill' radiance for blocked
    hemisphere samples (an ambient interreflection stand-in; zero outdoors)."""
    sc = dict(DAYLIGHT, **(scene or {}))
    boxes, fill, fill_fn = sc['boxes'], np.array(sc['fill']), sc.get('fill_fn')
    rng = np.random.default_rng(seed)
    cam = np.array(sc['cam'], dtype=float); target = np.array(sc['target'], dtype=float)
    fwd = target - cam; fwd /= np.linalg.norm(fwd)
    right = np.cross([0, 1, 0], fwd); right /= np.linalg.norm(right); up = np.cross(fwd, right)
    th = np.tan(np.radians(sc['fov']) / 2)
    ys, xs = np.mgrid[0:height, 0:width]
    sx = ((xs + 0.5) / width * 2 - 1) * th * width / height
    sy = (1 - (ys + 0.5) / height * 2) * th
    d = fwd + sx[..., None] * right + sy[..., None] * up
    d = (d / np.linalg.norm(d, axis=-1, keepdims=True)).reshape(-1, 3)
    o = np.broadcast_to(cam, d.shape).copy()
    t, nrm, oid = intersect(o, d, boxes=boxes)
    hit = np.isfinite(t)
    p = o[hit] + d[hit] * t[hit, None]; n = nrm[hit]; ids = oid[hit]
    po = p + n * 1e-3
    alb = albedo_at(p, ids, boxes, sc['ground'])
    cos_sun = np.clip(n @ SUN_TO, 0, None)
    # Soft sun visibility: stratified cone samples, per-pixel rotation.
    su, sv = basis(np.broadcast_to(SUN_TO, n.shape).copy())
    rot = rng.random(len(p)) * 2 * np.pi
    vis = np.zeros(len(p))
    for i in range(sun_samples):
        r = SUN_CONE * np.sqrt((i + 0.5) / sun_samples); a = rot + i * 2.39996
        sd = SUN_TO + np.tan(r) * (np.cos(a)[:, None] * su + np.sin(a)[:, None] * sv)
        sd /= np.linalg.norm(sd, axis=1, keepdims=True)
        vis += np.where(cos_sun > 0, ~occluded(po, sd, boxes), 0)
    vis /= sun_samples
    # Cosine-weighted hemisphere: sky above horizon, bounce below, zero when blocked.
    hu, hv = basis(n)
    rot = rng.random(len(p)) * 2 * np.pi
    amb = np.zeros((len(p), 3)); amb_open = np.zeros((len(p), 3))
    for i in range(sky_samples):
        r = np.sqrt((i + 0.5) / sky_samples); a = rot + i * 2.39996
        hd = (np.sqrt(1 - r * r))[..., None] * n + (r * np.cos(a))[:, None] * hu + (r * np.sin(a))[:, None] * hv
        env = np.where(hd[:, 1:2] > 0, SKY_RGB, BOUNCE_RGB)
        amb_open += env
        th_hit = intersect(po, hd, boxes=boxes)[0]
        blocked = np.isfinite(th_hit)[:, None]
        if fill_fn is not None:
            hp = po + hd * np.where(np.isfinite(th_hit), th_hit, 0)[:, None]
            amb += np.where(blocked, fill_fn(hp), env)
        else:
            amb += np.where(blocked, fill, env)
    amb /= sky_samples; amb_open /= sky_samples
    irr = SUN_RGB * (cos_sun * vis)[:, None] / np.pi + amb
    # Reference: the same surface with every occluder removed (sun and sky unblocked).
    irr_open = SUN_RGB * cos_sun[:, None] / np.pi + amb_open
    # Full-light reference independent of surface orientation (form shading counts as shading).
    irr_full = SUN_RGB / np.pi + SKY_RGB
    hdr = np.zeros((len(d), 3)); hdr[~hit] = sky_color(d[~hit])
    hdr[hit] = alb * irr
    def img(v, fill=0.0, ch=1):
        out = np.full((len(d), ch), fill, dtype=np.float64); out[hit] = v.reshape(len(p), ch)
        return out.reshape(height, width, ch) if ch > 1 else out.reshape(height, width)
    return {'hdr': hdr.reshape(height, width, 3), 'albedo': img(alb, 0, 3),
            'cast': img(1 - (irr @ LUMA) / np.maximum(irr_open @ LUMA, 1e-9)),
            'shading': img(1 - (irr @ LUMA) / (irr_full @ LUMA)),
            'irr_luma': img(irr @ LUMA),
            'surface': hit.reshape(height, width)}

def sky_color(d):
    h = np.clip(d[:, 1], 0, 1)[:, None]
    return (1 - h) * np.array([0.55, 0.62, 0.72]) + h * np.array([0.20, 0.32, 0.60])

def aces(x):
    return np.clip(x * (2.51 * x + 0.03) / (x * (2.43 * x + 0.59) + 0.14), 0, 1)

def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055)

def from_srgb(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

def apply_delta(lin, delta):
    """Shader headroom budget: the largest step (<=1) keeping every channel <= 1."""
    with np.errstate(divide='ignore', invalid='ignore'):
        head = np.where(delta > 1e-12, (1 - lin) / np.maximum(delta, 1e-12), np.inf)
    budget = np.clip(np.min(head, axis=-1, keepdims=True), 0, 1)
    return lin + delta * budget

def variants(src_lin, albedo, shadow, strength):
    """Display-linear outputs of the helper with different gates; all share the BLACKS/WHITES remap."""
    y = src_lin @ LUMA
    lin = src_lin * (WHITES - BLACKS) + BLACKS
    lum_gate = smooth(0.00025, 0.0025, y) * (1 - smooth(0.01, 0.04, y))
    shadow_gate = smooth(0.55, 0.85, shadow)
    chroma_obs = src_lin / np.maximum(y, 1e-6)[..., None] - 1
    ya = np.maximum(albedo @ LUMA, 1e-6)
    chroma_mat = albedo / ya[..., None] - 1
    # Oracle amount is relative to luminance; .25 equals the current helper's
    # relative amount at y=.011 (1.10 * .0025 / .011), inside its active range.
    k = 0.25 * strength
    out = {
        'current': apply_delta(lin, 1.10 * strength * OFFSET * lum_gate[..., None] * chroma_obs),
        'oracle_observed': apply_delta(lin, k * shadow_gate[..., None] * y[..., None] * chroma_obs),
        'oracle_material': apply_delta(lin, k * shadow_gate[..., None] * y[..., None] * chroma_mat),
    }
    return out, {'current': lum_gate, 'oracle': shadow_gate}

def oklab(lin):
    m1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                   [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]])
    m2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                   [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]])
    return np.cbrt(np.clip(lin, 0, None) @ m1.T) @ m2.T

def write_png(path, srgb):
    Image.fromarray(np.round(np.clip(srgb, 0, 1) * 255).astype(np.uint8)).save(path)

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path, help='new or empty directory')
    ap.add_argument('--width', type=int, default=1280)
    ap.add_argument('--height', type=int, default=720)
    ap.add_argument('--sun-samples', type=int, default=16)
    ap.add_argument('--sky-samples', type=int, default=48)
    ap.add_argument('--seed', type=int, default=7)
    args = ap.parse_args()
    out = args.output
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        ap.error('output directory must be new or empty')
    out.mkdir(parents=True, exist_ok=True)
    s = render(args.width, args.height, args.sun_samples, args.sky_samples, args.seed)
    # Game-like display image: exposure 1, per-channel ACES fit, 8-bit sRGB backbuffer.
    src8 = np.round(to_srgb(aces(s['hdr'])) * 255) / 255
    src_lin = from_srgb(src8)
    albedo, shadow, surf = s['albedo'], s['shading'], s['surface']
    y_alb = albedo @ LUMA
    regions = {
        'bright_lit':    surf & (shadow < 0.55) & (y_alb > 0.15),
        'bright_shadow': surf & (shadow > 0.8) & (y_alb > 0.15),
        'dark_lit':      surf & (shadow < 0.55) & (y_alb < 0.05),
        'dark_shadow':   surf & (shadow > 0.8) & (y_alb < 0.05),
    }
    report = {'tool_sha256': digest(__file__), 'args': {k: str(v) for k, v in vars(args).items()},
              'helper': {'BLACKS': BLACKS, 'WHITES': WHITES, 'EXPERIMENTAL_COLOR_OFFSET': OFFSET,
                         'luma_gate': 'smoothstep(.00025,.0025,y)*(1-smoothstep(.01,.04,y)), 1.10x'},
              'oracle': {'shadow': '1 - illum_luma / full_sun_and_sky_luma',
                         'gate': 'smoothstep(.55,.85,shadow)', 'amount': '.25 * y * chroma_direction'},
              'scope': 'helper only; no corrective/tonal/film/print stages; CPU reference',
              'region_pixels': {k: int(v.sum()) for k, v in regions.items()}, 'strengths': {}}
    write_png(out / 'source.png', src8)
    write_png(out / 'albedo.png', to_srgb(albedo))
    write_png(out / 'shadow_truth.png', np.repeat(shadow[..., None], 3, -1))
    write_png(out / 'cast_shadow_truth.png', np.repeat(s['cast'][..., None], 3, -1))
    for name, m in regions.items():
        write_png(out / f'region_{name}.png', np.repeat(m[..., None].astype(float), 3, -1))
    np.save(out / 'shadow_truth.npy', shadow.astype(np.float32))
    np.save(out / 'albedo.npy', albedo.astype(np.float32))
    lab_src = oklab(src_lin * (WHITES - BLACKS) + BLACKS)
    for strength in (1.0, 2.0):
        res, gates = variants(src_lin, albedo, shadow, strength)
        tag = f'{int(strength * 100)}'
        rows = {}
        for name, lin in res.items():
            srgb = to_srgb(lin)
            write_png(out / f'{name}_{tag}.png', srgb)
            lab = oklab(from_srgb(np.round(srgb * 255) / 255))
            c0, c1 = np.hypot(lab_src[..., 1], lab_src[..., 2]), np.hypot(lab[..., 1], lab[..., 2])
            dE = np.linalg.norm(lab - lab_src, axis=-1)
            rows[name] = {r: {'mean_dC_x100': float(100 * (c1 - c0)[m].mean()),
                              'mean_dE_x100': float(100 * dE[m].mean()),
                              'p95_dE_x100': float(100 * np.percentile(dE[m], 95)),
                              'changed_8bit_frac': float((np.abs(np.round(srgb * 255) - np.round(src8 * 255)).max(-1) > 0)[m].mean())}
                          for r, m in regions.items()}
            diff = np.clip(np.abs(srgb - src8).max(-1) * 255 / 8, 0, 1)
            write_png(out / f'diff_{name}_{tag}.png', np.repeat(diff[..., None], 3, -1))
        for gname, g in gates.items():
            rows[f'gate_{gname}'] = {r: float(g[m].mean()) for r, m in regions.items()}
        report['strengths'][tag] = rows
    for gname, g in gates.items():
        write_png(out / f'gate_{gname}.png', np.repeat(g[..., None], 3, -1))
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    write_review(out, report)
    print(json.dumps(report['strengths'], indent=1))

def write_review(out, report):
    views = [('source', 'Source (8-bit display)'),
             ('current_100', 'Current helper 110%'), ('oracle_observed_100', 'Oracle: true shadow, observed color'),
             ('oracle_material_100', 'Oracle: true shadow + true material color'),
             ('current_200', 'Current helper ×2'), ('oracle_observed_200', 'Oracle observed ×2'),
             ('oracle_material_200', 'Oracle material ×2'),
             ('shadow_truth', 'Truth: shading (1 − illumination)'), ('albedo', 'Truth: material color'),
             ('gate_current', 'Gate: current luminance'), ('gate_oracle', 'Gate: oracle shadow'),
             ('diff_current_100', 'Diff current (×8 codes)'), ('diff_oracle_observed_100', 'Diff oracle observed'),
             ('diff_oracle_material_100', 'Diff oracle material')]
    buttons = ''.join(f'<button data-k="{k}" title="key {i + 1 if i < 9 else ""}">{html.escape(t)}</button>'
                      for i, (k, t) in enumerate(views))
    table = ['<table><tr><th>strength</th><th>variant</th>' + ''.join(f'<th>{r}<br>dE / dC ×100</th>' for r in report['region_pixels']) + '</tr>']
    for tag, rows in report['strengths'].items():
        for name, regs in rows.items():
            if name.startswith('gate_'):
                cells = ''.join(f'<td>gate {v:.2f}</td>' for v in regs.values())
            else:
                cells = ''.join(f'<td>{v["mean_dE_x100"]:.2f} / {v["mean_dC_x100"]:+.2f}</td>' for v in regs.values())
            table.append(f'<tr><td>{tag}%</td><td>{name}</td>{cells}</tr>')
    table.append('</table>')
    page = f'''<!doctype html><meta charset="utf-8"><title>Shadow oracle test</title>
<style>body{{background:#16181b;color:#e8e8e8;font:15px system-ui;margin:1.5rem}}button{{margin:2px;padding:.4rem .6rem;background:#2a2d31;color:#eee;border:1px solid #555;cursor:pointer}}
button.on{{background:#4a6;color:#000}}img{{width:100%;image-rendering:pixelated;display:block;margin-top:.6rem}}table{{border-collapse:collapse;margin-top:1rem}}td,th{{border:1px solid #444;padding:.25rem .5rem;font-size:13px}}</style>
<h1>Shadow oracle test</h1><p>Helper only, CPU reference; the rest of the grade is not applied. Left wall shadow covers bright red/blue/green and a dark red block; right side has the same materials in sun plus dark red/navy/green and asphalt; the shelter on the far right is deep occlusion over beige. Keys 1–9 switch views; click the image to toggle with source.</p>
<div>{buttons}</div><img id="v" src="source.png">{"".join(table)}
<script>const v=document.getElementById('v');let cur='source',last='source';const bs=[...document.querySelectorAll('button')];
function show(k){{last=cur;cur=k;v.src=k+'.png';bs.forEach(b=>b.classList.toggle('on',b.dataset.k==k));}}
bs.forEach(b=>b.onclick=()=>show(b.dataset.k));v.onclick=()=>show(cur==='source'?last:'source');
addEventListener('keydown',e=>{{const i=+e.key;if(i>=1&&i<=bs.length&&i<=9)show(bs[i-1].dataset.k);}});show('source');</script>'''
    (out / 'review.html').write_text(page)

if __name__ == '__main__':
    main()
