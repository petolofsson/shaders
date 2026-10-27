# Current-source lift repair and combined-chain activation — 2026-10-27

**Decision: adopt the current-source complete-product lift and close this repair.**
The [point screen](2026-10-27_lift_consumer_screen.md), native incoming-material
checks, six held scenes, production-path controls and actual shared-source checks
support the change. The dominant early strength and later specular-release jumps
are removed from the measured night window. Smaller settling and material/color
costs below remain recorded; they do not automatically create new repair tasks.

The user explicitly authorized activating both combined chains. GZW and Arc
active configs now exactly match their tested combined trials. This also closes
the separate-effect resource-sharing configuration defect. Profiles are unchanged.
Both actual active configs pass fresh private headless full/repeat captures with
pixel-identical repeats. Live gameplay and universal visual acceptance are not
claimed by these captures.

## Correction and preserved contracts

Previously, lift strength and specular protection received statistics still
settling from the earlier scene. The existing grade cut reset therefore selected
an initially weak lift target and later released a stale specular guard. Merely
moving the recurrence around those same targets was already rejected. The
adopted path uses current source observations for this consumer and filters its
complete global coefficient instead.

- The existing analysis high-percentile pass writes a three-texel RGBA32F cache.
  Its first record retains the original smoothed p90/p10 recurrence. Two extra
  records contain current p25/p50/p90/mode and p10/mass/validity. No analysis pass
  or history time constant is added or changed.
- [lift_observation.fxh](../general/lift_observation.fxh) uses native 576-count
  decoding, normalized mass, the existing trimmed 0.275 p25 anchor, and original
  percentile interpolation/mode tie rules. These remain linear-light observations.
- New scalar highway slots 212–217 publish p25, p50, p90, mode, p10 and validity
  for the lift consumer. Values retain the existing normalized half-float
  publication convention. Other consumers keep their original histories.
- The current strength, specular attenuation and deliberate slow-key/zone-key
  context form one coefficient. Existing `AdaptiveStep`, 32.4/186.7-ms rates and
  detector/cut-reset blend filter that coefficient in RGBA32F. Local protection,
  shadow window, p10 guard, manual controls and final SDR projection remain.
- The spare alpha channel in the second adaptive record stores the coefficient.
  Its flag is 1 for initialized gates and 2 for gates plus a valid source product.
  Legitimate zero products remain initialized. Source loss preserves the old
  fallback path; source recovery seeds from the current observation.

The original film/lift/print/gamut history record and formulas remain intact;
the original lift route remains the fallback if current analysis is unavailable.
This avoids making the previously separate chain depend on uninitialized new
fields. Both active chains now use one combined effect, so their required
observations and consumers actually share the same resources. Grade stays eight
passes. Profiles, exposure, source palette controls, headers, prior spatial fixes,
existing history rates and SDR output bounds remain.

## Native material and held-scene decision

Four private native entry replays retain both profiles and unchanged repeats.
They freeze night/return updates 1 and 2 at explicit source/token/GPU phases.
All 16 extracted-full/ordinary-full controls match exactly. Native comparisons
use 3,597,056 common samples after borders, prior tag footprint and browser
calibration patches are masked. The original video prefix remains packet-exact;
the longer readback tail is excluded from motion claims.

The larger incoming lift is a real appearance change, not a quality score:
first-cut native mean differences are about 3.46 ΔE in both profiles. It brings
forward the existing strong settled treatment rather than introducing a new
brightness target. GZW measurements at the first night update illustrate costs:

| Source-selected region | Source | Earlier first-cut output | Current-product candidate |
|---|---:|---:|---:|
| Gray face median L | 42.660 | 43.463 | 49.885 |
| Black face median L | 8.597 | 6.924 | 8.368 |
| Floor median L | 26.029 | 25.073 | 29.613 |
| Red core median C | 21.818 | 21.729 | 17.421 |
| Magenta core median C | 24.707 | 22.406 | 19.466 |

