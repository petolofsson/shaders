# Next shared-code candidate — 2026-11-03

**Closed after the user authorized the experiment:** the residual prototype is
[rejected for adoption](2026-11-03_inverse_transport_decision.md). Numerical
precision improves, but selected full-frame appearance does not justify the
additional surface. The proposal below preserves the original selection rationale.

**Recommendation: preserve the inverse reconstruction's sub-code color changes
through to grade using a floating-point reconstruction residual.** Start with
the GZW-profile vivid case, where colored midtones are a more plausible source
of useful inverse activity than near-neutral shadows; retain Arc interior as a
cross-profile control. The vivid image is Arc content processed by GZW settings,
not a third game. Both existing profiles remain assessment inputs.

This is a source-grounded candidate, not an implemented enhancement, confirmed
visual defect, new score or mandatory repair. No production shader, profile,
config, header or runtime state was changed during this selection. Current
production remains commit `738a6f6`, with chain/grade estimated at 78.

## Concrete opportunity

In the combined technique, `pass InverseGrade` has no explicit render target
(`general/pipeline/pipeline.fx:102`), so it writes the UNORM BackBuffer.
`InverseGradePS` returns encoded, bounded SDR RGB after its existing chroma
reconstruction and gamut projection. `ColorTransformPS` then samples that
BackBuffer and explicitly decodes it (`general/grade/grade.fx:846`). The inverse
calculation can produce values between code levels, which are rounded at this
handoff before the later tonal, chroma and print stages consume them.

Combining the effects repaired resource sharing; it did not itself remove this
BackBuffer boundary. Most SDR games commonly use eight-bit output, whereas
existing private mpv validation uses ten-bit UNORM. Neither represents an
unquantized inverse result.

Consumer inspection narrows the scope: corrective zone/chroma/slow-key analysis
uses the original-scene texture highway, not inverse-graded BackBuffer data
(`general/corrective/corrective.fx:137,254`). The active combined technique does
not call corrective's standalone BackBuffer passthrough. The ordinary downstream
color consumer to redirect is grade's color-transform input. Native guide,
guided-filter inputs and analysis/history producers should remain untouched.

## Proposed representation

Keep the original BackBuffer intact until final grade output. In the existing
inverse pass, write an explicit RGBA16F texture containing:

```text
residual = inverse_encoded_RGB - source_encoded_RGB
```

Grade reconstructs `saturate(source_encoded_RGB + residual)`, then uses its
existing explicit sRGB decode and color processing. These are encoded-channel
transport values; the existing color algorithms still operate in their original
linear/perceptual domains. Keep the inverse's current SDR projection/ceiling.
No overrange reconstruction, wider gamut or HDR output is introduced.

A residual is preferable to storing absolute RGB in FP16 for this first design:
small corrections receive finer absolute precision, and an exactly zero
correction preserves the original source value instead of rounding the whole
source into half float. The source alpha should remain the original alpha.
Do not claim every currently inactive inverse pixel has a bit-exact zero
residual: existing color-space roundoff can leave small values. Runtime bypass
and endpoint contracts still need verification.

Factor the inverse color calculation and grade color body into shared helpers
with explicit input values, keeping their ordinary standalone entry points.
The combined technique supplies the residual writer and reconstructed grade
input. Avoid duplicate artistic formulas and algorithmic preprocessor forks.
The existing inverse pass changes target; no new full-resolution pass is
inherently required. Existing grade remains eight passes. All required surfaces
must remain inside the same combined effect; no cross-effect sharing is assumed.

This first candidate preserves the existing encoded sampling semantics rather
than also changing interpolation domains. A later linear-working-surface design
would be a separate decision, only if this smaller transport change establishes
useful benefit. It is not a prerequisite or automatic follow-up.

## Independent precision bound

A CPU quantizer calculation covers 524,544 supplied encoded-channel contexts:
source levels `0..255/255`, with bounded corrections spanning -0.02 to +0.02.
These are synthetic transport contexts, not an inverse model or observed game
output distribution. Errors below are measured before downstream processing,
in units of one eight-bit channel code.

| Representation | Maximum error | RMS error |
|---|---:|---:|
| UNORM8 | 0.499805 | 0.284202 |
| UNORM10 | 0.124633 | 0.071529 |
| Absolute FP16 | 0.062207 | 0.027021 |
| Source plus FP16 residual | 0.001868 | 0.000640 |

Zero residual preserves the supplied source exactly in the CPU model. This does
not establish compiled GPU identity, better final appearance, or an equivalent
error ratio for larger corrections. The ten-bit quantizer row is not a claim
that a real ten-bit source's zero-effect bypass changes its existing code value.
Local model/artifacts: `captures/transport_candidate_20261103/` (ignored).

## Why prioritize this candidate

It targets a concrete information-loss boundary while preserving current color
intent, source confidence, curves, profiles and automation. It can help retain
reconstructed colored-material distinctions and gradients that later processing
may otherwise amplify or redistribute after rounding. It does not add missing
information to the original eight-bit source. Near-neutral pixels with no
meaningful inverse correction may receive little benefit; broad weak-shadow
color recovery must not be promised from this candidate.

The surface payload is about 28.125 MiB at 2560×1440 for RGBA16F, before backend
copies or allocation overhead. Extra image traffic and a source/residual read
are real costs. GPU profiling remains deferred; no frame-rate or memory-budget
acceptance is claimed. These costs could outweigh a small visible gain.

A chroma-confidence redesign across inverse/grade/print is a broader second lead,
but it depends more on uncertain reconstruction intent. Ambient shadow tint's
use of unweighted local color is another source-inspection question, without
current attribution of a significant loss. Neither is queued as a parameter
search. The rejected grade chroma-budget, print toe, scalar-gain and lift
classifier screens remain closed.

## Smallest useful next step

First read back the actual pre-UNORM inverse result and its stored BackBuffer
result at the same GPU update, including an explicit eight-bit diagnostic path
and the existing ten-bit path. Establish whether meaningful inverse activity
loses material/color distinctions in the chosen current-profile cases. Ordinary
screenshots cannot supply that pre-boundary observation.

Only if that identifies useful headroom should the residual transport be built
as an isolated prototype. Its numerical contract should compare reconstructed
input with the intended inverse result, retain original-source analysis and
history semantics, and check inverse-zero/grade bypasses and black/white bounds.
A small matched source/current/prototype/repeat comparison then decides whether
appearance benefit justifies the additional surface. Preserve all existing
artistic functions and strengths. Expand validation for adoption only after a
useful improvement is demonstrated; stop if precision gains do not produce
worthwhile final-image benefit.

All runtime work stays private/headless and requires the appropriate escalation.
No GPU run, shader prototype, parameter sweep, commit or push was started for
this candidate selection.
