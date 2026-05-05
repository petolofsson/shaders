# R66 — Scene-Ambient Shadow Tinting

**Date:** 2026-05-02
**Status:** Proposed

## Problem

R65 (Hunt chroma coupling) scales existing a/b during shadow lift — it preserves
saturation for pixels that have some chroma. It cannot help pixels where a ≈ 0, b ≈ 0
(genuinely achromatic shadow geometry — unlit walls, dark metal, deep shadow). Those
pixels stay gray after lift regardless of n, because there is nothing to couple.

In real-world scenes, no shadow is truly neutral. Shadows pick up the dominant ambient
light: blue skylight outdoors, warm fill light indoors, colored bounce from nearby
surfaces. The absence of any ambient hue in lifted shadows is what makes them read as
artificial.

## Hypothesis

Injecting a small fraction of the scene's ambient hue into lifted shadow pixels —
proportional to both lift amount and pixel achromaticity — would make lifted shadows
look physically plausible rather than gray. The injection must be scene-adaptive
(auto-derived from the frame), not a fixed tint, to remain game-agnostic.

## Available data (no new passes)

| Source | What it provides |
|--------|-----------------|
| `CreativeLowFreqTex` mip 2 | 1/32-res base image — smoothed scene color at each spatial location. `.rgb` contains low-freq color signal. Sampling at screen UV gives local ambient hue. |
| `ChromaHistoryTex` col 6 | `zone_log_key`, `zone_std` — scene key and contrast. Modulates tint strength. |
| `lift_w` (already computed) | Shadow lift weight `new_luma × smoothstep(0.30, 0, new_luma)` — natural gate for where tinting applies. |
| `lab_t` after R65 | Post-coupling Oklab — ready for a/b injection. |

`CreativeLowFreqTex` mip 2 is already sampled in Stage 2 (as `illum_s2`). The `.rgb`
channels at that mip encode the low-frequency scene color — a natural ambient estimate.

## Research questions

1. Does `RGBtoOklab(illum_s2_rgb).yz` give a stable, usable ambient hue direction
   frame-to-frame, or is it too noisy to use without additional temporal smoothing?

2. What injection strength avoids visible tinting on neutral surfaces (gray walls, black
   floors) while being perceptible on shadow transitions?

3. Should injection be gated by pixel achromaticity (`1 - smoothstep(0.0, 0.05, C)`)
   so it only fires when C is near zero, or is a uniform injection cleaner?

4. Does sampling at the pixel's own UV (local ambient) produce better results than
   sampling at screen center (global ambient)? Local is physically correct; global is
   more stable and simpler.

## Proposed implementation sketch

After R65 coupling, still inside the `lab_t` block:

```hlsl
// R66: ambient shadow tint — inject scene-ambient hue into achromatic lifted shadows
float3 illum_s2_rgb = tex2Dlod(CreativeLowFreq, float4(texcoord, 0, 2.0)).rgb;
float3 lab_amb      = RGBtoOklab(illum_s2_rgb);
float  achrom_w     = 1.0 - smoothstep(0.0, 0.05, length(lab_t.yz));
float  r66_w        = r65_sw * achrom_w * 0.4;  // 0.4 = starting strength
lab_t.y = lerp(lab_t.y, lab_amb.y * 0.5, r66_w);
lab_t.z = lerp(lab_t.z, lab_amb.z * 0.5, r66_w);
```

`r65_sw` (shadow gate, already computed) constrains injection to the lift region.
`achrom_w` focuses injection on near-neutral pixels — chromatic pixels get less tinting.
`lab_amb.yz * 0.5` — half the ambient chroma, not the full signal; scene-wide mip 2 is
already very low-chroma, so this keeps injection subtle.

No new texture taps: `illum_s2` RGB is available but currently only `.a` (luma) is used.
No new passes, no new textures.

## Interaction with R65

R65 and R66 are complementary and non-overlapping:
- R65 fires on pixels that have existing chroma (a/b ≠ 0) — scales them up
- R66 fires on pixels that are achromatic (a/b ≈ 0) — injects ambient hue

Both are gated to the shadow region via `r65_sw`. Together they cover the full shadow
lift artifact space.

## Risk

- If `illum_s2` is too warm/cold frame-to-frame (scene cuts, rapid lighting changes),
  tinting could flicker. Mitigation: the Kalman temporal filter in corrective already
  smooths zone history — if needed, use `slow_key` (R60 EMA) as an additional gate
  to suppress tinting during scene cuts.
- Over-tinting neutral surfaces is the main aesthetic risk. `achrom_w` gating and the
  `0.4` strength factor are the primary controls.

## Success criterion

Lifted shadow regions that are genuinely achromatic take on a subtle ambient hue
consistent with the rest of the scene rather than reading as neutral gray. Effect should
be imperceptible on chromatic surfaces and on non-lifted pixels.
