# Shader Pipeline

vkBasalt HLSL post-process chain for SDR game output. BackBuffer uses UNORM
views; shaders explicitly decode/encode sRGB at processing boundaries. Internal
work is linear-light. HDR must be off in-game.

## Product Direction and Startup

Read [GOAL.md](GOAL.md) for the agreed game-agnostic visual direction:
fuller SDR color relationships, deep nuanced shadows and convincing light,
with unobtrusive automatic restraint. Preserve the game's palette and lighting.
Richness is not a saturation, darkness or hue-coverage target. Existing profiles
remain intact during assessment; no auto-exposure or HDR output is introduced.
Use [PLAN.md](PLAN.md) for current priorities, [HANDOFF.md](HANDOFF.md) for state,
and [startup-prompt-latest](startup-prompt-latest) as the sole startup prompt.
Current work prioritizes technical correctness and robust intended behavior;
personal palette/print preference is not a blocker. Preserve existing profiles.
All runtime testing must remain private and headless; no desktop fallback.

## Active Chain

Configured in `gamespecific/arc_raiders/arc_raiders.conf` and
`gamespecific/gzw/gzw.conf`:

```text
pipeline (one ShaderPipeline effect containing analysis_frame -> inverse_grade -> corrective -> grade)
```

`grade.fx` is an 8-pass technique:

```text
LFDownscale1 -> LFDownscale2 -> NeutralIllum -> GuidedCoeff -> GuidedBase
-> ColorTransform -> AdaptiveHistory -> TexHwyWrite
```

Diffusion has been removed from `grade.fx`.

## Hard Rules

- `creative_values.fx` is the only user-facing tuning surface.
- SDR by construction: output stays in `[0,1]`; `saturate()` is the ceiling.
- No auto-exposure. `EXPOSURE` is deliberate user tuning.
- No dynamic branches on pixel properties; prefer smooth arithmetic.
- Do not modify shader header comments unless explicitly asked.
- Do not edit `gzw.conf` unless explicitly asked.
- Explicit-render-target-only effects must end with BackBuffer passthrough.

## vkBasalt / SPIR-V Gotchas

- No `static const float[]` or `static const float3`: can compile with wrong output.
- No variable named `out`: reserved by HLSL/SPIR-V.
- No `tex2Dlod(BackBuffer, ...)`: it returns zero; use `tex2D(BackBuffer, uv)`.
- Explicit render targets in separate `.fx` effects do not share data, even at
  mip0. Build and read required surfaces inside one effect technique.
- Inter-effect BackBuffer is UNORM; overrange values clip between effects.
- SDR games commonly use 8-bit; mpv validation used a 10-bit UNORM swapchain.
- Keep BackBuffer `SRGBTexture`/`SRGBWriteEnable` false with explicit sRGB math;
  10-bit UNORM has no corresponding sRGB image-view format.
- Active output uses spatial dither and no temporal grain; analysis sampling retains `FRAME_TIMER`.

## Key Files

| Path | Role |
|------|------|
| `gamespecific/*/shaders/creative_values.fx` | Tuning profile |
| `general/analysis-frame/analysis_frame.fx` | Histogram, percentiles, scene cut, highway write |
| `general/inverse-grade/inverse_grade.fx` | Pre-corrective inverse tone/chroma reconstruction |
| `general/corrective/corrective.fx` | Zone/chroma history, slow key, passthrough |
| `general/grade/grade.fx` | Corrective, tonal, chroma, look, adaptive automation |
| `general/highway.fxh` | Scalar highway slots and `ReadHWY()` |
| `general/hue_bands.fxh` | Hue weights, rolloff, chroma ceilings |
| `tools/compare_frame.py` | Runtime before/after and effect attribution |
| `tools/noise_floor.py` | EXR high-frequency noise measurement |

## Stage Order

1. `inverse_grade`: source reconstruction plus Oklab chroma expansion, bounded
   by `HueCeil()`; FilmCurve is not inverted here.
2. `corrective`: zone/chroma/slow-key analysis; preserves BackBuffer.
3. `grade` corrective: `INVERSE_LUMA` on source signal, then `EXPOSURE`, DIR
   couplers, and 3-way CC.
4. `grade` tonal: guided-filter detail, Retinex/zone shaping, signed adaptive
   contrast, shadow lift, Hunt coupling, ambient tint, highlights, then the
   luminance-preserving FilmCurve shoulder.