Both flat faces retain zero measured edge-minus-center L. The gray face's
interior L95−L5 moves 0.330→0.353; the near-black face moves 0.789→1.425, retaining
a quantization/tonal variation cost. Red and magenta core chroma fall as their
lightness rises; measured hue shifts from the earlier output are under one
degree. Cyan/yellow core median L/C stay unchanged while their gap to the lifted
floor narrows. All selected light cores remain separated from the floor. There
are no added exact-black or code-255 channel samples on the measured native
support, and source exact black stays black. These are bounded material/edge
checks, not universal lighting fidelity or subjective certification.

Twelve further fresh held runs cover GZW dark, sunset, muted, vivid Arc input
under GZW tuning, and Arc clouds/emitters under Arc tuning, each with an unchanged
repeat. The initial full-precision diagnostic differs by at most one code; all
six diagnostic repeats are identical. The actual production data path publishes
current statistics through the same half-float convention as the original
statistics. Its six held baseline/actual comparisons are pixel-identical, with
no added black or white clipping. This preserves the existing treatment at the
measured held states; 30-second observation is not proof of universal convergence.

## Production and state verification

Four native production-candidate replays retain both profiles and repeats.
Six more held production checks compare the real implementation to an independent
recurrence using the same published inputs. All 22 native/held independent/actual
controls are pixel-identical. Recorded products match at binary readback precision
through all 32 night and 30 original-prefix return updates in each native run.

The actual-source observation probe covers ten distributions, including empty
data, black, white, uniform, bimodal, percentile boundaries, mode ties and partial
mass. Maximum observation error is 0.000000084; publications stay within one
half-float ULP, with maximum absolute error 0.000390649 near white. The original
smoothed p90/p10 state matches its unmodified reference exactly. Repeat is identical.

The actual state probe records 256 updates per process across simulated
30/60/144 rates, zero dt, 250-ms hitches, startup, fractional/confident cuts,
source loss/recovery and a valid zero product followed by growth. Maximum final
probe error is 0.000001676; repeat is identical. An earlier state probe pair is
also retained. Original adaptive channels match their reference recurrence.
These are state/timing contracts, not physical high-refresh or whole-game hitch
acceptance.

Two final fresh replays compile the actual adopted shared sources under both
profiles. All eight native shared/independent controls are pixel-identical, and
recorded products match their independent state through the original cut windows.
Adopted shader files are byte-identical to their canonical tested candidates.
All successful runtime checks have zero dropped/delayed frames. All 22 tooling
tests and the whitespace check pass.

One rejected private producer prototype retained RG32F while adding fields that
needed four channels; its probe exposed lost B/A data. Widening this specific
cache to RGBA32F repaired it before adoption. That failed prototype is retained.
The first active-config report also used a private-profile path assumption; its
image/log and reporting failure are separate from the successful actual-config
retries. Neither failed attempt is counted as acceptance evidence.

## Activation and closure

On the user's explicit “Activate both combined chains” instruction,
[gzw.conf](../gamespecific/gzw/gzw.conf) and
[arc_raiders.conf](../gamespecific/arc_raiders/arc_raiders.conf) were changed only
from the separate effect bindings to their tested combined `pipeline` binding.
Shader/profile/texture paths retain their original game-specific values.
Four fresh actual-active-config captures cover GZW muted and Arc emitters,
full/repeat in each. Both repeats are pixel-identical and all four runs report
zero dropped/delayed frames. These configs now load the working resource path
on the next game launch.

Local [captures/lift_validation_20261027/](../captures/lift_validation_20261027/)
retains source/phase/profile/config hashes, native and held images, producer and
state probes, canonical sources, failed diagnostics, actual-source checks,
activation authorization/diff/before snapshots and active-config verification.
`audit.py` verifies the declared changes and protected profiles/other sources.
The final audit passes 899 checks across 836 unique artifacts, covering 28
native/held replays, six synthetic probe runs and four actual-active-config runs.
All successful runs report zero dropped/delayed frames. There are 28 exact
ordinary-full controls and 30 exact production/independent controls. The private
format rejection and active reporting failure remain separate.

The lift decision and active-chain configuration repair are closed for this
technical pass. Remaining broader motion/timing, aspect/resolution and game
coverage are confidence work for stronger claims. Smaller settling, incoming
material/color changes, dark quantization and prior documented costs remain
limitations for overall assessment. No new mandatory repair is queued from
these measurements, and the older provisional effectiveness score is not raised.
