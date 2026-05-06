# R119 — Shadow Lift Color Stability
**Date:** 2026-05-06

---

## Problem Statement

Shadow lift (TONAL stage, grade.fx) is producing wrong object colors in lifted shadow regions.
Objects that should appear neutrally dark take on incorrect hues after lift is applied.
Confirmed by user: setting SHADOW_LIFT_STRENGTH = 0 eliminates the artifact. The issue implicates
the lift itself and the chroma coupling stages that follow it (R65, R66).

---

## Code Path

```hlsl
// 1. Luma lift — scalar, post-Retinex
float shadow_lift = shadow_lift_str
                  * (0.149169 / (illum_s0 * illum_s0 + 0.003))
                  * local_range_att * texture_att * detail_protect * context_lift;
float lift_w  = new_luma * smoothstep(0.30, 0.0, new_luma);
new_luma      = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w * SHADOW_LIFT_STRENGTH);

// 2. R62: chroma-stable tonal — apply luma ratio to Oklab L
float r_tonal = new_luma / max(luma, 0.001);
float cbrt_r  = exp2(log2(r_tonal) * (1.0 / 3.0));   // cube-root for Oklab L
lab_t.x = saturate(lab_t.x * cbrt_r);

// 3. R65: couple a/b to L — maintains C/L during lift
float r65_sw = smoothstep(0.30, 0.0, lab_t.x);        // only deep shadows
lab_t.y *= lerp(1.0, cbrt_r, r65_sw);
lab_t.z *= lerp(1.0, cbrt_r, r65_sw);

// 4. R66: ambient shadow tint — lerp achromatic shadows toward scene illuminant hue
float achrom_w = 1.0 - smoothstep(0.0, 0.05, length(lab_t.yz));
float r66_w    = r65_sw * achrom_w * (1.0 - scene_cut) * 0.4;
lab_t.y = lerp(lab_t.y, lab_amb.y, r66_w);
lab_t.z = lerp(lab_t.z, lab_amb.z, r66_w);
```

---

## Identified Issues

### Issue A — R65 amplifies pre-existing color casts

R65 scales Oklab a/b by `cbrt_r` (the luma lift ratio, cube-root). For lifted shadows,
cbrt_r > 1.0 — so a/b are amplified along with L.

Intention: maintain C/L ratio (Oklab saturation) during lift — if shadow was at saturation
S before lift, it stays at S after. Physically motivated: lifting a shadow reveals more of
the reflectance at constant saturation.

**Problem:** Objects in game shadow already carry a color cast from bounce light, indirect
illumination, or game VFX. When R65 scales a/b by cbrt_r, it amplifies that cast proportionally.
A slight green-tint in shadows becomes a strong green. The user sees "wrong object colors" because
the pre-lift tint (which was subtle and acceptable) becomes salient post-lift.

**Root cause:** R65's model assumes the pre-lift color is the ground truth. If the shadow's
color is an artifact of the game engine's lighting rather than scene reflectance, amplifying
it is wrong.

### Issue B — R65 + R66 compound on near-achromatic pixels

R66's achrom_w gate (`smoothstep(0.0, 0.05, C)`) targets near-achromatic shadows. But after
R65 scales a/b upward, a pixel that was near-achromatic (C ≈ 0.03) may now be at C ≈ 0.05
(above the gate threshold) — R66 fires partially on it. Then R66 pushes toward ambient hue.
Two tinting operations compound where only one was intended.

### Issue C — illum_s0 from 1/16-res blurs object boundaries

The shadow lift denominator uses `illum_s0` from LowFreqMip1 (1/16-res, ~67px radius at 1080p).
Objects within the same illuminant zone share the same lift coefficient. Object boundary pixels
— where the foreground object is darker than the background zone luma — get the same lift as
the uniform region behind them. This reduces perceived object separation in shadows and
contributes to the "smeared" appearance.

### Issue E — detail_protect differentially flattens micro-contrast (texture smoothing)

`detail_protect = smoothstep(-0.5, 0.0, log_R)` where `log_R = log2(new_luma / illum_s0)`.

- Pixel brighter than local illuminant (raised surface, specular): log_R > 0 → detail_protect = 1.0 → full lift
- Pixel matching local illuminant: log_R = 0 → detail_protect = 0.5 → half lift
- Pixel darker than local illuminant (recessed surface, true shadow): log_R < -0.5 → detail_protect = 0 → no lift

