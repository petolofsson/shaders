# Offline shadow gradient graph screen

## Decision

Do not implement this candidate. A regularized source-gradient reconstruction can recover a little local separation, but the tested restrained version produces changes that are difficult to see in the native comparisons, while still responding to synthetic source noise. The safeguard that reduces that response also leaves an affine shadow ramp completely unchanged. This is a limited offline screen, not evidence that gradient-domain approaches cannot work or that the active shader has a new defect.

## Method

The experiment works on the same separately captured, 8-bit source-only and full-chain images used in the [multiscale screen](2026-11-05_shadow_multiscale_measurement.md). It solves a regularized least-squares graph on padded native crops, with horizontal and vertical differences at one and four pixels. Where the output's signed log-luminance difference is smaller than the source's, the target requests some of the missing separation. Weights attenuate near-black and brighter source pixels, differences near an estimated one-code noise floor, strong edges and color boundaries. A bounded log-gain is applied to the current linear RGB, followed by output encoding and quantization. This is an offline reference, not a practical shader implementation or a mathematically guaranteed ordering constraint; the final bounded gain is applied after the solve.

The initial graph reference and a variant with a local directional-coherence weight were screened. The latter suppresses inconsistent neighboring gradient directions, which can include both noise and legitimate texture. Parameters were exploratory, not calibrated across games. Reports, scripts, crops and native comparison images are in `captures/shadow_graph_20261106/`; the coherent results are in its `coherent/` subdirectory. The full-chain images and source images used here match their recorded hashes, and all 17 shader, include, profile and configuration hashes in the source-capture record match the current workspace. These checks do not turn the two separately captured 8-bit images into the shader's exact internal source and output signals.

## Results

For selected source-signed four-pixel neighbor pairs, the mean output gap in stops changed as follows. These overlapping pair measurements describe the chosen regions; they are not independent samples or a universal quality score.

| Region | Current | Coherent graph |
| --- | ---: | ---: |
| GZW dark shelf | 0.115959 | 0.116046 |
| GZW blue wall | 0.075890 | 0.079933 |
| Arc dark metal | 0.137007 | 0.139618 |
| Arc cool window | 0.149966 | 0.155188 |

Maximum changes were one 8-bit code on the shelf and two codes in each other crop. The blue-wall comparison shows a subtle change, not a clear improvement at native size. Four-pixel source-relative reversal rates fell on the blue wall (2.626% to 2.425%) but rose on the cool window (1.984% to 2.222%); quantization and independent capture can affect these counts. Source differences are not an unquestionable target for the game's intended graded appearance.

Synthetic 128×512 tests used a flat code-16 current image and independently varied the source around code 16. With random ±1-code source variation, the initial graph changed 7,921 pixels by at most one code; coherence reduced this to 213 pixels. With ±3-code variation, it changed 30,830 pixels by at most two codes without coherence and 5,357 with coherence. These deliberately adverse fixtures are not measurements of actual game noise. The coherent version left its identity, flat-black, simple step, and affine-ramp fixtures unchanged; the ramp result is also a sensitivity limitation because the requested black-offset compression was not recovered. The step fixture had identical source and output, so it does not establish halo protection for a nontrivial correction.

The crop solves reported relative iterative residuals below 0.0001 before the final bounded gain. This is a numerical stopping measure, not a visual or order-preservation guarantee. No GPU implementation, full-frame comparison, actual motion test, or performance measurement was performed. The offline solver's many iterations and global coupling would require a materially different real-time approximation, with its own boundary and temporal validation.
