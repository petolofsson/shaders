# Lift-product and cut-gate transition screen — 2026-10-27

Continues the completed [night attribution](2026-10-27_night_settling_attribution.md).
Moving the existing adaptive recurrence to the complete global lift coefficient
does not resolve the early night peak. It softens the later specular release
but extends its tail. Smoothing direct cut-gate recovery reduces the first return
handoff and spreads the response over later updates. Neither result establishes
an acceptable complete transition repair. No production change is adopted.

## Candidates and preserved contracts

The isolated diagnostic evaluates four image paths against the same ordinary
pipeline state: unchanged full, complete-product filtering, direct-gate recovery
filtering, and their combination. A fifth path samples the real ordinary output
immediately after its color pass. The ordinary full grade and all its histories
advance normally. Candidate state runs independently; candidate images do not
feed the production histories.

The product candidate moves the existing `AdaptiveStep` recurrence from lift
strength to the product of raw lift strength, slow-key/zone-key context gain and
specular attenuation. The raw strength reproduces the current quintic,
zone-standard-deviation suppression and p10 guard. Local detail protection,
the shadow luminance window, profile values and stage gates remain. For constant
statistics the product has the same algebraic fixed point as the original path;
this is not a held-scene convergence measurement.

The gate candidate independently filters the existing `adaptation_gate` and
ambient `(1-scene_cut)` factors. It uses the same `AdaptiveStep`: 32.4-ms rising
and 186.7-ms falling half-lives, elapsed frame time, and the existing fractional
scene-cut reset blend. Thus a confident cut still suppresses the direct image
gates immediately, while recovery is gradual. The current Retinex and
chroma-scene-scale image consumers use the filtered adaptation gate; ambient
tint uses the independently filtered ambient gate. Film/print/gamut histories,
the detector and every analysis producer retain their original inputs and rates.
No new threshold, manual control, exposure change or detector shortcut is tested.

The independent RGBA32F candidate state stores product, adaptation gate, ambient
gate and an explicit initialization flag. It updates once before the diagnostic
and ordinary color passes. Product replacement is expressed through the existing
lift-strength field, dividing out the current positive context/specular factor
before the ordinary tonal helper reapplies it. This keeps the actual shared
spatial/tonal helpers in use, with any floating-point reconstruction differences
included in the measured image costs.

## Measurement scope

Four fresh private headless replays retain both existing profiles and unchanged
repeats. Source manifests, frame/clip hashes and the unchanged original packet
prefix are checked against the existing cut-window evidence. Each replay uses
the original 20-second continuous pre-roll and five-second compilation wait.
No desktop fallback or physical display change is used.

Each run freezes 48 records: the first 24 consecutive night updates, first 20
return updates, and both presentations of daylight poses 1428 and 1432. All are
inside the original clip. Binary GPU readback records source/token/update/cut
identities, context and candidate state. Each image is a 160×90 native point
sample at `(16*x+4,16*y+4)`; the common two-pixel border and both atlas-tag masks
leave 12,984 samples. Visual contact sheets mask those same invalid samples.
This is a bounded candidate screen on 15 unique poses/sec duplicated at 30 fps,
not full-resolution temporal acceptance or dense unique gameplay.

## Results and disposition

All distances use Oklab ×100 and mean distance over the common sample support.
The table compares duplicate presentations of identical source poses; it does
not treat a change across moving poses as pure state evolution.

| Identical-source step | GZW full | GZW product | GZW gates | Arc full | Arc product | Arc gates |
|---|---:|---:|---:|---:|---:|---:|
| Night update 4 | 0.642945 | 0.653455 | 0.640652 | 0.648978 | 0.659290 | 0.646284 |
| Night update 18 | 0.533755 | 0.457531 | 0.533755 | 0.532087 | 0.447665 | 0.532087 |
| Night update 20 | 0.016445 | 0.201031 | 0.016445 | 0.015613 | 0.204620 | 0.015613 |
| Return update 2 | 1.483268 | 1.483268 | 0.786304 | 1.483728 | 1.483728 | 0.779713 |
| Return update 4 | 0.046955 | 0.046955 | 0.201989 | 0.042002 | 0.042002 | 0.211825 |

The complete-product candidate leaves the early night strength-driven peak
essentially unchanged. The same existing fast rising coefficient still follows
the changing target, and the delayed fractional cut pulse remains. At the later
specular release, filtering reduces the immediate step but leaves a larger step
after the original has almost settled. Moving the recurrence alone is rejected
as a complete night-transition repair. Do not promote it or simply slow the
intentional slow key by association.

Gate recovery reduces the immediate return handoff but retains a substantial
first step and adds recovery changes to subsequent poses. At the two daylight
rejection poses all three candidate outputs match full exactly on valid samples;
the detector itself is unchanged. This screen therefore avoids the earlier
raw-median shortcut's false triggers. It does not certify the full route or
other noncut lighting changes.

The combination retains the product candidate's night limitation and the gate
candidate's return benefit; it is not adopted. Gate-only recovery remains a
candidate for full-resolution held/motion assessment, including entry and
recovery costs. No profile, active config, shared shader, shader header, prior
spatial repair, existing history rate or pass count changes in this continuation.

## Artifacts and next work

All four runs report zero dropped/delayed frames. All 192 extracted-full/actual
full controls are pixel-identical on valid samples, and all 48 phase keys match
across the runs. Maximum same-phase repeat variation over all candidates is
0.010592 mean ΔE; the measured return reduction is much larger. The roughly
0.010 increase in the early product peak is comparable to that bound, so the
screen establishes no useful reduction there rather than a reliable increase.

There are no added exact-black samples relative to full, no samples with a
channel at code 255 in this screen, and source exact black remains black across
all candidates and runs. These are sample-limited constraints. Forty-four
consecutive state pairs per primary profile independently reproduce the gate
recurrence from GPU frame time, cut confidence and target gates; maximum error
is 0.000000602 GZW / 0.000000183 Arc, including binary readback quantization.
At return update 20 the gate candidate and full are pixel-identical on valid
samples in the primary GZW run; Arc retains one sample differing by one code.
This close agreement at one update does not establish held-scene convergence.

The read-only audit passes 1,624 checks across 1,579 unique artifacts, including
source frames, candidate snapshots, frozen image hashes/extractions, binary state
decoding, phase identities, full controls and completed runtime logs. All 22
diagnostic tooling tests and the whitespace check pass. These are evidence
integrity and tooling checks, not complete shader or visual acceptance.

Ignored [captures/transition_screen_20261027/](../captures/transition_screen_20261027/)
retains `run.py`, `analyze.py`, `audit.py`, isolated shader/config/profile copies,
four runtime reports, explicit state records, 960 frozen images, `metrics.json`,
masked contact sheets and temporal plots. Reports distinguish image candidates
from ordinary history evolution. The screen neither changes the prior overall
effectiveness estimate nor certifies the active separate-effect resource path.

Next assess gate-only recovery at full resolution, and examine how the lift
target and cut reset interact before choosing any further temporal treatment.
Preserve the useful steady-state lift, current time constants, spatial guards,
profiles and daylight 1428/1432 rejection controls. Larger timing variation,
physical high refresh, dense unique motion, remaining aspect ratios, broader
games and active-chain resource sharing remain open.

Follow-up: the [native gate-recovery assessment](2026-10-27_gate_recovery.md)
now applies the gate-only treatment after full-resolution, held and storage
validation. Complete-product filter relocation remains rejected; the remaining
early lift-target transition is measured separately.
