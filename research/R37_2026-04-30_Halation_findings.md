# R37 — Film Halation — Findings
**Date:** 2026-04-30
**Searches:**
1. "film halation physics emulsion layers light scatter red channel base"
2. "photographic halation emulsion depth red green blue layer order 35mm color film structure"
3. "film halation real-time shader implementation bloom Gaussian blur mip chain chromatic"
4. "halation vs lens bloom vs lens flare distinct phenomena cinematography physics difference"
5. "film halation additive blend mode compositing screen mode correct physically"
6. "halation DCTL open source highlight threshold luma gate strength value"

---

## Key Findings

### 1. Physics: emulsion layer order and why red scatters widest

Color negative film is structured (top to bottom): **blue-sensitive → yellow filter → green-sensitive → red-sensitive → anti-halation layer → film base**. This layer order is confirmed by Britannica, LibreTexts, Wikipedia (C-41 process), and multiple film-optics sources.

When strong light passes through all emulsion layers and reaches the film base (or its backing), it partially reflects back upward. The **red-sensitive layer is the last emulsion layer before the base** — meaning reflected light strikes red first on its return path. This is the direct physical cause of the red/orange tint of halation:

> "Really strong light rays are so strong that they partially bounce off the anti-halation layer and scatter back into the last layer, namely the red one. This is the reason for the distinct redness of classic film halation." — Prodigium Pictures

> "The red layer is hit by the reflected light first. This reflection creates the distinct red glowing effect or 'halation'." — Color.io

> "This effect starts with a red glow because red light scatters the most. However, as the light penetrates deeper into the film, it can also reach the green dye layer, which shifts the halation glow from red to yellow, depending on the intensity." — Color Finale

> "When we take this anti-halation layer off the emulsion composition, the halo becomes much more pronounced, especially from the red-sensitive layer." — Lomography

The anti-halation layer (carbon black) absorbs the majority of reflected light. What bleeds through is strongest in red because that layer intercepts the return path first, before the reflection can reach green or blue. The R > G > B scatter width ordering in the R37 proposal directly mirrors this physical sequence.

The claim in R37 that R scatters **widest** (not just strongest) is also physically grounded: reflected light scatters laterally as it travels back through the emulsion base and layers, so the deeper the layer, the more lateral spread accumulates. Red, being deepest, sees the most substrate traversal and therefore the widest spatial scatter.

### 2. Scatter radius and the mip-level approximation

No academic paper was found that specifies exact Gaussian sigma values for 35mm halation. However, Dehancer's documented model and industry colorist practice provide useful calibration:

- Dehancer distinguishes "Local Diffusion" (tight scatter around the highlight source — roughly equivalent to mip 0/1) from "Global Diffusion" (secondary, diffuse scatter affecting midtones — analogous to mip 2).
- The monomodes DCTL and xjackyz DCTL implementations use radius in the range 12–16 pixels at 1080p for the red channel, which at 1/8-res effectively corresponds to 1.5–2 pixels at the low-res level — consistent with mip 1/2 sampling of a 1/8-res texture.
- Dehancer explicitly notes: "The smaller the frame, the larger the Halation and Bloom effects are relative to it. On 16mm, halos are more visible than on 35mm." This inverse relationship means 35mm halation is genuinely subtle, supporting a default strength of ~0.18 and scatter radii that are moderate relative to frame size.

The mip chain approach (mip 0 = 1/8-res, mip 1 = 1/16-res, mip 2 = 1/32-res of the original) produces three Gaussian-equivalent blur radii at effectively 8px, 16px, and 32px at source resolution (given `CreativeLowFreqTex` is already 1/8-res). This range — from a tight halo at 8px to a wide soft glow at 32px — is consistent with industry emulations for a 35mm-equivalent frame.

### 3. Real-time / shader emulation techniques

No Unreal Engine or Unity built-in halation pass was found. Bloom in game engines (Unreal's FFT/Gaussian bloom, Unity's physical bloom) does not distinguish R/G/B radii — it is chromatic-neutral. Game-engine bloom is therefore **not** a halation emulation; it is a distinct lens optical phenomenon.

The standard real-time approximation (confirmed by multiple colorist tools including Dehancer, DCTL implementations, Color Finale, and the Darktable guide) is:
1. Extract highlights above a threshold (or gate by luma)
2. Apply a large blur to the isolated channel(s) — often red only, or R wider than G
3. Composite the blurred result back onto the original using **additive** or **lighten** blend mode

Using the **mip chain of an already-downsampled texture** (`CreativeLowFreqTex`) as the scatter source is an efficient approximation of this: each mip level is effectively a pre-blurred version of the luminance signal, and sampling different mip levels per channel is a zero-cost way to achieve differential blur radii within a single pass.

