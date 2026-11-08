# Shadow-tint cue maps vs the brightness oracle

This was queued after the [shadow surround tint](2026-11-08_shadow_tint_candidate.md)
review, with the user's approval. Question: does the adopted tint's
relative-darkness shadow weight separate shaded surfaces from lit dark materials
better than plain pixel darkness? If so, it would be a new light/material signal
for the closed brightness-recovery work. CPU only.

Script and outputs: `captures/cue_map_oracle_20261108/` (`score.py`, `report.json`,
maps). The frames are the cached [brightness oracle](2026-11-08_brightness_oracle.md)
renders (1280×720, upscaled 2× nearest so the low-resolution fields keep their
game-resolution footprint). They are scored with the candidate's `reference.py`
weights (same formulas as production). Oracle regions come from exact
illumination: shaded = partial bright, partial dark material, deep occlusion;
lit = lit bright, lit dark material.

## Results

Mean weight per region:

| Region | Daylight | Interior |
| --- | ---: | ---: |
| lit dark material | .31 | .0002 |
| partial bright | .10 | .06 |
| partial dark material | .39 | .07 |
| deep occlusion | .19 | — |
| lit bright | .01 | .00001 |

ROC AUC (higher means the cue ranks shade above light):

| Comparison | Daylight tint w | Daylight darkness | Interior tint w | Interior darkness |
| --- | ---: | ---: | ---: | ---: |
| shaded vs lit | .51 | .54 | .77 | 1.00 |
| shaded bright vs lit dark material | .35 | .08 | .77 | 1.00 |

## Interpretation

In daylight the weight fires about as often on lit dark materials as on shaded
dark materials, and it separates shade from light at chance level. On the hard
case (shaded bright vs lit dark material) it is less wrong than pixel darkness
(.35 vs .08) but still below chance. In the interior, where darkness alone
separates the oracle regions almost perfectly, the relative weight is worse
because it stays near zero across the broadly dim room.

The cue maps supply no light/material signal. Brightness recovery stays closed.
For the adopted tint, this quantifies a known cost: lit dark materials beside
brighter surfaces can be tinted. The emitter map was not scored (the oracle
scenes have no emitters). Limits: two synthetic scenes, one parameter set.
