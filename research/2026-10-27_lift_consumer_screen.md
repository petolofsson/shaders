# Current-observation lift-consumer screen — 2026-10-27

Follows the applied [direct gate recovery](2026-10-27_gate_recovery.md).
Using current source observations for the complete lift coefficient reduces
the measured night settling substantially while preserving the existing detector
and analysis histories. It also changes the incoming cut appearance markedly.
This is a diagnostic candidate screen; no additional production change is adopted.

## Consumer-local method

Four fresh private headless replays retain both profiles and unchanged repeats.
The verified post-gate shared run anchors source and shader hashes. The original
video packet prefix, 15-pose/sec source duplicated at 30 fps, five-second compile
wait and 20-second continuous pre-roll remain unchanged. The extended readback
tail is not counted as motion evidence.

A two-texel RGBA32F diagnostic observation reads the existing current
`LumHistRaw` inside the combined effect. It decodes the native 576-sample fractions
with the actual `DecodeLumHistFraction`, normalizes measured mass, and walks
p10/p50/p90 plus the existing trimmed 0.275 p25 anchor. Mode uses the existing
64-bin center and argmax tie rule. These are linear-light luma observations.
The diagnostic does not replace histogram smoothing, percentile/mode/p10 histories,
their rates, published highways or the scene-cut detector.

The current observations drive the original quintic lift-strength formula,
zone-standard-deviation suppression and p10 guard. The same raw p90/p50 pair
drives the existing specular-attenuation formula. Deliberate slow-key/zone-key
context, local detail protection, shadow luminance window, profile controls,
gamut mapping and all other helpers remain.

Three image interventions run beside ordinary full output:

- **Current strength:** filter the current-observation strength with the existing
  `AdaptiveStep`, then retain the original published specular guard and context.
- **Current product:** filter the complete current-observation strength × current
  context × current-observation specular attenuation, using the same 32.4/186.7-ms
  coefficients, raw detector confidence and existing cut-reset blend.
- **Direct product:** apply that complete current product without its extra
  consumer recurrence. This is a diagnostic response bound, not a proposed
  unsmoothed output policy.

Independent RGBA32F consumer histories advance once per update with an explicit
initialization flag. The ordinary grade still advances every production history
normally. Frozen images only override the local lift coefficient; they never
feed those interventions back into the ordinary output or history producers.
The raw-strength path isolates the specular pairing; the complete-product path
tests coherence beyond merely relocating a filter around the old targets.

Each replay freezes 48 measured records: first 24 night updates, first 20 return
updates, and both presentations of daylight poses 1428/1432. All are inside the
original clip. Five simultaneous paths include extracted full and actual ordinary
full controls. Native `(16*x+4,16*y+4)` samples form 160×90 tiles. The same border
and two atlas-tag masks leave 12,984 samples in every image, including source
and repeats. These are point samples at measured GPU phases, not full-resolution
motion imagery or dense unique gameplay.

## Results

All distances use mean Oklab ×100 distance on the common sample support.
Duplicate steps compare identical source pose/token inputs.

| Identical-source step | GZW full | GZW current strength | GZW current product | Arc full | Arc current strength | Arc current product |
|---|---:|---:|---:|---:|---:|---:|
| Night update 2 | 0.311300 | 0.030237 | 0.024438 | 0.304247 | 0.024283 | 0.019794 |
| Night update 4 | 0.641209 | 0.067529 | 0.023782 | 0.646533 | 0.068884 | 0.023701 |
| Night update 8 | 0.188996 | 0.172420 | 0.158365 | 0.138332 | 0.123910 | 0.115881 |
| Night update 18 | 0.530544 | 0.530477 | 0.010894 | 0.534852 | 0.534856 | 0.011287 |

Current strength removes most of the early target-driven jump but retains the
late specular-release jump. Current product removes both dominant peaks; its
remaining maximum is at update eight, 0.158365 GZW / 0.115881 Arc. The remaining
residual is not assigned a new causal percentage from this intervention alone.
Maximum same-phase repeat difference is 0.002042/0.004513 for current product,
versus 0.007339/0.012123 for full.