5. `grade` chroma: sat-by-luma, Munsell rolloff, hue rotation, vibrance,
   saturation, compression, and gamut projection.
6. `grade` look: Kodak 2383 print stock, masking/dye couplers, printer lights;
   gated by `LOOK_STRENGTH`.
7. Output: dither and 2x2 red activity marker.

## Highway Slots

`HighwayTex` is `256x1 R16F`; values are normalized to `[0,1]` by convention.
Encode/decode out-of-range quantities at the slot boundary.

```text
194 p25, 195 p50, 196 p75, 197 chroma slope, 198 median C, 199 scene cut
200 p90, 201 mean chroma angle, 202 achromatic fraction
203 zone key, 204 zone std, 205 slow key
206 luma mode, 207 entropy, 208 IQR, 209 p10, 210 near-clip fraction
212 current lift p25, 213 p50, 214 p90, 215 mode, 216 p10, 217 source-valid flag
218 current source p75 for inverse-luma restraint (also uses slots 212/217)
```

## Current State

- On 2026-11-04 the user prioritized clear, naked-eye improvements. Assess
  native-size source/full images for a recurring visible loss before developing
  a candidate. The [slow-key probe](research/2026-11-04_slow_key_sentinel.md),
  [hue ablation](research/2026-11-04_hue_direction_screen.md) and
  [print screen](research/2026-11-04_print_chroma_screen.md) produced no adopted
  change or established clear visual improvement. Preserve their limitations.
- Current external GZW profile values are FILM_CURVE=0.70, SHADOW_TEMP=-0.05,
  SHADOW_TINT=-0.010 and MID_TEMP=0.05. Preserve these newer choices; earlier
  references below to different values describe historical evidence epochs.


- On 2026-11-03 the user-authorized [shared-component CC enhancement](research/2026-11-03_neutral_component_cc_adoption.md)
  is adopted. Three body lines scale existing three-way a/b offsets by the common
  linear-RGB fraction min(RGB)/Y. Gray response is GPU-identical; primary faces
  match zero CC. Selected foliage/shelf/cool-material relationships improve,
  retaining blue/warm-material, neutral-tint, quantization and temporal costs.
  Five candidate/baseline pairs each, GPU/CPU contracts, exact zero pairs, both
  gradient charts, 192 measured motion controls and four actual-config exact
  candidate matches pass. Profiles/configs/headers, producers, histories/rates,
  resources and passes remain; grade stays eight passes. Current hashes:
  `captures/neutral_cc_20261103/adoption_verification.json`. Older tonal-base
  outputs are pre-CC. Chain/grade 78 and CC 75 remain provisional carried
  estimates; no fresh full re-score or mandatory sweep follows.


- On 2026-11-02 the [shared tonal base](research/2026-11-02_tonal_architecture.md)
  is adopted. A guarded native-source estimate supplies one brightness base for
  Retinex/zone/lift, with original corrected-pixel detail carried through the
  combined gain. Local cloth/plaster/floor response improves about 2.2%/4.3%/3.8%.
  Source-range rejection protects narrow bright features; relative Retinex spatial
  correction remains. Seven selected held pairs/current baseline pairs, two GPU
  readbacks, exact tonal-zero pairs, 192 exact measured controls and four exact
  actual-config matches pass. All 18 flat-face median edge L/C gaps are zero.
  Road/material/gradient/small transition costs and an original vivid baseline
  repeat failure remain documented. A mislabeled refresh is excluded and an
  explicit preserved-original reference pair is exact. Profiles/configs/headers,
  inverse, histories/rates/resources and eight passes remain. The subsequent
  requested ratings review estimates chain/grade at 78 and joint tonal behavior
  at 80; individual scores remain retained. No mandatory follow-up is queued.
  Current hashes:
  `captures/tonal_base_20261102/verification.json`. GPU profiling stays deferred.

- On 2026-11-01 the user explicitly set `BLACKS=0.0025` in both creative profiles
  (Arc 0.005→0.0025, GZW 0→0.0025), then requested wrapping up. Only those values
  changed; shared shaders/configs remain. The [Arc trial](research/2026-11-01_arc_black_trial.md)
  supports the Arc setting, not GZW appearance. Post-edit actual-config captures
  were deferred then completed on November 2. The historical profile-edit record is: `captures/arc_black_20261101/activation_state.json`.
  Older baseline hashes below retain their original profile epochs. Further
  improvements must target underlying shared shader code, not profile/config
  searches. The exact-Y reconstruction trial was CPU-screened and stopped after
  tiny mixed held changes; it is not adopted or a confirmed defect. The shared
  tonal-base model above is the current implementation.

