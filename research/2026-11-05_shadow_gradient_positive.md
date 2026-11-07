# Positive shadow-gradient candidate — 2026-11-05

**Decision: not adopted.** The user asked to improve the previous candidate. This version preserves the selected shelf and increases selected dark-metal separation, but loses separation in cool materials and the vivid blue-field control. The gains and costs warrant recording; they do not demonstrate a safe, broadly improved shadow gradient. No production shader, profile, config or score changed.

The isolated candidate replaces the previous signed S-shaped term with a positive response `anchor * x * (1-x)^2`, where `anchor=clamp(zone_key,0.04,0.12)` and `x=saturate(new_luma/anchor)`. It retains the source-Y shadow window `smoothstep(0.004,0.020,Y) * (1-smoothstep(0.080,0.150,Y))`, existing contrast/zone/cut gates and original tonal reconstruction. The window and source signal come from the [preceding refinement](2026-11-05_shadow_gradient_refinement.md); source guide Y floors at 0.001. This can lift eligible shadows, so it is not a zero-brightness redistribution, even though the deepest source values and values above the upper window fade remain unchanged by the added term. It is not an auto-exposure system.

| Source-selected region | Measure | Current | Previous refinement | Positive candidate |
|---|---|---:|---:|---:|
| GZW shelf | median L | 15.735 | 15.735 | 15.735 |
| GZW shelf | visible L gap | 2.661 | 2.657 | 2.669 |
| Arc dark metal | visible L gap | 8.981 | 8.320 | 10.830 |
| Arc dark metal | relative log-Y gap, stops | 1.949 | 1.821 | 2.268 |
| Arc cool upper | visible L gap | 20.385 | 19.650 | 18.972 |
| Arc cool window | visible L gap | 31.973 | 32.550 | 30.677 |
| GZW-profile vivid blue sky | visible L gap | 10.567 | 10.590 | 10.549 |
| GZW-profile vivid blue field | visible L gap | 27.390 | 30.175 | 24.249 |

These source-quartile measures are not quality scores; selected dark-metal gap rises about 20.6%, while cool-upper and blue-field gaps fall about 6.9% and 11.5%. Fixed-source neighboring-pair mean signed output gaps at 1/4/16-pixel offsets on Arc metal rise 0.113594/0.136975/0.156600→0.127985/0.157620/0.178506 stops. GZW shelf results change only slightly. Native crops do not establish a clear overall improvement, and no user visual judgment was collected. Brightness, lighting and hue tradeoffs remain; a larger gap is not automatically preferable.

Current-profile isolated candidate/repeat pairs cover GZW dark, Arc interior, Arc emitter and Arc vivid content under GZW settings. All four are pixel-identical after masking the marker; eight fresh private headless processes report zero dropped/delayed frames. Source/profile/config/grade files remained unchanged; isolated config/grade file hashes match their capture records. Current baselines and previous candidates retain their recorded profile and source epochs. The all-channel black count adds zero pixels in each pair, but this is not a near-black gradation contract. Full-frame maximum per-channel differences are 7/12/10/18 codes respectively. The 20-second static settle does not establish motion stability or convergence at all times.

A CPU scalar check assuming source Y equals corrected Y and fixed anchors 0.04/0.08/0.12 finds minimum numerical slopes about 0.667/0.667/0.635; the clamp prevents the larger-anchor scalar case from being used. This is not a monotonicity proof for the real adaptive color pipeline. No GPU numeric/zero-bypass contracts, near-black or gradient charts, motion/cut controls or actual-config adoption checks were performed. Native comparison crops, shader copies, scripts and capture identities are local ignored artifacts in `captures/shadow_gradient_positive_20261105/`. Further strength search is not automatically justified by these measurements.