At the first GZW night update, current observations are approximately
p25=0.005893, p50=0.010714, p90=0.027014 and mode=0.007813; p10=0.002143.
They produce strength 1.5 and specular contrast about 0.040749, so the existing
specular guard is fully released. The original published entry values instead
produce strength about 0.443 and the 0.65 attenuation floor, as documented in
the preceding raw-target trace. The current-context gain remains about 3.26;
the complete incoming coefficient is approximately 4.887. No first-frame value
is held, no history producer is reset, and no new strength ceiling is introduced.

The direct-product diagnostic has a similar remaining maximum, 0.159849 GZW /
0.115998 Arc. At update four it makes a larger step than the filtered current
product: approximately 0.093 versus 0.024 in both profiles. Existing temporal
restraint therefore remains useful even with the more coherent observation.
At update 24 the filtered current product retains a small same-pose lag relative
to full, about 0.0142 GZW ΔE. This is not a claim of complete convergence.

## Incoming-image cost and rejection controls

The first-cut image changes by 3.488206 GZW / 3.486009 Arc mean ΔE for current
product. Mean L moves 19.267957→22.732062 in GZW and 19.178603→22.652255 in Arc.
Current strength alone changes the first-cut image by about 2.11 ΔE. These are
large image differences, not quality scores or automatic evidence for adoption.
The deliberate slow-key context boost is retained and becomes immediately
visible when strength/specular observations no longer carry the earlier scene.
Native shadow separation, colored-light shape and incoming-lighting intent need
assessment before this temporal benefit can be accepted.

No candidate adds exact-black samples relative to full or a channel at code 255
on valid samples. Source exact black remains black. All three interventions are
pixel-identical to full at the measured return and daylight rejection records.
The detector is unchanged, so this is distinct from the previously rejected
raw-median detector shortcut. These controls do not certify the full noncut route,
raw-observation behavior in other moving scenes, or already-balanced inputs.

For stationary observations and context, the product's algebraic fixed point
matches the original complete coefficient once its original statistics have
also converged. No held-scene GPU convergence or universal steady-state identity
is claimed here. In particular, adapting the context inside the product adds
short-term lag relative to its original direct multiplication.

## Verification and disposition

All four runs report zero dropped/delayed frames. All 192 extracted-full/actual
ordinary-full controls are pixel-identical, and all 48 measured phase keys match
across runs. There are 960 frozen point images. Independent CPU reconstruction
of the recorded targets and recurrences has maximum errors about 0.000002270
and 0.000002806 in GZW, and 0.000001867/0.000002351 in Arc, including binary
readback precision. The read-only audit passes 1,582 checks across 1,579 unique
artifacts. Protected production shader/profile/config hashes remain unchanged
from the applied gate repair.
All 22 diagnostic tooling tests and the whitespace check pass.

Ignored [captures/lift_consumer_20261027/](../captures/lift_consumer_20261027/)
retains runners, isolated shaders/configs/profiles, four runtime reports,
source/update/cut identities, current observations, candidate control histories,
960 images, `metrics.json`, masked contact sheets, temporal plots and audit output.
No additional production change, effect, manual control or integration path is
chosen. Existing profiles and active configs remain.

Next assess the filtered current-product candidate at full resolution and on held
real-game inputs, prioritizing its changed incoming shadows/materials/colored
lights, useful steady-state lift and noncut rejection controls. Broader motion,
timing, aspects/resolutions, games and active-chain resource sharing remain open.
The gate-only repair remains applied; this screen does not re-score effectiveness
or certify complete temporal behavior.

Follow-up: the [lift/activation closure](2026-10-27_lift_transition_repair.md)
adopts the current-source lift after native material, held and production checks.
Both combined chains are now active with explicit user authorization. This point
screen's candidate decision is complete; do not repeat its proposed follow-ups.
