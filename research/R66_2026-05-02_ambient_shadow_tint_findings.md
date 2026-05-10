# R66 Findings — Scene-Ambient Shadow Tinting

**Date:** 2026-05-02
**Status:** Implement

---

## Physical basis confirmed

Outdoor shadows receive no direct sunlight — they are illuminated entirely by skylight.
Rayleigh scattering preferentially scatters short wavelengths (blue), giving the sky
a color temperature of ~7000–10000K (open shade ~7000K, blue sky alone ~10000K) against
direct sunlight at ~5500K. This ≥1500K gap is the physical cause of the familiar
blue-cool shadow tint in outdoor scenes.

Indoors, the ambient depends on fill lights. In Arc Raiders (UE5/Lumen), shadows receive
engine-computed indirect light — the tint varies by scene. This is why the source for the
tint must be **scene-derived**, not a fixed color.

The pipeline has no post-process representation of this — lifted achromatic shadow pixels
emerge neutral gray. R66 corrects this.

---

## CreativeLowFreqTex RGB is valid color data

Confirmed from `corrective.fx:227`:

```hlsl
return float4(rgb, Luma(rgb));
```

`.rgb` = linear RGB (4-tap downsampled from BackBuffer), `.a` = luma. Hardware mip
generation averages `.rgb` at each level. `illum_s2` (mip 2, already sampled in Stage 2)
carries valid color — it has been used only for its `.a` channel until now.

**No new taps required.** `illum_s2` is already a `float4`; switching from `.a` to `.rgb`
costs nothing.

---

## Temporal stability: mip 2 is sufficient without extra smoothing

Mip 2 of CreativeLowFreqTex is 1/32-res (60×34 at 1080p). Each texel is a spatial
average of 256 original pixels (the base pass uses a 4-tap filter, then hardware mip
averaging). By the signal averaging principle (variance ∝ 1/N), averaging 256 samples
reduces variance 256× and standard deviation 16× relative to a single-pixel sample.

Frame-to-frame, this color signal changes only when the aggregate color of 256 pixels
shifts — i.e. camera pan through a radically different region, or a hard scene cut.
Camera pans produce smooth, gradual changes; scene cuts are abrupt but already handled
by `SceneCutTex` in the pipeline.

**No additional EMA or temporal filter needed for mip 2 color.**

Defensive measure for scene cuts: multiply `r66_w` by `(1.0 - scene_cut)`. One extra
scalar multiply. Since shadow pixels are near-black, one frame of wrong ambient hue
during a cut is perceptually negligible — this is optional but cheap.

---

## Null signal problem and fix

If a shadow pixel is surrounded by uniformly dark content at mip 2 scale (e.g. a dark
room filling the screen), `illum_s2.rgb` will be near-zero and carry no reliable hue.
Converting raw `illum_s2.rgb` to Oklab gives a/b ≈ 0 — no tinting would be injected,
which is correct: a uniformly dark scene has no ambient color to derive.

However, a partially lit scene where the shadow pixel happens to be near a dark corner
could underestimate the ambient hue. Fix: normalize the RGB to extract the hue direction
independently of luminance, then evaluate at a fixed reference luminance:

```hlsl
float3 illum_s2_rgb = tex2Dlod(CreativeLowFreq, float4(texcoord, 0, 2.0)).rgb;
float  illum_lum    = max(Luma(illum_s2_rgb), 0.001);
float3 illum_norm   = illum_s2_rgb / illum_lum;        // hue direction only
float3 lab_amb      = RGBtoOklab(illum_norm * 0.18);   // evaluate at 18% gray
// lab_amb.yz now encodes hue direction decoupled from local luminance
```

Evaluating at `0.18` (18% gray, standard photographic mid-tone reference) gives stable
a/b magnitudes regardless of whether the local region is bright or dark. If the ambient
truly is neutral (gray), `illum_norm * 0.18` converts to Oklab with a/b ≈ 0 — no tint.
If the ambient is blue-cool, a/b encode that direction.

---

## Local vs global ambient sampling

Sampling at the pixel's own UV is physically correct: shadow in a sunlit corridor gets
the corridor ambient, shadow in a dark cave gets the cave ambient. Mip 2 spatial extent
(256-pixel coverage) is large enough to be representative without being a single global
value, and the normalization above decouples it from local luminance.

Global sampling (e.g. UV = 0.5, 0.5) would be simpler but would tint all shadows with
the screen-center ambient regardless of position. Not recommended.

---

## No prior art found

No published post-process technique for automatic scene-adaptive ambient shadow tinting
was found in the literature (2020–2026). Most shadow coloring work is in the rendering
domain (GI, Lumen, SSAO tinting). This is a novel application of the existing
`CreativeLowFreqTex` infrastructure.

---

## Implementation

Insert after R65 coupling, still inside the `lab_t` block (grade.fx ~line 330):

```hlsl
// R66: ambient shadow tint — inject scene-ambient hue into achromatic lifted shadows.
// illum_s2 already sampled above; use .rgb (color) not just .a (luma).
float3 illum_s2_rgb = tex2Dlod(CreativeLowFreq, float4(texcoord, 0, 2.0)).rgb;
float  illum_lum    = max(Luma(illum_s2_rgb), 0.001);
float3 lab_amb      = RGBtoOklab((illum_s2_rgb / illum_lum) * 0.18);
float  achrom_w     = 1.0 - smoothstep(0.0, 0.05, length(lab_t.yz));
float  r66_w        = r65_sw * achrom_w * (1.0 - scene_cut) * 0.4;
lab_t.y             = lerp(lab_t.y, lab_amb.y, r66_w);
lab_t.z             = lerp(lab_t.z, lab_amb.z, r66_w);
```

**Gate stack:**
- `r65_sw` — shadow region only (L_ok < 0.30)
- `achrom_w` — only where C ≈ 0 (truly gray pixels); chromatic pixels unaffected
- `(1.0 - scene_cut)` — suppressed during hard cuts
- `0.4` — starting strength; tune toward 0.6 if too subtle, 0.2 if too visible

**GPU cost:** 1 extra tex2Dlod (mip 2, already in cache from Stage 2), 1 RGBtoOklab
call, ~6 scalar ops. All inside existing `lab_t` block.

Note: `illum_s2` is already read in Stage 2 as `float illum_s2 = tex2Dlod(...).a`.
The new read fetches `.rgb` instead. This can be merged into the existing read if
refactoring is desired, but a second sampler call at the same coord/lod is trivially
cached by the GPU.

---

## Interaction with R65

| Pixel type | R65 | R66 |
|---|---|---|
| Shadow, C > 0 (colored shadow) | Scales a/b up | `achrom_w` ≈ 0, no injection |
| Shadow, C ≈ 0 (gray shadow) | No-op (a/b ≈ 0) | Injects ambient hue |
| Midtone / highlight | `r65_sw` = 0 | `r65_sw` = 0 |

The two are complementary and non-overlapping. Together they eliminate the full
gray/ashy shadow lift artifact space.

---

## Verdict

Implement. Scene-cut gate optional but costs one multiply — include it.
Starting strength 0.4 is conservative; expect to tune upward after visual testing.
