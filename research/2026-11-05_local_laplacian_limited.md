# Confidence-limited local-Laplacian reference — 2026-11-05

**Decision: do not adopt or port this version.** The user requested trying noise restraint and a gradient-order constraint on the [first local-Laplacian reference](2026-11-05_local_laplacian_reference.md). Both reduce selected risks, but the combined version retains only a small fraction of the first reference's selected local response and still adds some source-relative reversals after 8-bit quantization. No production shader, profile, config or rating changed.

## Method

The offline candidate starts with the same four-level sampled-anchor local-Laplacian log-luminance reference, source-luma shadow window and bounded gain as the first experiment. A per-pixel heuristic estimates a neutral sRGB one-code luminance increment from the current output; the local deviation from a 5-tap blurred log-Y image is smoothly gated from 1.25 to 2.5 such increments. This is a quantization-derived confidence heuristic, not a measured game noise floor. It can suppress real subtle shading along with noise and can itself introduce spatially varying behavior.

A separate iterative pair-order projection operates on the proposed *continuous log gain*. For horizontal/vertical 1-, 4- and 16-pixel pairs with source Y in [0.001,0.15) and absolute source log difference 0.02–0.5 stops, the allowed correction must not create a reversal against source order where none existed, or worsen an existing source-relative reversal. Thirty-six red/black coordinate sweeps project pairwise constraints, while each pixel is clipped to the interval between zero correction and its noise-gated proposed correction. This is a costly offline feasibility experiment, not a proven real-time vkBasalt implementation or a general gradient-order guarantee; constraints on other distances, missing information and inapplicable pairs remain. It operates on a 96-pixel-padded crop. RGB scaling, clipping and subsequent 8-bit quantization happen after the continuous projection and can reintroduce reversals.

## Material results

| Fixed source-selected region | 4-px signed log gap: current | First reference | Limited | New 4-px source-order reversals: first → limited |
|---|---:|---:|---:|---:|
| GZW shelf | 0.115959 | 0.117360 | 0.116170 | 7 → 1 |
| GZW blue wall | 0.075890 | 0.104403 | 0.080130 | 337 → 53 |
| Arc dark metal | 0.137007 | 0.150503 | 0.139680 | 550 → 78 |
| Arc cool window | 0.149966 | 0.177317 | 0.158920 | 399 → 83 |

The signed mean gaps use the previous source-selected material, L/chroma and pair masks. The new-reversal counts are a separate, broader defined audit: all source-Y-eligible pairs in the crop, source gap 0.02–0.5 stops, in both axes. Thus their populations differ from the signed-gap populations and pairs overlap. A new reversal is a pair not reversed in the original current image and reversed in the quantized candidate. Counts are not independent events or quality scores. Larger local gaps do not by themselves establish better-looking material.

For source-quartile L gaps, current/first/limited are 2.661/2.675/2.663 shelf, 9.468/9.666/9.491 wall, 8.973/9.034/8.995 metal, and 31.972/32.003/32.001 window. The limited reference retains about 15% of the first reference's selected wall 4-px gap increase and about 20% of its metal increase, while removing many but not all added reversals. The visible crops show no clear overall improvement. No blind or user visual assessment was performed.

A separate constraint audit on 4-pixel pairs found 0/0/2/2 residual continuous violations (>1e-6 stops) in shelf/wall/metal/window after 36 sweeps, with maxima <=0.000124 stops. After 8-bit quantization these become 1/53/81/88 violations, including 1/53/78/83 new reversals. This is evidence of incomplete convergence and quantization effects, not a mathematically complete ordering guarantee. No GPU readback is involved. Full tables, fixed-source selections, code and native comparisons are in `captures/local_laplacian_limited_20261105/`.

## Synthetic controls

The synthetic constant-black and 0–64-code neutral ramp are pixel-identical to input in this reference; the 16/96-code hard step is also pixel-identical after 8-bit quantization. These are limited fixtures, not a general edge, near-black or monotonicity proof. The first full-reference test of black had a divide-by-zero; that earlier failure and its corrected rerun are preserved in the preceding reference report.

On the identical synthetic code-16 ±1-code noise patch, continuous code-equivalent noise standard deviation changes by a factor 1.00013 with limiting versus 1.27881 for the first reference; both quantize back to the input in that fixture. On ±3-code synthetic noise it changes by 1.09973 versus 1.14587, and 6,887 pixels change by one code after limiting. These are arbitrary independent-noise fixtures, not a calibrated model of dither, texture or real game noise.

A one-pixel translation phase proxy changes 1,059/262,144 pixels in the GZW crop and 2,251/262,144 in the Arc crop, all by at most one code, compared with 1,793 and 5,631 for the first reference. A 16-pixel translation matches in these examples. These tests translate the entire still image and source together with a 64-pixel excluded boundary. They are not update-aligned moving gameplay, temporal stability or a phase-stabilized solution. No phase-averaging implementation was added because the first-stage limited model did not retain a clear material benefit.

## Limits and next decision

The source-only and current-output PNGs are separately captured 8-bit images; source transfer, quantization, UI and dither limitations from the first reference remain. The reference works only on padded selected crops; there is no full-frame GPU implementation, zero-effect GPU contract, color/gamut proof, real motion/cut test, performance measurement or active-config validation. No claim of eliminated noise, halos, flicker or reversals is made. Given the mixed response and implementation cost, this finite refinement does not justify porting to the active shader or an automatic parameter sweep. More representative captures or a genuinely different model would be needed to support a new decision.
