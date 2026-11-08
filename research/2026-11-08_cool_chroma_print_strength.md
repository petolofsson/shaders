# Cool-hue chroma, print strength and warmth (2026-11-08)

## Question

The [yellow/orange re-test](2026-11-08_hk_chroma_retest.md) found a warm-over-cool
chroma tilt:
- warm hues gain about 5% chroma;
- blue loses about 12%, cyan and magenta about 7%, green about 4%.

The user asked for a visual check. In the source/production crops the user
preferred production, then judged print possibly too strong. The user chose
`PRINT_STOCK` 0.5 in both profiles.

Scripts, stills and galleries are in `captures/cool_chroma_20261108/`. Galleries:
- `review.html`: crops with a chroma-ratio map;
- `review2.html`: all variants;
- `review_print.html`: print 0 / .25 / .5 / .75 / 1.0.

All runs used private headless `compare_frame` with current production grade and
pipeline. Variants are profile copies changing one knob. Every run logged 0 errors,
and identities were stable before and after. Production repeats differ by ≤2 codes,
with band medians within .002.

## Attribution

Each bypass is a single-stage switch-off. Bypasses overlap, so their shares are
not additive. The table shows the cool-band chroma ratio, out/src.

| Scene | Production | Print off | Warmth off | Corrective off | Inverse chroma off |
| --- | ---: | ---: | ---: | ---: | ---: |
| GZW 133058 cyan/blue | .799 | .981 | .887 | .885 | .799 |
| GZW 101035 sky | .867 | .956 | .913 | .931 | .867 |
| GZW 133750 green | .929 | .971 | .926 | .938 | .928 |
| Arc 205938 cyan/blue | .904 | 1.020 | .939 | .953 | .903 |

- Print stock is the main cause. It removes about 70–100% of the cool loss and
  also causes most of the .03–.045 Oklab darkening.
- Warmth and corrective each account for about 30–50%.
- Inverse chroma has no effect.

## Print strength

The response is close to linear. Each .25 of `PRINT_STOCK` changes lightness by
about .008 Oklab and cool chroma by 2–5%, while warm chroma barely moves. Example
for GZW 133058, cyan/blue:

| Setting | Chroma ratio | ΔL |
| --- | ---: | ---: |
| Print 0 | .981 | +.032 |
| Print .25 | .923 | +.025 |
| Print .5 | .898 | +.016 |
| Print .75 | .855 | +.008 |
| Print 1.0 | .799 | −.001 |

`PRINT_STOCK` is a ceiling clamped to 1. The shader applies 70–100% of it
automatically (`print_auto`).

## Warmth

`MID_TEMP` / `HIGHLIGHT_TEMP` were tested at 50%, 150% and off. The user saw no
difference, and that matches the arithmetic. `Apply3WayCC` shifts Oklab b by
`temp × 0.06 × zone weight × neutral_share`. At .05/.10 that is at most
.003/.006, below the approximately .02 visibility threshold, and smaller still on
chromatic pixels. Warmth 150% vs 50% moves mean output by about +.3 R and −.8 B
codes (max 5). The knobs work but are subtle by construction. Values around ≥.3
would be needed for a visible change. The follow-up below raised them.

### Stronger warmth (2026-11-09)

On the print-0.5 profiles, ×3 and ×6 were captured. For GZW these are mid/highlight
temp .15/.30 and .30/.60; for Arc, .15/.15 and .30/.30. Gallery:
`review_warm.html`. Mean shift vs print-0.5 production:

| Variant | Mean R | Mean B | Max (GZW) | Max (Arc) |
| --- | ---: | ---: | ---: | ---: |
| ×3 | +.2–.7 codes | −.9–1.7 codes | 9 | 5 |
| ×6 | +.6–1.5 codes | −2.2–4.3 codes | 23 | 11 |

At ×6 the clouds, concrete and paving are visibly warmer. The user chose between
×3 and ×4, and ×3.5 was set. For GZW this is .175/.35; for Arc, .175/.175. The
exact ×3.5 value was not captured. It lies between captured settings, and the
operation is linear in the knob.

## Tint strength

At `SHADOW_SURROUND_TINT` 1.5, foliage green chroma rises (133058: ×.938→×.988).
Brightness and other bands do not change. Tint 1.25 and 1.5 stills are in
`review2.html`. Neither was adopted, and neither has been noise-validated.

## Decision

The user set `PRINT_STOCK` 0.5 in both profiles. At that point both
`creative_values.fx` files were byte-identical to their captured `print50` copies.
Warmth was then set to ×3.5, as described above. No shader change.

Limits: six stills, a single frame each, and no motion. Each setting value has one
repeat. The production repeats bound capture variation.
