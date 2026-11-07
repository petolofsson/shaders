# Local-Laplacian shadow reference — 2026-11-05

**Decision: promising local response, but not ready for a shader implementation or adoption.** This is an offline static research reference; it increases selected local shadow differences, while also amplifying a synthetic noise signal and increasing source-relative pair reversals in some regions. No production shader, profile, config or rating changed.

## Reference and scope

Following [Paris, Hasinoff and Kautz's local Laplacian formulation](https://people.csail.mit.edu/sparis/publi/2011/siggraph/), the offline reference builds a four-level, decimated, 5-tap Gaussian/Laplacian pyramid in log2 linear Y. For each output pyramid coefficient it uses an intensity-centered remapping, `r(i,g)=i+0.5*(i-g)*exp(-((i-g)/0.5)^2)`, then reconstructs the pyramid. This is the local-Laplacian algorithm with a smooth remapping function, not the paper's exact power-law parameterization. To make the reference tractable, it computes pyramids for 129 evenly spaced intensity anchors and interpolates between them; it is a sampled-anchor approximation, not an exact evaluation at every pixel.

Forty-eight exact per-coefficient calculations per region (12 random positions at each of four levels) bound the observed interpolation error to 0.00035–0.00052 stops on these samples, not all pixels. Repeating with 257 anchors reduces the observed sample maxima to 0.000083–0.000112 stops; compared with the 129-anchor reconstructed/quantized crop, differences reach one code in 19/636/323/182 pixels for shelf/blue wall/metal/window. Standard pyramid reconstruction without remapping agrees with the input log image within 1e-6 stops. The independently sampled checks are not an exhaustive quality or numerical proof.

The reference operates on 8-bit *current full-output* PNGs; it is an added detail manipulation of already-processed SDR, not recovery of HDR signal or direct preservation of hidden pre-quantization source detail. Source-only playback Y gates the correction smoothly from 0.001–0.008 and out from 0.08–0.15 linear Y. The remapped-minus-original log-Y correction is clamped to ±0.5 stops and applied as linear RGB gain to the current output, then clipped and quantized. This windowed, clipped, 8-bit procedure is not the exact full original paper and is not a proposed production implementation. It could amplify quantization, dither, UI, grain and texture. Four native source-fixed material rectangles were processed with 96-pixel contextual padding; no full-frame implementation or performance claim follows. Current baseline and source-only capture hashes are recorded in `captures/local_laplacian_20261105/report.json`.

## Measured static results

| Fixed source-selected region | Current L gap | Reference L gap | 4-px signed mean log-Y gap, current → reference | 4-px reversal fraction, current → reference |
|---|---:|---:|---:|---:|
| GZW shelf | 2.661 | 2.675 | 0.115959 → 0.117360 | 6.49% → 6.48% |
| GZW blue wall | 9.468 | 9.666 | 0.075890 → 0.104403 | 2.63% → 2.85% |
| Arc dark metal | 8.973 | 9.034 | 0.137007 → 0.150503 | 5.75% → 6.21% |
| Arc cool window | 31.972 | 32.003 | 0.149966 → 0.177317 | 1.98% → 3.19% |

L gaps use fixed source L quartiles; neighboring-pair measures are source-selected with 0.02–0.5-stop source differences and chroma/brightness masks from prior tooling. Reversals are output pair sign opposing source pair sign, not a direct count of artifacts or proof of degraded appearance; pairs overlap. Larger gap is not a quality score. The shelf barely changes; blue wall and selected metal/window local differences increase, but reversal fractions also rise. No blind or user visual judgment is claimed. Native crops and JSON are in `captures/local_laplacian_20261105/`.

In the selected rectangles maximum channel changes versus current are 3/4/3/5 8-bit codes for shelf/wall/metal/window. No newly all-channel-black or channel-255 samples were counted in those crops; this does not establish correct black or gamut behavior for all inputs. The 96-pixel contextual crop padding reduces but does not prove absence of crop-boundary effects at every scale.

## Synthetic boundaries, noise and motion proxy

A 0–64-code grayscale ramp retains 65 unique values and no reversed row-mean steps; a two-level 16/96-code hard edge remains pixel-identical after 8-bit quantization in this one fixture. These are limited examples, not a general no-banding or no-halo proof. Exact black returns exact black after the constant-input fix described below.

For a flat code-16 grayscale patch with independent ±1-code synthetic noise, quantized output equals input, but before final 8-bit quantization the code-equivalent standard deviation increases 0.815→1.042 (about 28%). For synthetic ±3-code noise it increases 2.004→2.297 (about 15%) before quantization; 8,236 of 65,536 output pixels change by one code. These arbitrary independent-noise fixtures are not a calibrated game-noise or dither model; they show a real risk that 8-bit output hides sub-code amplification.

As a limited spatial-phase proxy, the same 640×640 current/source crops were translated by integer pixels before filtering, and compared against the filtered unshifted result translated by the same amount, excluding a 64-pixel border. A one-pixel shift changes 1,793/262,144 GZW and 5,631/262,144 Arc pixels by up to one code; 16-pixel shifts match exactly in these examples. This measures decimated-pyramid phase sensitivity, not temporal filtering, measured update alignment, actual moving-gameplay flicker or stability. Real motion/cut tests remain unperformed.

The initial constant-black fixture exposed a zero anchor-range divide, yielding NaN before encoding. That failed diagnostic is preserved as `fixture_initial_failure.json`; the offline reference was corrected to return a constant input unchanged and all fixtures rerun. No production code was involved. Both shader-screen source and full captures predate this reference and have recorded source/profile/config identities and static repeats in `captures/shadow_multiscale_20261105/`; no fresh GPU, timing, user blind review, gradient-chart GPU readback, edge-mask sweep or actual-config activation was performed.

## Interpretation

The method may be worth investigating if the user values the visible material differences, but these results do not establish a clear overall visual gain and explicitly retain quantization/noise, sign-reversal and spatial-phase concerns. Adding a new effect or passes is not justified yet. A further decision would require a representative noise/motion source, user-visible comparisons, robust boundary and near-black charts, a decision on any extra processing budget, and an implementable GPU design; this report does not authorize or claim those steps.
