# Shadow-curve redistribution screen

The user asked to keep working toward a functioning combined solution. This screen tests two distinct ways of moving the brightness curve's compensating compression away from the darkest material. Neither is ready for a shader: the broad curve lifts and compresses selected cool materials substantially, while the bounded curve is less disruptive but still loses blue-wall and cool-window neighboring separation and retains the prior color candidate's ordering costs. No production shader, profile, config or rating changed.

## Models and context

Both reuse the [combined offline proxy](2026-11-06_combined_shadow_proxy.md): an already-quantized half-strength color-candidate screenshot, a separately captured grade-input screenshot as the zero-input gate, the shelf-fitted output-Y pivot 0.003864, and post-processing RGB scaling followed by 8-bit quantization. Thus neither represents a compiled full-chain candidate; gate ordering, source-black, neutral shifts, noise and motion remain unvalidated. Source/profile/config hashes and crop inputs are recorded in the two capture directories.

The **broad** version replaces the previous output-Y fade from 0.006–0.015 with 0.006–0.10. This moves the return to identity across more of the tone range but allows the correction itself to keep growing. The **bounded** version instead divides positive pivot distance by `1+distance/0.004` and fades the correction over output Y 0.02–0.20. It limits positive absolute luminance lift while distributing the return across a wider range. Both retain the original low-Y gate and 0.3 coefficient. These are two illustrative mechanisms, not a calibrated strength or threshold search.

On a million-step CPU scalar grid with gate fixed at one, all three curves (previous narrow, broad and bounded) have sampled derivative range about 0.5805–1.3000. The maximum positive output-Y corrections are 0.00114, 0.00773 and 0.00104 respectively. At Y=0.05 the corrections are 0, 0.00758 and 0.00102. These scalar figures do not include the changing grade-input gate, RGB gamut, final quantization, downstream shader interaction or a GPU contract.

## Selected results

| Source-selected region | Four-pixel signed log-Y gap: current / color / narrow / broad / bounded | Source-relative reversals: current / color / narrow / broad / bounded |
| --- | ---: | ---: |
| GZW shelf | 0.11596 / 0.11620 / 0.14240 / 0.14248 / 0.13715 | 6.49% / 9.07% / 9.07% / 9.07% / 9.07% |
| Arc dark metal | 0.13701 / 0.13685 / 0.14552 / 0.15547 / 0.14286 | 5.75% / 6.81% / 7.02% / 6.82% / 6.82% |
| GZW blue wall | 0.07589 / 0.07588 / 0.07529 / 0.06232 / 0.07075 | 2.63% / 2.77% / 2.80% / 3.11% / 3.05% |
| Arc cool window | 0.14997 / 0.15005 / 0.14625 / 0.13613 / 0.14721 | 1.98% / 2.12% / 2.39% / 2.45% / 2.14% |

The broad proxy raises the source-selected L 12–35 blue-wall median from 23.717 to 25.368 and cool-window median from 22.372 to 23.672. The bounded proxy gives 24.103 and 22.802, respectively; its shelf median remains 16.073 and metal median rises 17.559 to 18.065. These medians use a different selection from quartile gaps. The bounded shelf color-group distance is 0.423 versus 0.327 current; metal is 1.776 versus 1.575. Blue wall falls 0.092 → 0.067; cool window rises 1.970 → 2.093. As before, group distances and overlapping pair metrics are descriptive, not visibility or fidelity scores. The fixture is a doubly quantized screenshot proxy, not a direct real-time output.

The broad result shows why simply spreading a correction is insufficient: it significantly changes the level and response of materials outside the target. The bounded result preserves more of the selected cool-window response but still compresses blue-wall response and does not cure the shared black/ordering issues. There is no evidence here of a clear appearance gain across held scenes. Keep both as research results, not a strength sweep or automatic production direction. Full metrics and native crops are under `captures/shadow_broad_curve_20261106/` and `captures/shadow_bounded_curve_20261106/`.
