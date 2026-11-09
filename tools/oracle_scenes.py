#!/usr/bin/env python3
"""Richer oracle scene set for light/material screens (2026-11-09).

Extends brightness_oracle.SCENES with more material colours, varied sun/sky colours and
coloured bounce. Blocked hemisphere samples receive the blocker's albedo times a fraction of
the open irradiance (one-bounce stand-in), so shade takes the colour of nearby surfaces.
Renders with tools/shadow_oracle.render by temporarily setting its light constants.
frame(name, args) mirrors brightness_oracle.frame (ACES, sRGB, game-like noise, 8-bit) and
caches under the same --cache directory with a scene-set prefix.
"""
import contextlib
from pathlib import Path

import numpy as np

import brightness_oracle as bo
import shadow_oracle as so

def _box_albedo_fill(boxes, ground, k, light):
    """fill_fn: radiance of the blocking surface = its albedo * k * light (rgb)."""
    items = list(boxes.values())
    def fill(hp):
        alb = np.zeros((len(hp), 3)); found = np.zeros(len(hp), bool)
        for lo, hi, rgb in items:
            inside = np.all((hp >= np.array(lo) - 2e-3) & (hp <= np.array(hi) + 2e-3), axis=1) & ~found
            alb[inside] = rgb; found |= inside
        g = ~found & (hp[:, 1] < 2e-3)
        if g.any():
            alb[g] = ground(hp[g, 0], hp[g, 2])
        alb[~found & ~g] = 0.3
        return alb * k * np.asarray(light)[None]
    return fill

PALETTE_BOXES = {
    'wall':        ((-2.0, 0.0, -8.0), (-1.7, 5.0, 14.0), (0.55, 0.42, 0.25)),   # ochre wall
    'orange_shade':((-1.2, 0.0, 3.0), (-0.2, 0.8, 4.0), (0.62, 0.26, 0.05)),
    'blue_shade':  ((-0.2, 0.0, 3.0), (0.8, 0.8, 4.0), (0.05, 0.13, 0.48)),        # touching the orange
    'purple_shade':((-1.0, 0.0, 7.0), (0.0, 0.7, 8.0), (0.30, 0.08, 0.35)),
    'teal_shade':  ((0.2, 0.0, 2.0), (1.0, 0.6, 2.6), (0.05, 0.30, 0.28)),
    'orange_sun':  ((3.0, 0.0, 3.0), (4.0, 0.8, 4.0), (0.62, 0.26, 0.05)),
    'blue_sun':    ((4.0, 0.0, 3.0), (5.0, 0.8, 4.0), (0.05, 0.13, 0.48)),          # touching, both lit
    'yellow_sun':  ((3.2, 0.0, 5.5), (4.2, 1.4, 5.8), (0.70, 0.60, 0.10)),
    'black_sun':   ((4.6, 0.0, 7.0), (5.6, 0.7, 8.0), (0.03, 0.03, 0.035)),
    'red_sun':     ((5.4, 0.0, 4.6), (6.2, 0.5, 5.4), (0.50, 0.06, 0.05)),
    'roof':        ((6.6, 1.6, 2.6), (9.4, 1.8, 6.4), (0.45, 0.20, 0.12)),          # terracotta
    'back':        ((6.6, 0.0, 6.2), (9.4, 1.6, 6.4), (0.15, 0.35, 0.15)),          # green
    'side':        ((9.2, 0.0, 2.6), (9.4, 1.6, 6.4), (0.15, 0.35, 0.15)),
    'side_l':      ((6.6, 0.0, 3.6), (6.8, 1.6, 6.4), (0.15, 0.35, 0.15)),
    'beige_deep':  ((7.4, 0.0, 4.4), (8.4, 0.8, 5.4), (0.60, 0.50, 0.35)),
}

def ground_grass(x, z):
    g = np.array([0.10, 0.20, 0.05]) * (0.8 + 0.4 * so.hash2(np.floor(x * 6), np.floor(z * 6)))[:, None]
    path = (x > 2.2) & (x < 3.4)
    g[path] = np.array([0.42, 0.36, 0.28]) * (0.9 + 0.2 * so.hash2(np.floor(x[path] * 10), np.floor(z[path] * 10)))[:, None]
    return g

CANOPY_BOXES = dict(PALETTE_BOXES)
CANOPY_BOXES['canopy'] = ((0.5, 2.6, 1.0), (7.0, 2.8, 6.5), (0.08, 0.22, 0.05))     # leafy roof
CANOPY_BOXES['trunk'] = ((2.0, 0.0, 6.6), (2.4, 2.6, 7.0), (0.20, 0.13, 0.08))

LAMP_BOXES = dict(bo.INTERIOR_BOXES)
LAMP_BOXES.update({
    'sofa':   ((0.6, 0.0, 6.4), (2.0, 0.7, 7.8), (0.62, 0.26, 0.05)),    # orange sofa
    'locker': ((2.0, 0.0, 7.2), (2.8, 1.8, 8.0), (0.05, 0.13, 0.48)),    # blue locker touching it
    'rug_g':  ((3.0, 0.0, 4.0), (4.4, 0.02, 5.6), (0.10, 0.28, 0.12)),
})
LAMP = np.array([1.6, 2.4, 6.2])

