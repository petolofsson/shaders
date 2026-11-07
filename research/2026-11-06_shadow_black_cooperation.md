# Stage-specific black-offset cooperation: GPU decision

The user asked to keep working on the narrower lead after the late full-grade
transfer failed its [full-frame screen](2026-11-06_shadow_wls_fullframe.md).
A concrete isolated shader now targets the black-offset contribution before
later grading. It compiles and runs through both current profiles with no new
resources/passes, but its full-chain appearance/absolute-gradient results reject
the scene-key version. A distinct CPU local-reference revision removes the key
dependence but retains too little useful response to justify another GPU screen.
Neither is adopted. Production, profiles/configs, headers, histories/rates,
resources, passes and effectiveness ratings remain unchanged.

## Narrow target and existing data

For source linear luminance y, define only the black-offset code debt:

```text
a = WHITES − BLACKS
debt(y) = sRGBEncode(a*y + BLACKS) − sRGBEncode(a*y)
```

This excludes deliberate later grading and vanishes exactly when BLACKS=0.
Reuse the existing guarded `TonalIlluminationLog` source-base estimate. Like
the adopted tonal architecture, carry the current post-inverse/source ratio
through that native estimate: `baseY = sourceY * exp2(baseLog−nativeLog)`.
This uses existing source observations; it is not an independently measured
noise-free base. Native log source has its existing 0.001 floor.

The first prototype uses the existing `ctx.slow_key` as reference pivot, in
linear luminance units. With the existing upper shadow window and the configured
BLACKS value, add the normalized sRGB-code correction:

```text
w = sourceY/(sourceY + BLACKS) * (1−smoothstep(0.08,0.15,sourceY))
deltaCode = 0.5*w*(debt(slowKey)−debt(baseY))*tonalGate
```

Apply it after the affine black/white mapping and optional isolated half-color
helper, **before** `ApplyCorrective`, tonal, chroma and look. Convert the code
difference back to a linear RGB gain, subtracting an identical round-trip term
so zero correction is an arithmetic identity, and bound common gain by SDR
headroom. Later grading remains active; no exposure target, new tuning control,
producer, history update or time constant is added. A new consumer of slow key
can nevertheless change sensitivity to its existing history—unchanged rates
alone do not prove unchanged temporal behavior.

The implementation adds a helper/body block to isolated grade copies only.
All existing texture declarations, formats, dimensions, original pre-ColorTransform
functions and eight grade passes remain. It reuses the guarded source helper;
no iterative WLS, new base resource or final-output surface is required.

## CPU contracts before runtime

Scalar controls use decoded gray source fields and the configured affine map,
not the complete chain. They retain exact arithmetic BLACKS-zero/tonal-zero
bypasses, zero source-black correction, ordered ramp and zero tested step
plateau distortion. With a pivot matching the code-16 field, periodic shading
std increases about 7%, while unit white/grain std rises about 1.7%/1.6%.
These are favorable **conditional pre-corrective controls**, not GPU contracts
or evidence of final material-gradient gain.

An initial build assertion compared expected absolute include substitutions
against relative source paths. The build stopped before runtime; normalizing
includes corrects the assertion. `build_initial_prefix_assertion.json` preserves
that tooling failure. No failed shader image is relabeled as a valid baseline.

## Actual private/headless screen

Twelve fresh processes use GZW dark and Arc interior source clips. Each scene
has current/current-repeat, color-only, brightness-only, combined/combined-repeat.
All run the unchanged profiles through isolated combined-pipeline copies.
The common private protocol uses five seconds compile wait and twenty seconds
settling. Source/clip/config/profile/include/shader identities are recorded;
normalized shader bodies are checked against the intended variant rather than
inferred from labels. All processes report zero dropped/delayed frames.

Both current pairs and both combined pairs are **pixel-exact**, with the
intentional 2×2 marker excluded. This is still-repeat evidence, not proof of
full temporal convergence, aligned history states, motion/cuts or performance.
Color-only and brightness-only have single fresh captures per scene.

