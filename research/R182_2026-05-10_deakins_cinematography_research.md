# R182 — Roger Deakins Cinematography Research
**Date:** 2026-05-10
**Status:** Reference / Inspiration — no implementation yet

Sources: rogerdeakins.com forum, ASC Magazine, Filmmaker Magazine, British
Cinematographer, No Film School, Hollywood Reporter, Team Deakins podcast.

---

## 1. Core Philosophy

> "I am concerned that the subtlety is being lost and every film tends to look very
> contrasty and saturated."

His DI is for refinement and shot-matching, not for imposing a look. The look is built
on set through lighting and exposure. The grade adjusts contrast and saturation "a very
small amount" — typically only the two of them (Deakins + colorist Mitch Paulson at
Company 3) can see the adjustments. Two-week DI vs. industry norm of three weeks.

**Pipeline implication:** Default knob values should be conservative. Subtlety is the
target. Over-saturation and over-contrast are the failure modes.

---

## 2. Shadow Philosophy — Earned Darkness

His darkness is constructive, not corrective. On *Shawshank*: he painted walls a
specific grey so they would drop cleanly into black at frame edges without crushing
mid-shadow detail. He designs the set/location so what the lens sees is already the
intended tonal zone. No lift needed.

On *Sicario*'s tunnel sequence: the SWAT entry was shot as a true silhouette against
the barely-lit sky. He refused fake moonlit fill because the film had established that
night is actually black — any fill would break that contract with the audience.

> "You lit the night exterior so that you could create an image the audience could see,
> but why did that make sense, because they were working in blackness? So you don't
> break the idea that night is black."

**Pipeline implication:** Shadow lift should not be a default-on correction. The
zone_std gate (R178) is philosophically aligned — only lift when the darkness is
unintentional (low zone_std). BLACKS = 0.005 (not zero) matches his "almost drop off
into black, but not quite" description exactly.

---

## 3. The 2383 LUT Shape

His show LUT (built at Company 3, used on all productions since going digital) is a
profile of Kodak 2383 print stock adapted to Alexa output. His description:

> "The only adjustment in it is to the contrast curve and the amount of color
> saturation. That is standard for any LUT that translates the RAW data."

Characteristic 2383 tonal shape:
- Lower toe: gentle roll starting at ~15% luminance — not a hard pivot
- Upper shoulder: restrained, begins around 75% luminance — no hard clip
- Saturation: ~5–8% reduction below neutral log-to-display (not a strong desaturation)

**Pipeline implication:** Our FilmCurve + PRINT_STOCK is targeting this shape. The toe
should bow gently upward in the 5–25% linear range (adding shadow density, not lifting
the floor). The shoulder should be restrained, not an aggressive S-curve crush.

---

## 4. Heavy Negative — Density in Lower-Mids

During the film era Deakins exposed his negatives heavily (printer lights ~29, targeting
high 30s/low 40s in print) to build rich shadow density — not shadow lift. His reason:

> "If you expose so the image needs to print in the high 30s/low 40s, the blacks in the
> image will be denser — richer saturation, more perceived snap."

The mechanism: a heavy negative has more silver density in the lower-mid range
(5–25% linear). When printed, these zones have richer contrast relative to true black,
while true black remains at zero. The shadow *tonality* is richer, not the shadow
*floor*.

This is distinct from lifting blacks: it is an upward bow in the lower-mid tonal range
while leaving the absolute black point at zero.

**Pipeline implication:** FilmCurve toe calibration target. The toe should add density
contrast in the 5–25% linear zone — a gentle upward bow — not a log-style lift. Our
current toe (CURVE_R_TOE, CURVE_B_TOE) works in this direction. Worth verifying the
shape against this description during calibration.

---

## 5. Pre-Flash — Colored Warm Shadow Cast

Deakins physically fogged negatives with warm colored light before shooting to inject
hue into deep shadow. The effect falls to zero by mid-gray (linear superposition on
film: the warm additive is overwhelmed by scene exposure above black).

> "I have flashed/fogged with a very warm colored light to introduce color into the
> shadows."

On *Jesse James*: intended warm pre-flash + bleach bypass together. The combination
produces warm shadow cast + desaturated midtones + retained highlight contrast.

A 5% pre-flash (white) on *Fight Club* night exteriors added ~half a stop of shadow
detail. A 15% warm pre-flash produces a visible amber-grey base fog across the darkest
zones.

This is different from R66 ambient shadow tint: pre-flash is a fixed additive offset at
the black point, warm-biased, hue-specific, scene-invariant. It does not depend on
the illuminant estimate — it is always there, always warm, always zero by mid-gray.

**Potential new knob (R183 candidate):** `SHADOW_CAST` — a fixed warm/cool additive at
the shadow floor, independent of R66's illuminant-adaptive tint. Implementation: a
small (L-gated) warm additive in Oklab ab space, `weight = 1 − smoothstep(0, 0.25, L)`,
falling to zero by mid-gray. Default 0 = off.

---

## 6. Warm/Cool Bipartite Zone Structure

Deakins consistently divides film environments into two or three color temperature zones,
each narratively motivated. Every zone has a physical light source that justifies its
color. No fill that compromises the dominant hue.

**Blade Runner 2049:**
- Los Angeles — cold blue-grey (overcast, neon pollution)
- Las Vegas — deep red/amber (in-camera: custom Tiffen Lee 790 Moroccan Pink + Lee 105
  Orange; also 20 Maxi-Brutes gelled green at stage edges to add warm-yellow into dust)