- The [weak-material color enhancement](research/2026-10-31_weak_material_colors.md)
  is adopted. Lower-tone print ratio weight fades by input C/L over 0.03–0.12;
  protection fades out over linear Y=0.10–0.25 to retain bright palette/highlights.
  Blue-wall/cool-window color gaps improve ~3.85%/2.96%, with small warm-floor,
  foliage/hue and quantization costs retained. Seven exact held pairs, GPU/CPU
  contracts, exact look-zero pairs, four chart/profile cases, 192 exact motion
  controls and four actual-config exact matches pass. Profiles/configs/headers,
  inverse, history rates/resources/passes remain; GZW inverse luma 0.60 is preserved.
  Shared-shader/pre-November-1-profile hashes: `captures/weak_color_20261031/verification.json`.
  No new effectiveness score or mandatory parameter screen follows.
- The [highlight-cooperation enhancement](research/2026-10-31_highlight_cooperation.md)
  is adopted. FilmCurve loss is passed to print to relieve secondary-shoulder
  overlap, retaining FilmCurve and print toe. Selected core separation improves
  ~9%; selected halo/red lamp/dark materials remain. Six exact held pairs, GPU/CPU
  contracts, boundary charts, 192 exact motion controls and four actual-config
  exact matches pass. GZW FilmCurve-zero retains one reproducible one-code pixel;
  other zero pairs are exact. Temporal repeats and chart quantization costs remain
  documented. Profiles/configs/headers/histories/rates/passes are preserved; GZW
  inverse luma is 0.60. Current hashes: `captures/highlight_cooperation_20261031/verification.json`.
  No new score or mandatory screen follows.
- The [tonal-cooperation screen](research/2026-10-31_tonal_cooperation.md) rejects
  both combined log-gain limits after five-scene held comparisons. No production
  shader change or score increase follows. An external GZW INVERSE_LUMA change
  from 0.30 to **0.60** is preserved; use refreshed GZW baselines in
  `captures/tonal_cooperation_20261031/`. The preceding 0.30 rating evidence does
  not establish a new 0.60 effectiveness score. No further mandatory screen.
- The preceding [print/inverse color-preservation follow-up](research/2026-10-31_print_inverse_color_preservation.md)
  is adopted. Print retains its helper luminance curve while blending to preserved
  RGB ratios over input linear Y=0.01–0.10, protecting deep shadows. Inverse adds
  a 14-step per-pixel SDR gamut budget at fixed lightness, preserving incoming C
  and retaining a valid original hue ceiling. Selected sky palette/material color
  improves with documented cool-material, warm-hue, synthetic-primary and
  quantization costs. Both focused estimates are now borderline 75, superseding
  their earlier 70 rows; chain/grade are not freshly re-scored. Seven exact held
  pairs, CPU/GPU contracts, zero bypasses, 384 exact measured motion controls
  (192 new / 192 verified prior) and four actual-config outputs exactly matching
  candidates pass. Temporal repeats reach two codes; held pairs are exact.
  Profiles/configs/headers/histories/rates/passes remain, including GZW tint -0.015.
  This finite task is closed; no further mandatory screen follows. Current
  baseline hashes/artifacts: `captures/color_preservation_20261031/verification.json`.
- The preceding [inverse-chroma decision](research/2026-10-31_inverse_chroma.md) is closed.
  Reconstruction uses `max(0.85 * HueCeil(hue), C)`: it never reduces incoming
  chroma and abstains above its reconstruction budget. Blanket half expansion is
  rejected. Selected red-light color separation improves about 15.7%; modest blue/
  warm-material and Arc daylight-step costs remain. Scalar/GPU contracts, labelled
  held repeats, exact zero bypasses, 576 exact extraction controls over twelve
  independent-history replays and both actual active-config full/repeats pass.
  Actual outputs match current-profile candidates exactly. The original GZW-day
  repeat varied one code; all three refreshed GZW held pairs are exact. An external
  GZW `SHADOW_TINT` edit to **-0.015** is preserved, with fresh relevant GZW evidence;
  Arc and other profile values remain. Only inverse body code changes in this task;
  headers, configs, histories/rates and passes remained. That checkpoint retained
  inverse/print estimates of 70; the latest follow-up above supersedes those two
  ratings and shaders. Its muted GZW case was prior-tint evidence; the latest
  follow-up refreshes it. Use the latest verification hashes for current reuse. The later November 4 profile choices above supersede that earlier tint.
