# R56 — Film Halation — Findings

**Date:** 2026-05-01
**Searches:**
1. film halation emulsion dye layer red scatter physics antihalation backing
2. 35mm film halation radius scatter distance emulsion thickness pixels
3. film halation luma threshold display referred specular highlights visibility
4. halation vs bloom difference cinema film digital comparison
5. Kodak Fuji emulsion cross section dye layer order red green blue deepest
6. film halation shader GLSL HLSL DCTL chromatic red channel implementation

---

## Key Findings

### 1. Dye layer order confirmed — red is deepest

The tri-pack emulsion layer order (lens-facing → film base) is:
1. **Blue-sensitive layer** — shallowest, first to receive light
2. **Green-sensitive layer** — middle
3. **Red-sensitive layer** — deepest, nearest the film base

Sources: Britannica (Colour Film Structure), Dehancer blog, Reddit r/cinematography,
Color.io user guide. All consistent.

**Why red dominates halation:** Light penetrates all three layers front-to-back. When it
reaches the anti-halation backing (or the film base in stocks without full anti-halation),
it reflects back upward. Blue and green wavelengths have already been absorbed by their
respective filter layers on the way down; the reflected light is predominantly red. The
reflected red light then re-exposes the red-sensitive layer from behind, creating the
characteristic warm/red fringe. Blue gets effectively zero secondary exposure; green gets
a small amount. This is physically confirmed by Lomography, Wikipedia (Anti-halation
backing), and multiple cinematography forums.

**Shader implication:** Blue channel gets zero halation contribution. Green gets a small
amount (mip 0 at low weight). Red gets the most (mip 0–1). The current R37 implementation
assigning `diffused.b` to the blue scatter source is physically incorrect and should be
corrected to zero.

---

### 2. Physical scatter radius — tight, confirmed tighter than bloom

Published measurements from shader implementations and industry tools:

- **GitHub film halation DCTL (xjackyz):** Typical radius 8–10 pixels at 1080p
- **DaVinci Resolve film emulation:** Halation radius 3–8 px; bloom 10–15 px
- **Medium (Martin McGowan):** Halation is "much tighter spread vs the much more
  diffuse Bloom" — approximately 60–80% of bloom radius
- **Physical constraint:** 35mm film base is 0.110–0.180 mm thick; emulsion layers are
  micrometres. At 1920px width, halation scatter maps to roughly 8–12 pixels — sub-1%
  of frame width. This is significantly tighter than any typical bloom implementation.

**Implication for this pipeline:** `CreativeLowFreqTex` is 1/8-res. At 1920×1080, that is
240×135 — each texel covers 8×8 source pixels. Mip 0 of this texture already spans
approximately 8-pixel radius in source-resolution terms, which matches the physical halation
radius. Mip 1 (1/16-res) spans ~16 pixels — already on the wide edge for true halation.
Mip 2 (1/32-res, ~32 pixels) is too wide — this is bloom territory, not halation.

**Current R37 uses mip 2 for the red channel — confirmed too wide.** Replace with mip 1
for red, mip 0 for green, zero for blue.

---

### 3. Luma threshold — 0.85 is on the high side but defensible for SDR

No canonical display-referred threshold exists in the literature. Findings:

- **GitHub DCTL (xjackyz):** Dual threshold: low = 0.5 (activation), high = 3.5 stops
  (full strength). These are scene-linear values, not display-referred.
- **DaVinci Resolve implementations:** Luma key threshold typically 0.75–0.80
  display-referred in tutorials.
- **Industry consensus:** Halation is "most noticeable in high-contrast areas — bright
  window in a dark room, streetlights at night." This is a contrast-ratio dependency,
  not an absolute luma dependency.
- **HDR/SDR note:** Color.io confirms halation is "much less visible on HDR than SDR"
  because in HDR the specular highlights are above display white — they carry more
  energy above the halation threshold naturally. In SDR, true specular clips at 1.0,
  so the threshold must be tuned lower than it would be in a scene-linear or HDR context.

**Recommendation:** Use 0.80 as activation start, 0.95 as full strength in display-referred
SDR. This is lower than the proposed 0.85 and better covers the "streetlight at night"
case where practical lights sit at 0.80–0.85 display-referred in Arc Raiders.

```hlsl
float hal_gate = smoothstep(0.80, 0.95, hal_luma);
```

This is a smoothstep (no hard conditional) — compliant with CLAUDE.md no-gates rule.

---

### 4. Halation vs bloom — confirmed distinct, complementary not redundant

| Property | Halation | Game bloom (Arc Raiders) |
|----------|----------|--------------------------|
| Color | Red/warm chromatic | Neutral to slightly warm |
| Radius | 8–12 px (tight) | 20–50+ px (wide) |
| Physics | Film base reflection | Optical/sensor diffusion |
| Fires from | Specular, practicals | Any overexposed pixel |
| Additive | Yes | Yes |

Halation and bloom are complementary: halation provides the tight chromatic fringe;
bloom provides the wide neutral glow. Both firing simultaneously on the same highlight
source is physically correct — real film exhibited both on bright practical lights.

The risk is not redundancy but **stacking amplitude** — both add light to the same
highlight pixels, potentially pushing them to SDR clip. The `max(0, scatter − base)`
formulation handles this: where the game bloom has already elevated surrounding pixels
to near clip, `scatter − base` approaches zero and the delta contribution is minimal.
This is self-regulating without requiring explicit bloom-detection logic.

