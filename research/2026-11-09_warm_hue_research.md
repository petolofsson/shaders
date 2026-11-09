# Warm-hue over-saturation: perception research and mitigation options (2026-11-09)

The user's screenshots (shader on vs off, GZW splash and menu) showed red chroma
up 20–35% and orange/yellow up 13–26%, with a +.003 to +.008 Oklab b shift. The
user asked whether a perceptual relationship explains why red and yellow look
"too much". The red marker was cropped out, so the on/off assignment comes from
the statistics. Warmth was eased to 1.75× the same day.

## Perception findings

1. **Natural colour variation runs blue–yellow.** Daylight chromaticities lie on
   the daylight locus, close to the blackbody locus and to the line between unique
   blue and unique yellow. Red–green illuminant shifts are rare. ([Webster
   2007](https://labs.psych.unr.edu/websterlab/files/WebsterNetwork2007.pdf);
   [Delahunt & Brainard 2004](https://jov.arvojournals.org/article.aspx?articleid=2121562))
2. **Viewers notice yellow shifts more than blue ones.** Illumination
   discrimination is worst toward bluer daylight: colour constancy is strongest
   there. So a cool push is discounted as "light", while a warm push of the same
   size reads as a colour change. ([Pearce et al.
   2014](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0087989))
   A later study disputes the daylight-statistics explanation, but the
   blue-bias measurement itself has been replicated.
3. **Bright colours look more colourful (Hunt effect).** Bright reds and oranges
   also look yellower (Bezold–Brücke). Warmth applied in highlights is therefore
   amplified twice for bright warm surfaces. ([Hunt
   effect](https://en.wikipedia.org/wiki/Hunt_effect_(color));
   [Bezold–Brücke](https://en.wikipedia.org/wiki/Bezold%E2%80%93Br%C3%BCcke_shift))
4. **H-K brightening is weakest for yellow and strongest for red/magenta.** This
   matches the 2026-11-08 retest, which found only about .2–.3 L*. Brightness
   from H-K is not the cause. ([Wikipedia
   H-K](https://en.wikipedia.org/wiki/Helmholtz%E2%80%93Kohlrausch_effect))
5. **Memory colours are hue-specific.** Viewers prefer skin and grass slightly
   yellower and sky bluer and purer. When asked for accuracy rather than
   preference, they often pick the accurate colour. Boosting memory colours does
   not guarantee a better image. ([Zeng
   thesis](https://etheses.whiterose.ac.uk/2090/); [Zhang et al.
   2012](https://web.engr.oregonstate.edu/~hliu/papers/Zhang_JEL_2012.pdf))
6. **Per-channel curves skew hues toward the six RGB primaries and secondaries.**
   Reds drift to orange and oranges to yellow near the gamut edge.
   ([ACEScentral](https://community.acescentral.com/t/some-reflections-and-experiments/4237/print))
   This pipeline's print/film stages are Oklab-aware, so this applies only if a
   per-channel step remains. Unverified here.

The user's hypothesis is partly right. Yellow is "natural" as *light*, along the
daylight axis, but the eye is more sensitive to yellow shifts than to blue ones.
Saturated red lies off the natural axis, so it reads as a conspicuous surface
colour. Equal Oklab steps are therefore not perceptually equal in effect: warm
pushes are seen more strongly than cool ones.

## How the pipeline adds warm chroma

All of these push in the same direction:
- **Production baseline.** The [2026-11-08 retest](2026-11-08_hk_chroma_retest.md)
  measured red/orange/amber chroma at +5%, yellow at +1% and blue at −12% against
  source, before warmth ×3.5 and saturation.
- **Warmth.** `Apply3WayCC` (`grade.fx:333`) adds a uniform Oklab +b, gated by
  `neutral_share`. Gray pixels get the full shift; saturated pixels get less. For
  a moderately saturated orange or yellow, +b still adds directly to chroma.
- **`SATURATION`.** It is a hue-uniform gain (`grade.fx:824`). The vivid guard
  trims only when `chroma_scene_scale` is below 1.
- **Per-band controls `SAT_RED` (30°) and `SAT_YELLOW` (110°).** These already
  exist but leave the problem zone mostly uncovered. With a band half-width of
  about 29°, orange and amber at about 60–85° get only weak tails from either
  control. There is no `SAT_ORANGE`.

## Mitigation options, cheapest first

| Option | Cost | Notes |
| --- | --- | --- |
| A. Keep warmth at 1.75× | none | Done. Re-check with matched screenshots. |
| B. Expose orange/amber bands (`SAT_ORANGE`) | ~2 ALU | The 12-band wheel already has orange (65°) and amber (87°) centres. Setting about −.1 would trim warm chroma where the testbed complaint sits. A shader change, so it needs authorization. |
| C. Warmth as an illuminant shift (von Kries/CAT along the daylight locus) | ~10 ALU | Scales colours like a real light change instead of adding yellow to already-yellow surfaces. Finding 2 says viewers discount daylight-axis changes. This is the principled fix. |
| D. Perceptually weighted saturation | ~5 ALU | Scale the `SATURATION` gain down for warm hues and with lightness (Hunt and Bezold–Brücke), so equal knob values give equal perceived boosts. |
| E. Warm/cool chroma rebalance | small | Counter the measured +5% warm / −12% blue tilt. Needs matched source comparisons first, per the evidence rule. |

Recommended order: A now, then B as a quick test, then C if warmth still reads as
"orange paint" rather than "warm light".

Limits: literature only. The screenshots were cropped and unmatched (the menu
news panel differs), and nothing was captured or rendered here.

## Follow-up: option C rejected, attribution measured

The user approved the recommendation, so C was prototyped on the CPU first
(scratch `vk.py`), calibrated so neutral pixels get the current shift exactly.
It would *raise* warmth on saturated warm surfaces. The existing `neutral_share`
gate gives saturated orange, yellow and red about +.0004 Oklab b at GZW mid
warmth 1.75×, while the illuminant shift gives about +.0038. Gray and skin
change little. So C was not built: warmth is not what drives saturated warm
chroma.

**Attribution captures.** Files are in `captures/warm_attr_20261109/`
(`run.sh`, `analyze.py`, `report.json`). The run used:
- GZW production ×2 and eight knob-off variants;
- three sources: the user's shader-off splash (053756) and menu (053827)
  screenshots, and reference 133058;
- 30 private headless captures, 0 errors, identities stable, production repeats
  within 0.1%.

The masks are source C > .03 and L > .2, banded by source hue. Each contribution
is production minus knob-off chroma, as a percentage of source chroma.

| Band (scenes) | Prod/src | Chroma stage | of which `SATURATION` | Warmth 1.75× | Inverse chroma | Print | Corrective gate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| red (splash, menu) | 1.16–1.29 | 15–16 | 9.3–9.5 | 2–4 | 3–9 | 0–1 | −6 to +2 |
| orange (3) | 1.03–1.23 | 4–16 | 3–9 | 1.5–9.5 | 1–2 | −1 to +6 | −3 to +8 |
| amber (3) | 1.14–1.18 | 13–16 | 8–10 | 6–8 | 1–2 | 0–4 | +3 to +6 |
| yellow (3) | 1.12–1.20 | 13–18 | 9–10 | 4–9 | 2–3 | 1–2 | −5 to +7 |
| green (3) | 1.09–1.16 | 12–16 | 9–12 | 3–6 | 3–5 | −3 to +2 | −4 to +4 |
| blue (menu, 133058) | .94–1.03 | 11–14 | 4–8 | −2 to −8 | −1 to +1 | −4 to −7 | 0 to −10 |

Findings:
- **The chroma stage is the largest contributor in every warm band.** It adds
  13–18%: `SATURATION` .075 gives about 9–10%, and the adaptive (median-C) lift the
  remaining 4–7%. Both are hue-uniform.
- **Warmth adds 2–10%.** It is largest in amber/orange/yellow at moderate chroma,
  and it removes 2–8% from blues. This is the warm-over-cool tilt.
- **Print and the corrective gate** also shift chroma from blue toward warm in
  daylight (133058).
- Because hues are perceived unequally (findings 1–3), a hue-uniform chroma boost
  reads as "too much red/yellow".

Revised options: lower `SATURATION`, or make the chroma stage hue-weighted (B,
extended to orange/amber), which trims warm bands while keeping cool and green
boosts.