- The [three-way CC decision](research/2026-10-31_three_way_cc.md) is closed.
  With the user's explicit authorization, both profiles adopted `SHADOW_TEMP=-0.075`
  and GZW adopted `SHADOW_TINT=-0.025` at that checkpoint; its later external tint
  choice is recorded above. Other creative values are preserved. Half
  strength restores selected shelf warmth and reduces foliage shifts about
  11–12°→4.5–4.8°, retaining cool neutral shadows and selected density/light cores.
  Quarter strength is not selected. Seven exact selected held pairs, 192 exact
  measured-phase full controls and both actual-config full/repeats pass. Small
  palette, one-code black/blue-pair and first-night-step costs remain. All shaders,
  configs, headers, histories/rates and passes are unchanged by this CC task.
  Focused CC estimate is borderline 75; chain/grade are not re-scored. The later
  print/inverse focused judgments above supersede their earlier 70 estimates. Do not reuse older full images by grade-code identity alone.
- The [print/look follow-up](research/2026-10-30_print_look_preservation.md) adopts
  only a gentler secondary print shoulder (1.5→0.75); the shadow-toe candidate
  is rejected. White-core visible separation improves 4.621→5.334 while selected
  halo/dark materials remain unchanged. Seven exact held repeat pairs, numeric
  GPU contracts, 192 exact same-update controls and both actual-config full/repeats
  pass. Small bright-blue/quantization and daylight-step costs remain. Profiles,
  headers, histories/rates and eight passes remained; print/look stayed 70 at that
  checkpoint, before the latest color-preservation follow-up above.
  This finite screen is closed. The later CC decision above completes its next
  follow-up; do not reopen the toe screen or overwrite unrelated profile values.
- The [October 29 effect reassessment](research/2026-10-29_effect_ratings.md)
  estimated chain/grade at borderline 75/100 and inverse chroma reconstruction,
  then-current CC and print/look at 70. The later CC judgment is recorded above. Other rated
  blocks are 75–90 in their assessed roles; neutral optional controls are unrated.
  These are coarse effectiveness judgments, not fidelity percentages or universal
  acceptance. The review preserves production/profiles/configs and queues no
  mandatory repair. Do not present older technical-working scores as effectiveness.
- Guarded shadow inverse reconstruction uses a shared scene-key reference in the
  affine input domain, clamped to 0.06–0.12 linear Y. Its 0.001–0.005 near-black
  and 0.08–0.20 upper fades retain the original outer ranges; min(original,
  reference) prevents gain relaxation. The existing manual ceiling/current-source
  budget remains. [Attribution and decision](research/2026-10-29_shadow_stage_preservation.md)
  records selected paving gains and retained Arc vehicle/wood/metal/gradient costs.
  Active dark boundaries, numeric GPU contracts, measured cut controls and both
  actual active-config full/repeats pass. Profiles, histories and passes remain.
  This is a bounded enhancement, not universal shadow acceptance or a new repair queue.
- Diffusion is removed from the active grade; no diffusion setting is exposed.
- The 2x2 red activity marker is intentional; mask it in strict image tests.
- Exact-white histogram samples are clamped into the final bin before counting.
- Percentile and entropy reads normalize the temporally smoothed histogram;
  its total mass can be below one during startup.
- Raw global/zone histogram fractions recover their exact 576/100 sample counts
  before statistics. Global smoothed fractions remain continuous; zone CDF walks
  integer counts and uses weighted Welford population variance.
- Scene cuts use p50 delta plus raw histogram entropy delta.
- Median chroma includes all 576 samples; hue-centroid filtering stays restricted
  to colored samples. Percentile covariance initializes only from nonpositive
  state, avoiding false cold starts on legitimate small variance.
- Metadata UVs use integer texture dimensions; non-divisible widths must not
  blend adjacent fields.
- `ChromaHistoryTex` is RGBA32F. Slow key reads its authoritative history directly;
  published highways remain RGBA16F/R16F. Its 20-second/67-ms half-lives are
  unchanged. Remaining authoritative histories are audited below.
- `MeanChromaTex` is RGBA32F with direct feedback; coefficients and half-float
  publications are unchanged. GPU signed/startup/cut/timing probes verify the
  recurrence; matched motion retains a small one-code black quantization cost.
