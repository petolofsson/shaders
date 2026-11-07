# Shadow-color audit: weak color versus exact gray

**Correction to an earlier interpretation:** the selected weakly colored source pixels had not acquired their color in inverse processing. On the existing 8×8 sampled selections, source-only and grade-input screenshots have identical RGB for every selected pixel. Their nonzero grade-input color was already present in the source screenshot. A new source-color transport surface or moving the correction into inverse is therefore not justified by that premise.

This corrects language in the earlier guard report/startup notes; their numeric observations remain unchanged. It does not prove arbitrary scenes, original floating-point input, noise-free color or perceptual acceptance of the candidate.

## Matched artifact audit

Use the same source-only playback captures, grade-input diagnostic screenshots, current full images and existing half-strength bounded-color stills. Their hashes are verified against the earlier reports. Samples are `[8::8,8::8]`, source Oklab C<0.5 and L 12–35, all on the ×100 scale. These are weak-color samples, not exact neutrals. Separate process captures and 8-bit quantization remain limitations; this audit adds no GPU run.

| Observation | GZW dark | Arc interior |
| --- | ---: | ---: |
| Weak-color samples | 5,744 | 5,138 |
| Source/input RGB equality | 100% | 100% |
| Source/input maximum RGB difference | 0 codes | 0 codes |
| Median source and input C | 0.362 | 0.352 |
| Median source and input relative RGB range | 0.114 | 0.156 |
| Half-candidate/current maximum change on these samples | 1 code | 1 code |
| Median source-ab distance, current → half candidate | 0.340 → 0.266 | 0.432 → 0.427 |

Distances compare absolute Oklab a/b across differently graded brightness levels; they are descriptive, not fidelity scores. A smaller source distance does not establish a preferred palette, especially where user-selected CC intentionally changes it. The mean candidate chromatic change dotted with source a/b is positive in both selections, consistent with strengthening some existing weak source color rather than inventing its direction. Arc median output C still grows 0.443→0.506, so an overly strong weak-color/tint impression remains a valid appearance concern.

An additional exact-gray selection requires equal source R=G=B at the same source-L range. It has 56 GZW and 109 Arc samples. Every source/input RGB pair matches, and every current/half-candidate output RGB pair matches exactly in these samples. Their current output is not necessarily gray because later configured grading can tint it; the candidate does not change those sampled outputs. This sparse screenshot result is not a general exact-gray GPU or temporal contract.

## Consequence

The earlier summary that a source-neutral safeguard failed because the selected pixels had acquired inverse-stage color was unsupported on this sample. The relative-RGB guard fails to engage because an absolute low-Oklab-C threshold can still select appreciable **relative** channel differences in dark colors. Suppressing those differences may suppress the requested nuance itself.

The existing half-color candidate stays provisional. This audit removes an incorrect attribution; it does not erase weak-color appearance shifts, quantized ordering costs, missing brightness benefit or held warm-material/motion coverage. The next useful measurement is baseline and candidate pre-dither output in the same GPU update, to separate continuous response from screenshot-order classification changes. That measurement is a diagnostic, not adoption authorization.

Code, hashes and full values: `captures/shadow_neutral_alignment_20261106/`. Production/profiles/configs/ratings remain unchanged.