### 4. Chromatic halation: differential radii per channel

The R > G >> B radius ordering is universally used in physically-informed implementations:

- Lift Gamma Gain forum: "Using the red channel, you select the highlight levels at which you want halation to appear, then you blur and composite back using lighten blending mode. Sometimes I would also add halation to the green channel, at higher light levels."
- thatcherfreeman utility-DCTL: implements "Red Shift Correction" as a distinct parameter, acknowledging that re-exposure hits red channel first and hardest.
- Color Finale: red scatters first; green only reached at high intensity, producing yellow shift.
- All surveyed tools (Dehancer, halation-dctl, xjackyz, mononodes) use red as the dominant scatter channel. Blue halation is either absent or very weakly weighted.

The R37 mapping (R=mip2, G=mip1, B=mip0) is consistent with every reference found.

### 5. Halation vs. lens bloom vs. lens flare

These are three physically distinct phenomena:

| Phenomenon | Origin | Location | Color | Shape |
|---|---|---|---|---|
| **Halation** | Light reflects off film base, re-exposes emulsion | In the emulsion (focal plane) | Red/orange dominant | Soft, round, symmetric |
| **Lens bloom** | Light scatters within glass elements / aperture diffraction | In the optical path (before sensor/film) | White/neutral or color-dependent on coating | Radial glow, broader |
| **Lens flare** | Internal reflections between glass elements | In the optical path | Colored rings/streaks | Directional, follows light source angle |

Key distinctions confirmed by sources:
- Halation stays in-focus because it re-exposes the same focal plane. Bloom softens focus. Flare introduces geometry.
- "Halation is naturally subtle; most lenses produce bloom more prominently than halation" — Dehancer.
- "Halation effect rarely occurs in isolation from the bloom effect" — Dehancer/Reddit.
- Photrio: "Blooming spreads in the emulsion layers; for halation some light passes the last emulsion layer, rebounds, and comes back — they are different mechanisms."
- Coma distortion can resemble halation visually but does not produce red coloration (analog.cafe).

The R37 proposal is correctly framed as halation (film-plane, red-dominant, symmetric), not bloom (which is what `pro_mist.fx` already provides as a lens-softening analog).

### 6. Additive compositing: is it correct?

This is the one area of mild disagreement in the literature:

**For additive:**
- The physical process is purely additive: reflected light adds to the exposure that was already made. There is no subtraction.
- The hotgluebanjo halation-dctl is described as "physically accurate, has proper falloff" and uses additive compositing.
- Most fast implementations (Dehancer, Miracamp, xjackyz) use additive as the primary mode.
- PixelTools halation offers both additive and frequency-separation modes, noting both are valid depending on goal.

**Against naive additive:**
- Color.io criticizes "simply add a tinted, gaussian-blurred layer on top of the existing footage with an additive blend mode" as the common shortcut, arguing their physically-accurate model "naturally modulates existing pixels by subtly extending the core highlights then falling off exponentially."
- The r/colorists thread on halation notes that 1/x² falloff (exponential blur) is more physically correct than Gaussian, since it matches inverse-square light scatter in a scattering medium.

**Assessment for R37:** The `max(0, halo - base)` scatter delta (rather than raw `halo`) is a meaningful improvement over naive additive — it only adds *incremental* light that the blurred version contributes above the source pixel, reducing double-counting in bright areas. This is not as sophisticated as Color.io's modulation model, but is more physically grounded than raw additive. The strength knob at 0.18 keeps the effect subtle enough that the distinction is perceptually minor.

---

## Literature Support (or Lack)

| Claim in R37 | Support level | Notes |
|---|---|---|
| Red layer is deepest, scatters widest | **Strong** — confirmed by film structure references, Wikipedia, Lomography, Color.io, Prodigium Pictures, Color Finale | No counter-evidence found |
| R > G >> B radius ordering | **Strong** — all surveyed tools (Dehancer, DCTLs, LGG forum) use this ordering | Unanimous |
| Additive composite is correct blend mode | **Moderate** — physically correct in principle; Color.io argues naive additive misses proper falloff shape | R37's `max(0, halo-base)` delta addresses the main critique |
| Highlight gate (p75 threshold) is physically reasonable | **Moderate** — all implementations gate on highlights; specific threshold varies. xjackyz DCTL uses luma threshold 0.0–2.5 (scene-linear), not a fixed 0.75. p75 from PercTex is a scene-adaptive equivalent | No source uses exactly p75, but adaptive thresholding from scene statistics is more principled than any fixed value |
| Strength 0.18 is in the right ballpark | **Moderate** — hotgluebanjo: "halation is naturally subtle"; Dehancer notes 35mm halation is smaller than 16mm. 0.18 reads as subtle-to-moderate in SDR [0,1] space, consistent with "subtle" characterization | No quantitative reference found; calibrate visually |
| Mip 0/1/2 of 1/8-res texture approximates correct Gaussian radii for 35mm | **Weak-to-moderate** — no formal academic treatment found; consistent with Dehancer's local/global diffusion split and with real-time bloom implementations using mip chains for blur | Approximation is engineering-pragmatic, not physically derived |

