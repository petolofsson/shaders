# Yellow/orange over-saturation re-test (H-K chroma follow-up)

This was queued after the [shadow surround tint](2026-11-08_shadow_tint_candidate.md)
review, with the user's approval. The idea was to apply Helmholtz–Kohlrausch
compensation to chroma-adding stages for the testbed's old yellow/orange
over-saturation issue. That issue was recorded as likely resolved by
R130/R133/R138, to be re-tested before reopening. Per the repository rule, a
candidate needs a recurring visible loss first.

Script: `captures/hk_chroma_20261108/retest.py`; output `retest.json`. Data:
matched stills `production_0` (production without the tint, from the tint
candidate run; the tint affects only shade) vs the source references for seven
scenes (five GZW, two Arc). Pixels with source Oklab C > .03 and L > .25 are
banded by source hue. The figures are per-scene medians averaged over scenes.

| Band | Scenes | Pixels | Chroma out/src | L** − L* src → out |
| --- | ---: | ---: | ---: | ---: |
| red | 2 | 40 k | 1.047 | 5.76 → 6.02 |
| orange | 4 | 458 k | 1.057 | 4.05 → 4.35 |
| amber | 7 | 1.86 M | 1.052 | 3.03 → 3.35 |
| yellow | 7 | 2.47 M | 1.014 | 2.50 → 2.67 |
| green | 7 | 908 k | .959 | 4.82 → 4.75 |
| cyan | 2 | 7 k | .928 | 3.34 → 3.43 |
| blue | 5 | 1.10 M | .884 | 6.89 → 6.62 |
| magenta | 1 | 1 k | .930 | 4.01 → 3.77 |

Production adds about 5% chroma to red/orange/amber and about 1% to yellow, and
reduces cool hues. The added H-K brightening is about .2–.3 L*, below one
lightness step. There is no recurring over-saturation loss, so no H-K chroma
candidate follows. A mild warm-over-cool chroma tilt remains, as data only.

Limits: seven stills, Fairchild–Pirrotta as the only H-K model, and no visual
review of this specific question.