- Six per-hue chroma-history records have no ordinary image consumer; zone and
  slow-key columns remain live. Do not repair unused filters by association.
- Histogram, percentile, near-clip, high-percentile, mode, entropy, zone and
  adaptive accumulators now use 32-bit formats after independent GPU probes.
  Their formulas, rates and initialization are unchanged. Raw observations and
  publications remain half-float; bounded one-frame scene-cut storage stays RGBA16F.
- Guided-filter epsilon is local-variance adaptive.
- Low-frequency downscale and guided-filter taps use allocated integer texture
  dimensions, including widths/heights not divisible by eight or sixteen.
- Zone statistics use 64 squared-edge bins decoded to linear light for near-black precision.
- Local contrast's negative arm uses a luminance-relative smooth bound to preserve shadows.
- Zone contrast uses a live scene-wide mean zone median and global percentile
  span, avoiding interpolated pivot gradients. Its shadow debt is normalized
  by luma plus that pivot, retaining a finite-gain linear black tail. Strength,
  slope cap, diagnostic gate and history production/rates remain unchanged.
- Arc Raiders and GZW share shader code; existing profiles remain assessment
  inputs, not a unified preset. Technical audits do not require taste tuning.
- `RETINEX_STRENGTH`, `ZONE_CONTRAST_STRENGTH`, and `SHADOW_LIFT_STRENGTH` are
  independent diagnostic gates; each zero value is a visual bypass.
- Shadow lift uses the histogram p10 shadow floor as an adaptive black-level guard.
- Film-curve strength adapts to highlight-tail separation, highlight presence, and entropy;
  `FILM_CURVE` remains the manual ceiling.
- Print stock, soft gamut compression, and chroma protection adapt to scene statistics;
  scene-cut confidence temporarily damps those adaptations.
- Internal grade Oklab conversions preserve signed RGB and positive overrange;
  final gamut projection checks negative and over-one channels before `saturate()`.
  Its initial SDR-face test permits only 1e-6 matrix roundoff; gamut-search bounds
  remain strict and final output remains saturated.
- Blue-cusp projection uses a bounded lightness-preserving path with localized
  hue adjustment for out-of-gamut colors; valid input identity and the face guard
  remain. Quantized-gradient and extreme-blue hue/separation costs are documented
  in `research/2026-10-27_gamut_continuity_repair.md`.
- Shared SDR projection repairs the disconnected blue-cusp ray with a bounded,
  lightness-preserving path and localized hue adjustment for out-of-gamut blue.
  Valid-color identity and the existing face tolerance remain. Quantized-gradient
  amplification and extreme-blue hue/separation costs are documented in PLAN.
- Inverse-luma reconstruction applies its weighted linear-light gain in RGB;
  scaling Oklab coordinates directly cubed that gain and over-darkened midtones.
- Retinex reconstructs against pre-Retinex luma; chroma reconstructs against input C.
- Local max-channel protection supplements the global near-clip history.
- Film, shadow, print, and gamut hysteresis uses elapsed time, with no forced
  maximum-strength target on scene cuts; other analysis Kalman filters remain separate.
- Dither uses the sRGB code domain and preserves exact black/white endpoints.
- Retinex retains bounded gain and global confidence without coarse-edge strength
  fading, which produced halos. Zone contrast uses its existing conservative
  0.65 confidence floor uniformly; its coarse-edge fade also produced false rims.
- Retinex evaluates averaged `BilateralLogTex` coefficients in the original source
  domain using `NativeGuideLogTex` R32F, captured before inverse corrections.
  Its unresolved model residual is conditioned by `(1-a)`. Its gain now combines
  a bounded 0.35 log-slope native response with the original guided/native gain
  ratio (`2*key/(key+illuminant)` for each reference), retaining ±0.35-stop bounds.
  The [material-preservation decision](research/2026-10-27_retinex_material_preservation.md)
  records improved selected wall/paving separation, preserved held-face protection
  and retained shadow/cloud/sky costs. The direct-curve candidates are rejected.
  Analysis/combined techniques add the source observation first; grade stays eight passes.
- Matched headless Babylon motion is validated with sparse frame identities;
  15 source poses/sec duplicated at 30 fps does not prove dense continuity.
  At cuts the duplicated pose/token can refer to different GPU updates. Temporal
  repeats require measured render-phase alignment; mpv time is not GPU telemetry.
  Ordinary source-only summaries are labeled as such; strict diagnostic matching
  rejects missing or conflicting source-update/cut-update ages.
