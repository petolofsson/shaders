# Retinex sky compression and guide-domain repair — 2026-10-26

The shared shader now restores the measured broad-sky lightness separation
without restoring the tested flat-face rims. Profiles and active configurations
are preserved. This completes the requested Retinex follow-up to the
[spatial attribution](2026-10-26_spatial_color_attribution.md) and
[zone repair](2026-10-26_zone_scene_pivot.md); broader visual and temporal
acceptance remain open.

## Defect and retained change

The old bounded `key / illuminant` gain compressed the selected blue-sky field.
There was also a signal-domain error: the guided coefficients were fitted to
original source log-luma, but native reconstruction evaluated them at luma after
inverse reconstruction and creative corrections. Weakening gain alone exposed
coarse coefficient errors again as flat-face rims.

`general/native_guide.fxh` now observes native original-source log-luma before
inverse processing. It uses an explicit full-resolution R32F texture and point
sampling. This is an observation, not a temporal accumulator or another effect.
`NativeGuideSource` is the first pass of analysis and the combined pipeline.
The grade technique retains its eight passes; analysis retains its final
BackBuffer passthrough. The combined include guard shares the observation with
grade inside one effect instance.

For native source log-luma `I` and averaged guided coefficients `a,b`, the
reconstructed illuminant is:

```text
q = a*I + b
q_conditioned = I + (1-a)*(q-I)
illuminant = exp2(q_conditioned)
gain = clamp(2*key / (key+illuminant), exp2(-0.35), exp2(0.35))
```

The unresolved fraction attenuates the model residual, rather than fading the
Retinex strength near edges. A native self-model `q=I` stays exact for every `a`.
The key-relative gain normalizes the signed difference by the sum, retains unity
at the key and the existing stop bounds, and weakens broad-field compression.
The guided producer, other base consumers, strength/confidence, highlight guard,
scene-cut gate, history formats/rates and controls remain unchanged. There is
no new tuning control, exposure adjustment, pixel-dependent branch or HDR path.
The existing final gamut projection, dither and SDR ceiling remain.

## Rejected partial repairs

The source-selected sky group gap uses the same fixed region and source-defined
low/high lightness groups as the attribution report. Values below are Oklab L
on a 0–100 scale; they are separation measurements, not fidelity scores.

| Variant | Sky group gap | Held flat-face finding |
|---|---:|---|
| Source | 9.708699 | Uniform diagnostic faces |
| Previous shared output | 7.376501 | Orange/red median edge gaps zero |
| Gain change alone, rejected | 9.641922 | Orange rim 0.181417, red rim 0.106355 |
| Source-domain evaluation alone with new gain, rejected | 9.648168 | Orange broad variation 0.122223; blue edge −0.05895 |
| Source domain + conditioned residual + new gain, retained | 9.646211 | All eight measured held-face median edge gaps zero |
| Retinex bypass | 12.042030 | Attribution control, not a target |

Orange 8×8 block L95−L5 stays near the previous 0.017119 at 0.016616; gain-only
raised it to 0.131081. Red changes 0.016808→0.017524. Selected magenta broad
variation falls 0.189855→0.014188. Green, yellow, cyan and purple broad spreads
are unchanged; blue changes 0.019933→0.019474. Fine dither/quantization variation
still exists. These are scoped boundary/interior checks, not a universal
halo-free guarantee. Contact sheets retain the rejected variants explicitly:
their `candidate` label means the early gain-only experiment; `raw_conditioned`
is the retained variant.

## GPU and held-scene verification

Two fresh GPU probes recover identical 357-record readbacks. They exercise five
keys and 65 illuminant ratios each, neutral response, monotonic gain/output,
the existing stop bounds and weaker intervention than the old ratio. Maximum
CPU-oracle discrepancy is 0.000007057, below the 0.000008 encoding tolerance.
Sixteen native/processed samples plus sixteen coefficient records verify the
original-source observation and residual reconstruction. A diagnostic-only
`WHITES=0.5` exposes the domain mismatch; at one orange boundary the old
evaluation error is −0.974859 stops, the source-domain model error −0.011110,
and the conditioned error −0.000402. User profiles are untouched.