---

### 5. Manual knob vs scene-adaptive strength

The industry overwhelmingly uses a manual strength knob: Dehancer, FilmConvert, Color
Finale, Color.io, the GitHub DCTL — all expose a user-facing intensity slider. Scene-
adaptive halation (FilmConvert Nitrate's "light-responsive" mode) exists but is the
exception and is opaque to the user.

**Recommendation: `HAL_STRENGTH` as a user knob with scene-adaptive gate only.**
The gate (smoothstep 0.80–0.95) controls where halation fires automatically; the knob
controls how much. This matches industry practice: the user sets strength to taste, the
physics of the threshold handles where it appears.

Default `HAL_STRENGTH = 0.35` — moderate. At this level halation is perceptible on
specular highlights in dark scenes and invisible in midtone-dominated frames.

---

### 6. Ordering with pro_mist (R55) — self-regulating, no explicit anti-stacking needed

`grade.fx` runs before `pro_mist.fx` in the chain. Halation in `grade.fx` fires first;
pro_mist scatter fires on the post-halation image.

Key interaction: pro_mist computes scatter as `max(0, diffused − base)` where `diffused`
is `CreativeLowFreqTex` written by `corrective.fx` — **before** grade.fx runs. After
halation lifts highlight-adjacent pixels, `base` in those pixels is higher than the
pre-grade `diffused`. The delta `diffused − base` becomes negative → clamped to zero →
pro_mist adds no scatter in halation-lifted regions.

The two effects are therefore **mutually attenuating at their overlap zone** by construction.
No explicit interaction logic is needed. The one caveat: very bright pixels (luma > 0.90)
where halation fires strongly may suppress pro_mist scatter entirely in those regions.
This is perceptually correct — the film halation ring should not be softened by a separate
diffusion layer on top.

---

## Parameter Validation

### Proposed implementation (inside `ColorTransformPS`, end of Stage 3)

```hlsl
// R56: film halation — tight chromatic emulsion scatter, red-dominant
float3 hal_r = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).rgb;  // mip 1 — red spreads most
float3 hal_g = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 0)).rgb;  // mip 0 — green tighter
float  hal_luma = dot(col.rgb, float3(0.2126, 0.7152, 0.0722));
float  hal_gate = smoothstep(0.80, 0.95, hal_luma);

float3 hal_delta = float3(
    max(0.0, hal_r.r - col.r),   // red: wide scatter
    max(0.0, hal_g.g - col.g),   // green: tight scatter
    0.0                           // blue: none (film physics)
);
col.rgb = saturate(col.rgb + hal_delta * float3(1.2, 0.45, 0.0) * hal_gate * HAL_STRENGTH);
```

Two `tex2Dlod` calls — mip 1 for red (already sampled by Retinex at LOD 1; reuse that
sample), mip 0 for green. At default `HAL_STRENGTH = 0.35`:
- True white input (1.0): `hal_r.r − 1.0 ≤ 0` → delta = 0 (no effect at peak)
- Adjacent pixel at luma 0.85 next to a 1.0 highlight: `hal_r.r ≈ 0.90`, delta = 0.05,
  contribution = 0.05 × 1.2 × 1.0 × 0.35 ≈ 0.021 linear → adds slight red warmth. ✓
- Midtone pixel at luma 0.50: `hal_gate = smoothstep(0.80, 0.95, 0.50) = 0` → no effect. ✓

### `HAL_STRENGTH` knob range

| HAL_STRENGTH | Effect |
|-------------|--------|
| 0.0 | Off (identity) |
| 0.20 | Subtle — visible only on very bright practicals |
| 0.35 | Default — perceptible in dark scenes, invisible in bright |
| 0.60 | Strong — cinematic, noticeable warm fringe on all specular |
| 1.0 | Film stock maximum — aggressive, Ektachrome-style |

---

## Risks and Concerns

### 1. Mip 1 re-use with Retinex

`grade.fx` already samples `CreativeLowFreqTex` at LOD 1 for Retinex. If the Retinex
sample is in a local variable, reuse it for `hal_r` rather than issuing a second
`tex2Dlod`. Check `grade.fx` for the Retinex sample site and consolidate.

### 2. `saturate()` required after halation addition

Halation is additive. In very bright scenes with high `HAL_STRENGTH`, the addition could
exceed 1.0 before the final saturate. The implementation above has `saturate()` wrapping
the assignment — confirm the final `col.rgb` at function return also goes through
`saturate()` or that the pass output is declared `SV_Target` with implicit clamp.

### 3. Blue = 0 changes R37 behaviour visibly

The current R37 assigns `diffused.b` to the blue scatter source, giving blue a glow that
is physically incorrect but may have been tuned into the look. Setting blue to 0 will
remove this and slightly cool the halation. Monitor whether the warm character is
preserved by the red channel alone or if a small green boost compensates.

---

## Verdict

**Proceed. Two `tex2Dlod` calls, one knob, zero new passes.**

Implement inside `ColorTransformPS` at end of Stage 3, after chroma/density. Reuse the
existing Retinex mip 1 sample for the red channel if available. Add `HAL_STRENGTH = 0.35`
to `creative_values.fx`. Remove the R37 halation block from `pro_mist.fx` as part of R55.

The self-regulating ordering (halation before pro_mist in the chain) means no explicit
anti-stacking logic is needed. Both effects can be tuned independently without fighting.