Intention: protect specular highlights from being lifted (they don't need shadow recovery).
Actual effect: within a dark zone, raised surfaces (micro-highlights) get more lift than
recessed surfaces (micro-shadows). This differentially brightens the bright-in-dark while
suppressing the dark-in-dark — compressing local contrast within the zone. Texture reads as
a flatter, smoother surface because the albedo variation (light vs dark texel) is reduced.

This is fundamentally different from coarse-scale blur-smoothing. It is **contrast compression
within the shadow region** caused by the detail_protect weighting function.

### Issue F — texture_att uses coarse local_var, misses fine detail

`texture_att = 1.0 - smoothstep(0.005, 0.030, local_var)` where
`local_var = abs(illum_s0 - illum_s2)` — the difference between 1/16-res and 1/32-res
illuminant maps.

This attenuates the lift in medium-frequency zones (where the two blur scales disagree),
but fine texture (high spatial frequency, sub-pixel-16-res variation) is invisible to both
scales. Fine-grained surface texture — fabric, skin pores, leather grain — sits below
the resolution of both illuminant maps and gets full lift with no texture_att protection.
Combined with Issue E, this creates a compound smoothing: fine detail gets lifted uniformly
(same shadow_lift coefficient) while its local micro-contrast is simultaneously compressed.

### Issue E — Shadow lift flattens micro-contrast (texture smoothing)

`detail_protect = smoothstep(-0.5, 0.0, log_R)` where `log_R = log2(new_luma / illum_s0)`.

Within a dark zone, raised surface texels (brighter than local illuminant, log_R > 0) get
full lift. Recessed texels (darker than local illuminant, log_R < -0.5) get zero lift.
This differential treatment converges bright-in-dark and dark-in-dark texels toward the
same lifted level — local albedo contrast is compressed. Fine surface texture (fabric, skin,
leather) reads as flat and smeared because the micro-contrast that defines it is reduced.

Additionally, `texture_att = 1.0 - smoothstep(0.005, 0.030, local_var)` uses
`local_var = abs(illum_s0 - illum_s2)` — the difference between 1/16-res and 1/32-res maps.
Fine texture at full resolution is below the resolution of both scales and is invisible to
this attenuator. High-frequency surface detail receives full lift with no protection.

### Issue D — No chroma ceiling in TONAL stage

After R65 amplifies a/b and R66 adds tint, there is no chroma ceiling before the output
is passed to the CHROMA stage. R73 (HueCeil) in CHROMA operates on the already-tinted result.
If R65+R66 push chroma past the natural ceiling in a hue direction, R73 cannot reduce it.

---

## Research Questions

1. **C/L preservation vs. C preservation during lift**: Is scaling a/b by the luma ratio
   (C/L constant) physically correct? Or should absolute C be held constant during shadow lift?
   What does color appearance modelling (CAM16, CIECAM02) say?

2. **Shadow lift in professional grading**: How do DaVinci Resolve's lift controls handle
   chroma stability? Do they preserve C, preserve C/L, or operate in a different space?

3. **Achromatic shadow lift in film**: When film print stock (Kodak 2383) lifts the toe,
   does it affect chromatic shadow pixels differently than achromatic ones?

4. **Separation of reflectance and illumination tint in shadows**: In physically correct
   shadow rendering, what portion of shadow color is reflectance vs. ambient illumination?
   How should a post-process lift distinguish them?

5. **Alternative: lift L only, suppress a/b scaling**: If R65 is removed (a/b not scaled),
   does lifting L alone in Oklab preserve perceptual colour correctly? What are the failure
   modes?

6. **Contrast-preserving shadow lift**: What methods exist for lifting shadow luma without
   compressing local micro-contrast? Does multiplicative lift preserve local contrast ratios
   better than additive? Is there a per-pixel approach that lifts the local mean without
   affecting local variance?

7. **Fine-texture detection**: What full-resolution signal can gate shadow lift away from
   fine texture detail that is invisible to the 1/16-res illuminant maps?

---

## Pre-Research Hypotheses

- H1: C constant during lift (not C/L constant) is more correct for dark neutral objects —
  an object that is dark-grey with slight green tint should still have the same absolute
  greenness after brightening, not proportionally more green.
- H2: R65 should only fire on pixels below some absolute-C threshold — very saturated shadows
  may benefit from C/L preservation, but near-neutral shadows should not have a/b amplified.
- H3: R66 tint weight 0.4 is too aggressive — halving it (0.2) and gating more strictly on C
  would preserve scene colour without the compound tinting.
- H4: The 1/16-res illum_s0 is too coarse for object-edge preservation — a dual-scale approach
  (take min of fine and coarse illuminant) would protect object boundaries.
- H5: The detail_protect weighting (more lift for bright-in-dark, less for dark-in-dark) is
  the primary mechanism of texture smoothing. Inverting or flattening it would restore
  micro-contrast at the cost of some highlight protection.
- H6: A full-resolution texture gate (e.g. abs(pixel - LowFreqMip1) as a local gradient
  proxy) added to the lift attenuation chain would protect fine detail that local_var misses.
