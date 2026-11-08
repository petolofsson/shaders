# Gradient-classification Retinex screen

Follow-up to the [brightness oracle](2026-11-08_brightness_oracle.md), which found
that production's tonal base attributes light like a global curve. This screen
tests the classic single-image light/material separation: classify each
log-luminance edge as material or light, drop material edges, reintegrate the
rest (Neumann Poisson solve) and evaluate the same tonal curve on the result.
[`tools/retinex_screen.py`](../tools/retinex_screen.py), CPU only. Frames come
from the oracle renders via a cache (`captures/brightness_frames_cache/`); a
full-resolution cached rerun reproduced every earlier oracle PNG byte for byte.
Review: `captures/retinex_screen_20261108/review.html`.

Methods: Land & McCann's magnitude rule at .25/.5/1 stop per pixel (after a 3×3
box on log luminance), Funt–Drew–Brockington-style chromaticity rule (sum of
|Δlog R/G| + |Δlog B/G| < .15), and both combined. The Poisson solver recovers a
smooth test field to 2e-14. Estimates are offset to the pixel log-luminance
median. A **uniform** control applies the oracle's median surface gain
everywhere.

## Results (gain error vs oracle, stops)

`all` = mean over surface pixels; `balanced` = mean of per-region errors over
the five light/material regions, so a dominant region cannot hide failures.

| Variant | Daylight all | Daylight balanced | Interior all | Interior balanced |
| --- | ---: | ---: | ---: | ---: |
| global | .212 | .316 | .181 | .312 |
| production base | .212 | .316 | .181 | .313 |
| magnitude .25 | .209 | .344 | .035 | .340 |
| magnitude .5 | .216 | .381 | .043 | .342 |
| magnitude 1 | .255 | .439 | .126 | .409 |
| chromaticity .15 | .229 | **.252** | .034 | **.299** |
| magnitude .5 + chroma | .217 | .362 | .036 | .346 |
| uniform control | .288 | .405 | .044 | .351 |

## Interpretation

The interior's apparently large gain (all-pixel error .035 vs .181) is matched by
the uniform control (.044): the room is mostly partial shade, and Retinex simply
returns a nearly flat light estimate. It lifts lit bright and lit dark areas by
about +.6 stop where the oracle lifts nothing. Under the balanced metric, every
magnitude variant is worse than production in both scenes.

In daylight, cast-shadow and occlusion edges are as sharp as material edges, so
the magnitude rule removes them; the reintegrated light loses the shadow and the
sunlit side is lifted (+.43 on lit bright). Bluish skylight makes shadow edges
change chromaticity too, so the chromaticity rule also discards many of them.
It is the only variant below production on the balanced metric (.252/.299 vs
.316/.313), a modest improvement that still lifts lit areas and leaves deep
occlusion nearly unchanged.

No tested classical rule closes the attribution gap; the screen supplies no
shader candidate. Two observations bound the practical cost: production's own
lift only adds (no deepen band), so the oracle curve's crushing of shadowed dark
materials does not apply to production; production's remaining cost is mainly
lifting large dark materials in light. Limits: two synthetic scenes, a single
threshold family, no learned or multi-frame method, no production chain.