- Wallace Corporation — warm gold (3 × 25ft circular trusses of 35 × 10K lamps rotating)

> "I don't like to do an overall color correction in the DI." — Filter baked in-camera.

The Moroccan Pink + Orange spectral mix preserves skin tones while desaturating greens
heavily — which is why the dusty Vegas landscape reads correctly. A straight orange
filter shifts skin into unacceptable territory; the pink component counteracts this.

**Skyfall:**
- Istanbul (opening) — hot, overexposed, warm. Single T12 lamp for sunlight.
- Shanghai (skyscraper fight) — cold blue. Lit only by LED jellyfish advertisements
  (deep blue). No supplemental lights.

> "We wanted the whole Shanghai section to feel quite cold."

**Pipeline implication:** Warm highlights / cool shadows is a motivated, not arbitrary,
split. Our 3-way CC (SHADOW_TEMP / HIGHLIGHT_TEMP) is the right tool. The direction
should track the environment's light source logic, not be applied uniformly.

---

## 7. Selective Hue Desaturation — O Brother (2000)

First feature graded entirely digitally. 11 weeks at Cinesite with colorist Julius Friede.
Goal: turn Mississippi summer (green, lush) into 1930s faded postcard (burnt ochre,
straw, dust). Blues stripped almost to zero. Greens pulled to desaturated olive-yellow.

Crucially: when background greens were desaturated, an extra's orange-yellow dress
became the only saturated object in frame. Friede pulled the dress saturation separately
to let the extra disappear. Object-level hue-selective saturation control in 2000.

**Key perceptual insight:** Desaturating one hue band creates apparent saturation
increase in what remains. Pulling green/yellow makes orange/red appear more saturated
even at unchanged absolute values. This is the mechanism behind hue-specific grading —
changes in one band redistribute perceptual weight into neighbors.

**Pipeline implication:** SAT_GREEN negative + SAT_YELLOW negative = warm object
emphasis (skin, ochre, rust) without touching those hues directly. ROT_GREEN toward
yellow achieves the olive-green translation. All knobs now available.

---

## 8. Deakinizers — Optical Edge Aberration

For *Jesse James*, Deakins removed the front element from a 9.8mm Kinoptic lens and
mounted old wide-angle glass onto Arri Macro bodies, creating custom aberration
elements he called "Deakinizers."

> "Removing the front element makes the lens faster, and it also gives you this
> wonderful vignetting and slight color diffraction around the edges."

Used only for transitional shots — a 19th-century photographic aesthetic. Then bleach
bypass was applied to the negative, and the DI partially counteracted the bypass
harshness in non-Deakinizer shots.

The optical effect: radial lateral chromatic aberration + warm-to-cool chroma vignette
(warmth falls off toward frame edges, blue-green rises). Both luma vignette and chroma
aberration vignette, at different spatial frequencies, slight asymmetry.

**Potential future R:** Radial LCA + chroma vignette pass. Not a priority — Deakins
himself uses this only for specific period-film transitions, not as a general look.
Would require a new pass (performance cost). Deferred.

---

## 9. Diffusion — Firmly in Post, Not on Lens

Last in-lens diffusion filter use: circa 1985. He regretted it.

> His filter box contains ~40 filters; he has not opened it for a feature in decades.

He does not use Black Pro-Mist, fog, or any softening filters on the lens. Spatial
softness in his work comes from lighting (large sources, bounce), not filter scatter.
The BR2049 Tiffen filters were purely for color, not diffusion.

His view on lens artifacts:
> "I can't stand lens artifacts. I don't like vignetting, I don't like breathing,
> I don't like flare."

**Pipeline implication:** Diffusion belongs in post (our approach is correct). Halation
should be conservative — he treats scatter as a physical failure mode, not an aesthetic.
HAL_STRENGTH calibration should err on the low side.

---

## 10. On Film Grain

> "When you add a little digital grain to the image it is virtually impossible to
> distinguish it from film."

A practical endorsement — not nostalgia. He does not treat grain as sacred. He
considers it reproducible. Our R136/R173 grain model (Selwyn 2383, pcg3d,
per-dye-layer decorrelated) is the right approach.

---

## Summary Table — Actionable Pipeline Implications

| Deakins Pattern | Pipeline Status | Notes |
|---|---|---|
| Shadow floor near-zero, not lifted | ✓ BLACKS=0.005, zone_std gate | Confirmed correct |
| 2383 toe shape (gentle, 5–25% range) | ✓ FilmCurve + PRINT_STOCK | Calibrate toe bow |
| ~6% saturation reduction in base LUT | ✓ PRINT_STOCK desaturation | Check magnitude |
| Pre-flash warm shadow cast | ✗ Not implemented | R183 candidate: SHADOW_CAST knob |
| Warm/cool bipartite zone structure | ✓ 3-way CC SHADOW/HIGHLIGHT_TEMP | Motivated by light source |
| Hue-selective desaturation (O Brother) | ✓ SAT_* + ROT_* knobs now available | O Brother = SAT_GREEN−, ROT_GREEN→yellow |
| Diffusion in post, not in glass | ✓ Diffusion pass in grade.fx | Correct |
| Conservative halation | ~ HAL_STRENGTH 0.35 | May still be too high |
| Deakinizers (edge LCA + chroma vignette) | ✗ Not implemented | Future R, low priority |
| Film grain reproducible digitally | ✓ R136/R173 Selwyn model | Confirmed approach |