- Explicit diagnostic GPU readback isolates the measured dark-return tail to slow
  key rather than local-zone lag. The later precision repair preserves its
  time constants; old capture timing is historical evidence.
- Consecutive cut diagnostics cover 32 night and 30 return updates in the cached
  original clip. Pose 2220 appears only in the appended tail; exclude it from
  motion claims. Atlas tags can overlap a tile interior: mask their footprint
  consistently across all compared images, beyond the ordinary border crop.
- Current cut traces retain the real return handoff and night settling. A raw
  median cut-detector shortcut removes a delayed pulse but creates stronger
  noncut triggers at poses 1428/1432; it is rejected, not applied.
- Same-update night attribution isolates early lift-strength growth and later
  specular-protection release, plus smaller zone and ambient cut-gate responses.
  Frozen control holds/bypasses are diagnostics, not adopted repairs. Preserve
  prior rates and steady-state intent when assessing transition changes.
- Golden-image regression testing has been removed; use matched captures and effect attribution instead.
- Both active configs now use the combined pipeline, following the user's
  explicit “Activate both combined chains” instruction. The earlier separate-
  effect resource-sharing defect is no longer active. Actual active-config
  full/repeat captures are pixel-identical for both profiles.
- `PercHighTex` has three RGBA32F records: original p90/p10 history at 0.5/3,
  current p25/p50/p90/mode at 1.5/3 and p10/mass/current p75/validity at 2.5/3. Its original
  history recurrence is unchanged. Highways 212–217 publish current lift inputs.
- The complete current-source lift coefficient uses existing adaptive rates.
  In the second adaptive record, RG remain cut-gate recovery, B=1 means gates
  initialized, B=2 also validates the source product, and A stores that product.
  Valid zero products remain initialized; source loss/recovery uses explicit flags.
  The original lift path/history remains the fallback for unavailable analysis.
- Inverse luma now backs off to half its manual ceiling over a current-source
  trimmed p25/p75 span of two to four stops. Its gate and lift are unchanged by
  the later Retinex material-preservation enhancement.
  Current p75 occupies the spare B channel of `PercHighTex` record three and
  publishes in slot 218; existing observation/history fields and rates remain.
  The [tonal-selectivity decision](research/2026-10-27_tonal_selectivity.md)
  closes the lift/joint/inverse-only screen. Six held final comparisons/repeats,
  current-source GPU probes, measured cut controls and actual-config checks pass.
  Modest gains and cloud/warm-floor costs remain; no effectiveness re-score.

## Validation

```text
python3 -B -m unittest discover -s tests -p 'test_diagnostics.py'
python3 -B tools/compare_frame.py gamespecific/gzw/analysis/reference/autof_20260515_133058.png --all-effects --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf --only FILM_CURVE RETINEX BLACKS_WHITES --delay 5 --settle 20
```

Capture runs print a unique `/tmp/shader-runtime-*/` directory containing mpv
and vkBasalt logs. All-effects uses a fresh process per image. Use 20 seconds of
settling for small effects and an unchanged repeat; elapsed warmup alone does
not prove full temporal convergence. Private GPU/localhost tests require sandbox
escalation. Diagnostic techniques may explicitly render offscreen history for
readback; ordinary screenshot captures contain no such telemetry.
Screenshot captures contain no highway telemetry; `capture --dump` is unsupported.

Baseline labels do not establish shader identity. Compare the actual normalized
shader body with the intended snapshot before interpreting a capture, alongside
source/profile/config/include/producer identities. Preserve failed repeats and
incorrectly generated variants separately rather than silently reclassifying them.

Current two-game spatial/color coverage is assessed in the
[material/highlight report](research/2026-10-27_material_highlight_coverage.md).
The [lift/activation closure](research/2026-10-27_lift_transition_repair.md) completes
the current-source lift decision and active-chain configuration repair. Native
material/edge checks, six production held identities, independent source/state
probes and actual-source/active-config checks pass. Incoming red/magenta chroma,
near-black variation and smaller settling costs remain documented.
No new mandatory defect repair is queued. Broader timing/motion, aspect/resolution,
game coverage and ratings support stronger claims rather than blocking use.
Do not turn every small residual into another investigation; see PLAN.
The current [0–100 board](research/2026-11-02_effect_ratings.md) records provisional
chain/grade 78 and joint tonal-model 80 estimates, with retained individual rows
and explicit profile epochs.
Older technical-working scores are not current effectiveness or universal acceptance.
