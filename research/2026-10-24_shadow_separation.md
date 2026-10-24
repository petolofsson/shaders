# Shadow separation — first resumed pass, 2026-10-24

Genuine GZW dark gameplay `autof_20260515_133058.png` was replayed through
`gzw_stronger_trial.conf`. Fresh processes, continuous lossless RGB playback,
5-second compile delay and 20-second settle were used for full, unchanged full,
and individual contrast, Retinex, zone-contrast and shadow-lift bypasses.
The [first report](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_141123.json)
retains the captures and records one rejected effect; **its SHADOW_LIFT result
is invalid**, because other desktop windows obscured the image. The red marker
was still visible. Do not use that 10.11 ΔE result as shader evidence.

## Valid first-run observations

All percentages below exclude the intentional top-left 2×2 marker. Exact black
means all RGB codes equal zero; near black means max(R,G,B) < 5 in 8-bit PNGs.
These are endpoint/separation diagnostics, not fidelity scores.

| Output | Exact black % | Near black % | Bypass ΔE vs full |
|---|---:|---:|---:|
| Source | 0.00000 | 0.83380 | — |
| Full | 0.02984 | 2.87248 | — |
| Unchanged full repeat | 0.02981 | 2.88040 | 0.027 |
| Without CONTRAST | 0.00000 | 2.38089 | 0.11 |
| Without RETINEX | 0.02984 | 2.87248 | 0.00 |
| Without ZONE_CONTRAST | 0.00000 | 2.38802 | 0.12 |

`CONTRAST` scales the same local contrast path that
`ZONE_CONTRAST_STRENGTH` gates; they are not independent contrast stages.
Their small bypass difference is compatible with capture/history variation.
The negative contrast arm can reach the zero clamp, but these measurements
alone do not establish that the intended contrast operation is defective.

A source-selected mask with 4 < max(R,G,B) <= 64 contains 2,475,429 pixels.
None becomes exact black in full output; 3.038% becomes near black, compared
with 2.311% without contrast. Of 789,766 horizontal pairs inside that mask
whose source code-domain Rec.709 weighted gray differs by at least 2 codes,
0.0433% differs by less than half a code in full output (0.0385% without
contrast). This is a limited spatial-separation proxy; it does not measure
motion, perceived texture, or linear-light contrast. Visual inspection shows
darker shelf interiors, with the broad shelf geometry and wood texture retained.

## Existing Babylon night evidence

The earlier matched Firefox/Gamescope held pose at frame 1620 was also
measured, using its original baseline/trial/repeat PNGs rather than a new
mpv transfer path. Exact black stays 0.01313%; near black changes from
1.19521% to 1.19556%. Of 3,529,920 source-selected shadow pixels under the
same mask, none becomes exact black and 0.000397% becomes near black.
The baseline repeat is identical. This pose does not reproduce the broad
black growth seen in the cross-game Electric Dreams forest. Its mostly
flat surfaces provide limited evidence about dark textured detail.

Reproducible measurement script and full numerical outputs are retained under
ignored `captures/shadow_separation_20261024/` (`measure.py`, `gzw.json`,
`babylon_night.json`). Invoke `measure.py SOURCE.png OUTPUT.png ...`.

## Capture correction and scope

mpv launches now request `--ontop`, to prevent ordinary desktop windows from
covering fullscreen captures. This mitigates the observed failure; the marker
alone still cannot prove the entire desktop image is unobscured. Retained
images need inspection. The [fresh rerun](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_141401.json)
completed with unobscured captures and a pixel-identical full repeat. Shadow
lift contributes 2.35 ΔE, consistent with the previous audit. Without it,
near-black coverage rises to 4.93156% and exact black to 0.04034%, versus
2.87248% and 0.02984% in full output. Source-selected shadow pixels becoming
near black rise from 3.038% to 6.103%; eligible pairs losing separation rise
from 0.0433% to 0.2402%. Thus shadow lift helps separation in this scene;
these results do not support disabling it. Its rerun metrics are saved in
`captures/shadow_separation_20261024/gzw_shadow_lift_rerun.json`.

No shader logic or user tuning is changed. GZW config and trial hashes remain
`77b33ac8…` and `82d2b63e…`; restored tuning remains `ed371ec3…`.
The 12 diagnostic tests pass. The broader plan remains open: add a textured
low-light/ramp target if needed, assess purpose-specific regions, and save
matched moving Babylon output through foliage, emitters and both cuts.

Follow-up: the [contextual-ramp and sunset investigation](2026-10-24_contrast_shadow_toe.md)
subsequently demonstrated local-contrast shadow collapse and produced a
luminance-relative correction. The no-shader-change conclusion above describes
this initial pass, before that focused evidence was gathered.
