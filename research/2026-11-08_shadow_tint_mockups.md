# Shadow tint from surroundings: CPU mockups v1–v9

The user rejected the [darker-range 110% candidate](2026-11-08_shadow_color_candidate.md)
as feeling like "a saturation of darker colours". They asked instead for an
alpha-like tint: shadows should take a slight tint of their surroundings' colour
and light, such as green in a green forest and red near a red light. It must work
for every hue without per-hue settings and without looking neon. These are
CPU mockups applied to source frames (no production chain). Artifacts:
`captures/shadow_tint_mockup{,2..9}_20261108/` (`mockup.py`, `review.html`).
Scenes: GZW 133750/133831 (green), 133932 (fire), 133444 (warm), 133241 (village);
Arc 210448 (red light), 210213 (desert), 205938 (interior).

## Iterations and verdicts

| Version | Model | User verdict |
| --- | --- | --- |
| v1 | first tint mockup | artifacts, no visible difference |
| v2 | linear-RGB surrounding chroma | workable at 1–2×, red stands out |
| v3 | Oklab, soft-limited surroundings' saturation | no visible difference |
| v4 | fixed hue-fair Oklab amplitude along surroundings' hue | red/yellow good, green hardly visible |
| v5 | v4 + per-hue green gain / relative amplitude | rejected: no manual per-hue adjustment |
| v6 | equal CIEDE2000 change per pixel (bisection) | "kinda good" at 1.5 |
| v7 | equal Oklch+ distance, closed form | better at 1.0; green slightly too green |
| v8 | v7 + Helmholtz–Kohlrausch darkening | H-K "looks really good"; fails around emitters |
| v9 | v8, emitter-safe | "That worked" |

Diagnosis of v4 (strength 1.5, shadow weight > .5): added a,b was about equal in
all scenes (|Δab|×100 ≈ 1.5–1.9; the saturation cap barely acted). Red-light
shadows were near neutral (C/L .04), so their chroma rose 2.3×. Green foliage
shadows were already green along the same hue (C/L .07–.12) and rose only
1.35–1.45×, which reads as nothing. Visibility depends on the starting colour,
so a fixed amount cannot be hue-fair.

## Current model (v9)

1. **Surroundings' colour.** Oklab a,b and L, averaged over mid-tone surfaces
   only, with weight `ws = smooth(.02,.10,L)·(1−smooth(.80,.95,L))`. Emitters, sky
   and near-black are excluded. The average is a 16-px block average plus three
   blur passes, bilinearly upsampled. Hue direction `u` = direction of a,b/L.
   Hue confidence = `tanh(|sat|/.04)`.
2. **Shadow weight.** log2 of the wide surface-only luminance over the regional
   luminance (4-px block). The wide average excludes emitters, so a lamp does not
   make its own glow count as shadow. Weight = `smooth(0,1.5,·)` × not-bright
   region × not-near-black.
3. **Tint.** Oklch+ (arXiv 2606.05255: L' = L^.73, C' = C^.87/(C^.87+.34^.87),
   difference = Euclidean). The tint takes one fixed-length step along `u` in the
   (a',b') plane, then inverts: C = .34·(C'/(1−C'))^(1/.87). The step is
   strength × .0442 × weight × confidence, calibrated as the median distance v4
   produced at strength 1. L is unchanged; saturation cap .45·L or the original.
4. **H-K darkening.** Lightness is lowered so the Fairchild & Pirrotta (1991)
   perceived lightness L** = L* + (2.5 − .025L*)(.116|sin((h−90)/2)| + .085)C*
   stays at the original, and it only ever darkens. This turns the added chroma
   into a deeper, darker shade rather than a brighter one. It is hue-dependent
   through the published model, not through tuned constants.
5. **Emitter safety.** A wide low-pass of emitter luminance (smooth(.8,.95,L)·y)
   is compared with regional luminance. Darkening fades out where nearby light
   dominates (`smooth(.01,.10,E/y_region)`); the tint itself stays.

Accepted strength: 1.0.

## Negative and limiting results

- **v5 per-hue green gain** worked visually but was rejected on principle.
  Relative amplitude also boosted fire (|Δab| 5.6), a neon risk.
- **CIEDE2000 (v6)** is documented as weaker for dark and near-neutral colours.
  Its lightness weighting was fitted on data with few dark samples.
- **Oklch+ (v7)** is unreviewed and was fitted on COMBVD, not dark colours. It
  lacks CIEDE2000's chroma-dependent tolerance, so it does not reproduce v6's
  green boost. The user nevertheless preferred v7 at 1.0.
- **Single-step CIEDE2000 approximation** (one secant step): median relative
  error .03–.15, but the mean amplitude was low by up to 40% in the forest.
  Not pursued after v7.
- **Saturation cap at the surroundings' saturation (v8 "cap")** removed about
  90% of the tint, because shadows are already near their surroundings'
  saturation. Dropped.
- **v8 around emitters.** In 210448 the lamp raised the wide mean, so its glow
  (L .2–.35, C/L .1–.3) received shadow weight up to 1. It was tinted, then
  darkened by up to 2 L×100, dimming the glow.
  - A log-mean context shrank shadow coverage everywhere (green 20% → 4–10%) and
    was rejected.
  - A surface-only arithmetic mean keeps green and warm coverage unchanged and
    reduces the red scene (29% → 25%), but does not remove the glow alone. Hence
    the emitter-proximity fade.
- **v9 coverage and residuals.**
  - "Near light" covers 52–57% of the frame in Arc desert and interior (sky,
    bright areas), so darkening is mostly off there.
  - Largest darkening: −5.1 L×100 on the shaded side of a saturated blue sleeve
    (village, strong H-K for blue; looked natural), and scattered low-chroma
    pixels in Arc 205938.
- **HUD and UI** cannot be distinguished, as with the earlier candidate.

## Status

This is a visual direction only. Output noise, motion, scene cuts, GPU cost and
the production chain are untested. A shader candidate would need:
- one low-resolution pass for the surroundings' colour and context luminance,
  plus the wide emitter field;
- per-pixel Oklch+ and CIELAB/H-K math;
- one strength control in `creative_values.fx`.

It would replace, not stack with, the darker-range candidate. Its direction comes
from a smooth field rather than each pixel's own chroma, but the amplitude still
depends slightly on pixel chroma, so noise needs measuring again. Nothing is
adopted.
