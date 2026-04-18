# OlofssonianChromaLift

A scene-adaptive per-hue-band chroma vibrance shader for vkBasalt / ReShade.

Companion to [OlofssonianZoneContrast](https://github.com/petolofsson/olofssonian-zone-contrast). Same Halton sampling and temporal smoothing architecture, operating on color instead of luminance.

---

## What it does

Lifts muted colors toward the scene's own 75th-percentile chroma for their hue band — independently per band, every frame.

A dark shadowed tree and a sunlit clearing are both green, but they don't share the same saturation. This shader samples both and adapts. It never desaturates: pixels already above the target are untouched.

---

## How it works

### Color space: Oklab

All chroma work is done in [Oklab](https://bottosson.github.io/posts/oklab/) — a perceptually uniform color space where chroma (`C = √(a² + b²)`) scales consistently across all hues. Unlike HSV saturation, boosting Oklab chroma by a fixed amount looks like the same visual change on reds, greens, and blues.

### Four hue bands

Pixels are classified into four bands with smooth overlap (using circular hue distance in Oklab hue space):

| Band    | Hue center | Covers |
|---------|-----------|--------|
| Warm    | ~65°      | Reds, oranges, yellows, skin |
| Foliage | ~142°     | Greens |
| Sky     | ~-130°    | Cyans, blues |
| Cool    | ~-60°     | Purples, magentas |

### Scene sampling

Each frame: 128 quasi-random Halton(2,3) samples are taken from the back buffer. Per band, the weighted mean chroma and variance are computed — same two-pass approach as OZC.

This gives a **75th-percentile chroma estimate** per band:

```
target = mean + 0.674 × σ + BOOST_OFFSET
```

`0.674σ` is the theoretical 25th/75th percentile offset for a normal distribution — the same technique used in OZC for luma pivots.

### Vibrance model

For each pixel, if its chroma is below the band target, it is lifted toward it:

```
boost   = max(0, target − C) × BOOST_STRENGTH
new_C   = min(C + boost, SAT_MAX_C)
```

Pixels already above the target are unchanged. Dark shadowed foliage (low chroma) gets a larger absolute boost than vivid midtone foliage — which is what vibrance means.

### Temporal smoothing

The per-band stats are smoothed with `LERP_SPEED 0.08` — the same constant used in OZC, so adaptation speed is matched across the stack. A cold-start guard (no history yet) snaps immediately on first frame.

---

## Pipeline position

**Designed to run before OlofssonianZoneContrast**, not after. Reasons:

- OZC darkens shadows. Running chroma first means the shader samples the pre-contrast image — foliage in shadow is brighter and sampled correctly.
- Color character is set first, then tonal shape applied on top. Same order as professional color grading workflows.

Followed by `olofssonian_color_grade.fx` for film stock tinting, white cast, and print matrix.

Full GZW stack:

```
OlofssonianChromaLift → OlofssonianZoneContrast → ColorGrade
```

---

## Tuning

| Define | Default | Description |
|--------|---------|-------------|
| `BOOST_OFFSET` | `0.02` | Extra push beyond the 75th percentile |
| `BOOST_STRENGTH` | `1.0` | How far to pull toward target (0–1) |
| `SAT_MAX_C` | `0.28` | Hard ceiling on output chroma (pure vivid colors ≈ 0.26–0.31) |
| `LERP_SPEED` | `0.08` | Temporal adaptation speed |
| `BAND_WIDTH` | `1.05` | Hue band half-width in radians (~60°) |
| `MIN_C` | `0.02` | Skip near-neutral pixels |
| `HIGHLIGHT_GATE` | `0.93` | Protect near-white highlights (Oklab L) |

The shader has no presets and requires no tuning for different scenes — it derives all parameters from the scene itself each frame.

---

## Design notes

### Why not HSV saturation?

HSV saturation is geometrically inconsistent across hues. A green and a blue at the same HSV saturation value look very different in perceptual intensity. Worse, the S-curve approach (used in earlier versions of this shader) has a collapse problem: dark pixels with low saturation sit below the pivot and get *desaturated* toward grey, making shadows darker.

The Oklab chroma + vibrance approach solves both: perceptual uniformity across hues, and no desaturation side-effect.

### Why vibrance instead of S-curve?

An S-curve on chroma differentiates — it pushes vivid colors more vivid and muted colors more muted. But "more muted" on an already-dark foliage pixel means dark grey, and in a game scene shadows already have low chroma. The one-sided vibrance lift avoids this entirely.

If you want contrast (differentiation within a band), the right place is the luma channel — which OZC already handles.

### Why Halton sampling instead of a full histogram?

Same reason as OZC: a 4×4 history texture is effectively free, and quasi-random Halton(2,3) gives better spatial coverage than uniform random at 128 samples. Full histogram would require a reduction pass and a much larger texture.

---

## Requirements

- vkBasalt or ReShade with HLSL support
- Runs as two passes: `UpdateHistory` (writes to 4×4 texture) → `ApplyChroma` (writes to back buffer)