No academic papers (SIGGRAPH, JOSA, IEEE) on photographic halation simulation were found in search results. The field appears to be entirely practitioner-documented.

---

## Parameter Validation

### `smoothstep(p75, p75+0.15, luma_in)` as highlight gate
- Physically: halation occurs when light is bright enough to overwhelm the anti-halation layer. p75 as a lower bound is reasonable — it means the top 25% of the scene luminance distribution sources halation. This is adaptive: a low-contrast scene has a lower p75, so even relatively modest highlights contribute; a high-contrast scene has a higher p75, correctly restricting halation to true highlights.
- The 0.15 transition width is seam-free (smoothstep, no hard threshold). This matches CLAUDE.md's "no gates" requirement.
- Risk: if p75 is in deep shadow territory (very low-key scene), halation could fire too broadly. A floor clamp (`max(p75, 0.5)`) might be warranted as a defensive measure.

### Channel weights `float3(1.20, 0.60, 0.25)`
- R > G >> B is consistent with all physical references.
- The 1.20 red weight (slightly above unity) amplifies the red scatter to push warm tint, which is correct — the red layer is re-exposed most strongly.
- The 0.25 blue weight is not zero, which is correct: even with anti-halation, some blue-channel leakage occurs on extreme highlights. Keeping it at 0.25 rather than 0.0 adds a small amount of blue into the glow, which mixes with the red to produce a more orange/amber halo rather than pure red — this matches the visual character of real halation more closely than pure red.

### `HALATION_STR = 0.18`
- No paper specifies a canonical strength value. All sources describe halation as "subtle" on 35mm. 0.18 in linear SDR [0,1] space is moderate — roughly 18% of full-white intensity added at the peak of the gate. Since the gate peaks only on the top highlights and the scatter delta is typically a small fraction of 1.0, the effective contribution at typical bright-but-not-clipped highlights is well below 0.18. This is in the right range.

---

## Risks / Concerns

1. **Mip-level precision:** `tex2Dlod` with hardware mip selection will use bilinear filtering, which is correct for this use case. However, if `CreativeLowFreqTex` is not stored with full mip chain generation enabled in the vkBasalt/ReShade resource declaration, mip 1 and mip 2 may not exist. Verify `MipLevels` in the texture declaration.

2. **p75 floor edge case:** On very dark scenes (night, interior shadows), p75 may be low enough that even midtones trigger the gate. Consider `saturate((luma_in - max(p75, 0.55)) / 0.15)` as a defensive lower-bound floor.

3. **Additive in SDR:** Highlights that are already near 1.0 will clip to white on the `saturate()` call. This is physically correct (overexposure saturates) but may wash out specular detail. The `max(0, halo - base)` delta already mitigates this significantly — pixels at 1.0 contribute zero scatter delta.

4. **No falloff shape:** Real halation uses inverse-square or exponential falloff from the halo center outward. Mip-based Gaussian approximation has heavier tails than real scatter. This is the standard shortcut; it is acceptable for a real-time implementation.

5. **No per-light-source shape:** Real halation halos are shaped by the light source geometry. The mip-blur approach produces round, isotropic halos. A common critique (r/cinematography) is that this "too perfectly rounded" quality is a tell. Acceptable for a game context where halation is a tonal/color tool rather than a photorealistic simulation.

---

## Verdict

**R37 is physically well-grounded and ready to implement.**

The core design decisions — R channel widest scatter (mip2), G medium (mip1), B narrowest (mip0), additive composite, warm channel weights, adaptive highlight gate via p75, strength ~0.18 — are all individually supportable from the available evidence. The mip-chain approach is a pragmatic but appropriate approximation of multi-radius Gaussian scatter that imposes zero GPU overhead given `CreativeLowFreqTex` already exists.

The one refinement worth considering before implementation: add a `max(p75, 0.55)` floor to the smoothstep gate to prevent halation from firing in dark scenes. Otherwise, the proposal as written is internally consistent and physically reasonable.

No blocking concerns identified.
