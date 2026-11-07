# Compact tone: held warm-material decision

**Reject the fixed compact curve for production.** The additional warm interior gives mixed material response: selected dark pack detail improves, while neighboring warm timber brightens and loses shade separation. Native crops show a slightly lighter, flatter timber response rather than a consistent gain in dimension. The earlier shelf/metal benefits remain valid in their selected scenes, but do not justify this scene-fitted global curve. No strength or knot sweep follows. Profiles, production shaders, configs and ratings remain unchanged.

## Independent scene and captures

The scene is `gamespecific/gzw/analysis/reference/autof_20260515_133444.png`, not one of the two scenes used to fit the curve. Source SHA-256 is `ee2f38defaf0823fbe0c5bbf379d4a05b3bc8c8264ee97e0c569b412981203a5`. It contains dark brown timber and a warm pack in shadow. These are warm dark materials; they do not establish deep red-black coverage or a second game's acceptance.

Four fresh private headless processes compare current/current repeat and candidate/candidate repeat with 20-second settling. The insertion is exactly the one recorded in the [original compact screen](2026-11-06_compact_tone_gpu_screen.md); no refitting was performed. Initial production/profile/config hashes match that screen and remain unchanged afterward. Isolated configurations start from verified current production copies. Captured image and snapshot-file hashes are checked by the analysis script. All four processes report zero dropped/delayed frames.

With the intentional 2×2 marker masked, candidate repeats are exact. Current repeats differ in 675 pixels by at most one code. Candidate versus first current reaches five codes over the frame; 2,996,611 pixels differ and no new all-channel black pixels appear. Counts describe changes, not quality or endpoint safety. The current-repeat variation is retained rather than called exact.

Artifacts, hashes, runtime log paths, native source/current/candidate crops and scripts are under `captures/shadow_compact_held_20261106/`, especially `report.json` and `analysis.json`. Captures are separately settled 8-bit screenshots, not same-update floating-point or temporal readbacks. Source-selected measurements use the original PNG, not a fresh source-only playback transfer check.

## Material response

Use fixed rectangles and source Oklab a,b >0.4, on the ×100 scale. Split source lightness into 12–20 and 20–35. Four-pixel neighbor pairs use the existing source-selected small luminance/color-boundary exclusions; pairs overlap and are not independent observations. Source ordering is descriptive, not an absolute fidelity target.

| Selection and source L | Samples | Median output L current → candidate | Mean signed neighbor log-Y gap current → candidate |
| --- | ---: | ---: | ---: |
| Rear timber, 12–20 | 64,128 | 18.946 → 20.000 | 0.12380 → 0.12806 |
| Rear timber, 20–35 | 42,579 | 22.455 → 23.151 | 0.14538 → 0.12320 |
| Lower timber, 12–20 | 60,947 | 18.829 → 19.905 | 0.13617 → 0.13337 |
| Lower timber, 20–35 | 30,085 | 22.617 → 23.308 | 0.18787 → 0.15862 |
| Warm pack, 12–20 | 9,759 | 17.194 → 17.688 | 0.13051 → 0.17277 |

The 20–35 timber bands lose about 15.3% and 15.6% mean signed gap. Their source-relative reversal rates rise 4.51%→4.61% and 3.11%→3.46%; the pack's dark-band rate falls 5.69%→3.54%. The pack's higher band has only six selected pairs and is excluded from substantive conclusions. Quantization and the baseline repeat bound small effects; these metrics do not prove continuous shader ordering or perceptual thresholds.

The native timber crop visibly shifts toward a brighter, somewhat flatter appearance, while the pack change is subtle. This is an agent visual review, not blind/user or gameplay acceptance. The original shelf/metal changes also remain subtle in the reviewed native crops. Together with previously documented cool-material, foliage, ramp/noise and fitted-black-reference limitations, the held tradeoff does not support continued validation for adoption of this particular curve.

The missing compiled numerical, black-context, gamut and measured motion controls remain unperformed; rejection does not require claiming they pass or that this curve is technically defective. No actual-config candidate activation occurred. The broader shadow goal remains open: another design needs a specific mechanism for preserving useful material shading and subtle color without redistributing the loss onto nearby tones. Do not reopen the rejected global curve with a parameter sweep.