Six held cases use fresh private headless processes, five seconds for compilation
and twenty seconds of continuous playback before capture. Every retained
candidate/repeat image pair is byte-identical. No case adds black pixels or
white-channel clipping relative to the post-zone baseline. Source-black pixels
stay black, with the intentional marker excluded.

| Held input | Whole-frame mean change ΔE | Selected material lightness gaps, before→after |
|---|---:|---|
| GZW sunset | 0.102546 | Ground 30.357825→30.357825; facade 37.638880→37.638880 |
| GZW dark | 0 | Shelf 4.068447→4.068447 |
| GZW vivid | 0.274204 | Sky 7.376501→9.646211 |
| Arc cloud | 0.139001 | Cloud 19.065988→19.065988 |
| GZW overcast | 0.008969 | Foliage 17.238515→17.238515 |
| Arc emitters | 0.042246 | Red lamp 20.815059→20.815059; core 4.521852→4.521852; halo 22.102782→22.102782 |

The selected lighting gaps survive; absolute material lightness can change.
The full bypass with `RETINEX_STRENGTH=0` is pixel-identical before/after the
producer and reconstruction repair. No claim follows that every source shade
or all illumination boundaries are preserved.

## Measured-phase motion and integration

Three fresh motion replays freeze outputs and explicit state on the GPU at
seven poses, each at source updates 1 and 2. All 14 keys match across before,
candidate and unchanged repeat, including both cut windows. They include pose,
token, measured source-update age and measured cut-update age; host screenshot
time does not establish identity. No replay drops or delays frames.

The GPU atlas point-samples native coordinates `5*i+2` into 512×288 tiles.
Border crops exclude the marker and labels. It provides sparse native point
evidence, not a full-resolution motion image or dense continuity test. Measured
motion adds no black or white-channel clipping and keeps source black at zero.
Maximum per-image mean repeat ΔE is 0.003805. Daylight candidate changes are
0.143–0.620 ΔE; night changes of 0–0.001735 are below repeat uncertainty.
The first return update changes 0.000375 and the second 0.161284. The existing
cut gate remains; this does not certify its actual perceptual handoff.

Clearing orange/green edge gaps stay zero in both phases; red/magenta gaps
improve to zero. Existing sampled cyan −0.032357 and first-phase purple
0.085025 gaps remain, rather than being attributed to this repair.

Final shared-path captures of GZW sky, Arc cloud and the held diagnostic match
their isolated retained candidates pixel-for-pixel. Separate active GZW sunset
and Arc cloud controls compile and remain pixel-identical too: all five checks
pass without dropped or delayed frames. The active four-effect
chain still lacks shared explicit analysis resources; the new texture cannot
cross that boundary either. Combined trials remain the adaptive assessment
path, and neither active config is switched. Runtime/memory cost of the new
full-resolution R32F observation and pass is unprofiled; profiling was deferred.

## Reproducible local evidence

Ignored artifacts under `captures/retinex_sky_20261026/` retain:

- `run.py`, `targeted_report.json`, `guide_report.json`, `selected_report.json`,
  `regress_report.json`, `bypass_report.json`: isolated configs, snapshots,
  source/profile/config/image hashes, runtime logs and fresh repeats.
- `probe.py`, `probe/report.json`: GPU readback, decoding and CPU-oracle checks.
- `motion.py`, `motion.fxh`, `{before_run,candidate_run,repeat_run}/report.json`:
  GPU-frozen colors/state, phase identities, hashes and runtime logs.
- `motion_metrics.py`, `motion_metrics.json`, `analysis/*`: strict matching,
  source-defined masks, endpoint/separation/boundary measurements and crops.
- `shared.py`, `applied_report.json`: final shared shader equivalence and both
  active-path controls. `audit.py`, `audit_report.json` verify retained artifacts.

The appended diagnostic-readback tail preserves all 1710 original compressed
motion packets and timestamps; the original 20-second pre-roll and 15 poses/sec
duplicated at 30 fps are unchanged. Media and helper scripts remain local;
this report accompanies the shader changes in version control. The read-only audit verifies 163
retained artifacts across ten runtime reports. Twenty-two diagnostic tests
and `git diff --check` pass. No golden-image suite, effectiveness re-score,
physical 144 Hz claim or general cross-game acceptance is introduced.