Source-selected overlapping pair metrics match the preceding generic material
screen: source L 12–65, log-Y gap 0.02–0.5 stops, ab distance below 2, both axes,
offsets 1/4/16. Absolute code-Y and Oklab-L gaps accompany relative log-Y.
Compared with the same scene's color-only output, the combined shader gives:

| Region | Relative log-Y gap change, 4 px | Absolute code-Y gap change | Absolute L gap change | Mean L change |
| --- | ---: | ---: | ---: | ---: |
| GZW shelf | −0.42% | −4.88% | −4.01% | −0.567 |
| GZW blue wall | +0.31% | +0.19% | +0.17% | +0.069 |
| Arc dark metal | +3.40% | +0.03% | +0.73% | −0.527 |
| Arc warm floor | +0.01% | approximately 0% | approximately 0% | +0.005 |
| Arc cool upper | +0.71% | +0.37% | +0.43% | −0.028 |
| Arc cool window | +1.80% | +0.75% | +0.88% | −0.121 |

The shelf loses useful separation. Metal's relative gain mainly accompanies
darker mean levels, with almost no absolute code-gap improvement. Native
four-way images do not establish the clear dimensional improvement needed to
justify adoption. The code is technically executable but does not satisfy the
appearance goal. No full-chain GPU noise, numeric zero-bypass, gamut, broader
material/highlight, chart or measured motion campaign follows this failure.

## Why the favorable scalar example did not transfer

A fixed CPU context counterexample holds source code-16 shading/noise unchanged
while changing only the reference key. With a matching key, the flat mean code
is unchanged. References 0.01/0.05/0.18 linear Y instead darken that same flat
patch about 0.51/1.27/1.55 codes. Periodic-shading std gain falls from roughly
7% to 5.3%/2.8%/1.9%; fine white-noise variation eventually decreases rather
than increases. Thus a plausible correction around a matching reference does
not imply an absolute gradient gain for dark material in a brighter scene.

This demonstrates the model's reference/density sensitivity even before later
grading. It is not direct GPU attribution of which downstream stage contributes
to the measured shelf loss, and the pivot values are counterexamples, not
measured shader telemetry or fitted replacement parameters.

## Distinct local-reference revision, CPU only

To remove new slow-key dependence rather than tune its pivot, a separate fixed
reference uses guarded source estimates at the existing 8-pixel and 32-pixel
sampling scales. Raw coarse sparse observations can alias; an additional
continuous constraint only retains a farther-base residual when it extends the
fine-base residual in the same direction, capped by the fine residual's size.
The reference stays between those estimates and vanishes as the fine residual
vanishes. The same black-debt formula, half strength, source gate and downstream
location otherwise remain.

This is a different geometric reference, not a strength/pivot sweep, and it is
**not** the shader shown in the GPU images. CPU source-black/BLACKS-zero/tonal-zero
contracts and tested plateau preservation remain. Added white/grain std is about
0.67%/0.65%, but the main clean/noisy shading gain falls to about 1.53%/1.10%.
Period-16/32 fixtures remain unchanged; period-128/256 gains are only about
0.37%/0.07%. The sampled log ramp is essentially unchanged in its interior.
This limited retained response does not establish useful material restoration
or warrant more GPU captures. No local-reference shader or adoption patch is built.

## Decision and retained artifacts

Reject the scene-key prototype for adoption and do not port the weak local
revision or recover its strength by automatic tuning. This closes these two
finite stage-specific designs; there is no surviving implementation proposal
from this screen. A further brightness model needs a distinct, supported
mechanism and visible native material benefit, rather than repeated treatment
of darker density or code-noise changes as recovered dimension.

Local artifacts: `captures/shadow_black_cooperation_20261106/` contains the
isolated candidate patch/builds, CPU contracts/context counterexamples, local
revision/scale controls, twelve actual GPU captures, native four-way comparisons,
[review](../captures/shadow_black_cooperation_20261106/review.html), identity audit
and artifact manifest. The patch is a **rejected review artifact**, not production
state or an instruction to apply it. All older color-only options and rejected
models remain preserved. No actual-config candidate activation, new rating,
profile/config/header/history/resource/pass change, commit or push follows.