def lamp_fill(hp):
    """Warm lamp near the sofa plus weak cool window light."""
    dl = np.linalg.norm(hp - LAMP, axis=1); dw = np.linalg.norm(hp - bo.WINDOW, axis=1)
    return ((0.05 + 0.9 * np.exp(-dl / 1.4))[:, None] * np.array([0.14, 0.09, 0.04])
            + (0.35 * np.exp(-dw / 1.6))[:, None] * np.array([0.07, 0.085, 0.11]))

def _day(name, sun_to, sun_rgb, sky_rgb, bounce_rgb, boxes, ground, exposure, bounce_k=0.35):
    light = sun_rgb / np.pi * max(sun_to[1], 0.2) + sky_rgb
    return {'lights': {'SUN_TO': sun_to / np.linalg.norm(sun_to), 'SUN_RGB': sun_rgb, 'SKY_RGB': sky_rgb, 'BOUNCE_RGB': bounce_rgb},
            'scene': {'boxes': boxes, 'ground': ground, 'cam': (2.8, 1.5, -1.8), 'target': (3.2, 0.5, 6.0), 'fov': 55,
                      'fill_fn': _box_albedo_fill(boxes, ground, bounce_k, light)},
            'exposure': exposure}

NEW_SCENES = {
    'colourful_noon': _day('colourful_noon', np.array([-0.6, 0.65, -0.45]), np.array([1.0, 0.9, 0.75]) * np.pi,
                           np.array([0.18, 0.24, 0.36]), 0.2 * np.array([0.3, 0.5, 0.2]), PALETTE_BOXES, ground_grass, 1.0),
    'golden_hour':    _day('golden_hour', np.array([-0.8, 0.25, -0.3]), np.array([1.0, 0.62, 0.32]) * np.pi * 0.9,
                           np.array([0.10, 0.15, 0.32]), 0.15 * np.array([0.6, 0.45, 0.3]), PALETTE_BOXES, ground_grass, 1.6),
    'overcast':       _day('overcast', np.array([-0.3, 0.9, -0.2]), np.array([1.0, 1.0, 1.0]) * np.pi * 0.12,
                           np.array([0.42, 0.44, 0.47]), 0.2 * np.array([0.3, 0.4, 0.25]), PALETTE_BOXES, ground_grass, 1.4),
    'canopy_shade':   _day('canopy_shade', np.array([-0.5, 0.75, -0.4]), np.array([1.0, 0.92, 0.8]) * np.pi,
                           np.array([0.17, 0.24, 0.36]), 0.2 * np.array([0.25, 0.45, 0.15]), CANOPY_BOXES, ground_grass, 1.3, 0.45),
    'lamp_interior':  {'lights': {}, 'exposure': 6.0,
                       'scene': {'boxes': LAMP_BOXES, 'ground': bo.ground_planks, 'cam': (5.4, 1.6, 0.4),
                                 'target': (1.5, 0.8, 6.0), 'fov': 70, 'fill_fn': lamp_fill}},
}

@contextlib.contextmanager
def lights(overrides):
    old = {k: getattr(so, k) for k in overrides}
    try:
        for k, v in overrides.items(): setattr(so, k, np.asarray(v, float))
        yield
    finally:
        for k, v in old.items(): setattr(so, k, v)

def frame(name, args):
    """Same output dict as brightness_oracle.frame, for old or new scenes."""
    if name in bo.SCENES:
        return bo.frame(name, bo.SCENES[name], args)
    cfg = NEW_SCENES[name]
    key = f'set2_{name}_{args.width}x{args.height}_s{args.sun_samples}_k{args.sky_samples}_seed{args.seed}_n{args.noise_codes}'
    path = Path(args.cache) / f'{key}.npz'
    if path.is_file():
        d = np.load(path); return {k: d[k] for k in d.files}
    with lights(cfg['lights']):
        s = so.render(args.width, args.height, args.sun_samples, args.sky_samples, args.seed, cfg['scene'])
    exp = cfg['exposure']; rng = np.random.default_rng(args.seed + 1)
    disp = so.to_srgb(so.aces(s['hdr'] * exp)) + rng.normal(0, args.noise_codes / 255, s['hdr'].shape)
    src = so.from_srgb(np.round(np.clip(disp, 0, 1) * 255) / 255)
    surf = s['surface']; ya = s['albedo'] @ so.LUMA; ref = float(np.median(ya[surf]))
    x_light = np.where(surf, so.aces(ref * s['irr_luma'] * exp), src @ so.LUMA)
    f = {'src': src, 'surf': surf, 'ya': ya, 'x_light': x_light, 'albedo': s['albedo'], 'ref': np.array(ref)}
    path.parent.mkdir(parents=True, exist_ok=True); np.savez_compressed(path, **f)
    return f

ALL = list(bo.SCENES) + list(NEW_SCENES)
