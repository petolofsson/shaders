# Shadow richness: research and test list

Target: shadows with fine brightness gradients and very subtle warm/cool material distinctions that feel dimensional without a noticeable color treatment or tint, retaining convincing blacks, the source palette and lighting. The [first color candidate](2026-11-06_shadow_offset_color_candidate.md) is isolated and provisional. Preserve profiles and keep all runtime tests private and headless.

## Current checkpoint — two-part work remains open

Read the [consolidated session state](2026-11-06_shadow_session_index.md),
[latest regional/spectral decision](2026-11-06_shadow_region_budget.md),
[adaptive-range decision](2026-11-06_shadow_adaptive_range.md) and
[focused ratings](2026-11-06_shadow_experiment_ratings.md). They supersede the
historical next-step language below; all individual evidence remains preserved.

- Brightness ~45: no viable implementation proposal survives the current models.
  The user wants continued new brightness designs toward at least 75, not another
  curve/gain/filter sweep or relaxed noise gate. The latest joint budget can
  retain some broad timber shading under known noise models, but fine-material
  and longer-grain costs prevent adoption. Automatic segmentation is not ready
  or justified simply to port the supplied-region reference.
- Color ~70–75: retain the fixed, isolated half-strength helper and its frozen
  validation. It is not adopted and barely improves brightness. Do not treat a
  color-only adoption decision as a prerequisite for the other design work.
- Next work needs a distinct supported shading/material representation, an
  explicit range budget, useful native appearance and a plausible runtime path.
  There is no selected next algorithm or guaranteed numerical route to 75.
- The user requested documentation for a new session. Research/captures stop at
  this checkpoint and resume on their return. No runtime, permission/adoption
  question, publication or mandatory validation campaign is pending.

The companion [inventory](2026-11-06_shadow_report_inventory.md) indexes every
November 4–6 report. This file retains the detailed chronological test history;
older phrases such as "promising" and "next unvalidated lead" are historical,
not instructions to reopen candidates rejected by later reports.

## Earlier implemented screen — black-offset cooperation rejected

The [stage-specific GPU screen](2026-11-06_shadow_black_cooperation.md) builds an
isolated eight-pass/body-only candidate using existing source-base and slow-key
data. Twelve private processes, zero drops/delays and four exact current/combined
repeat pairs establish execution in the measured still scope. Appearance fails:
shelf absolute separation −4.88%; metal relative gain mostly reflects darkening.
A CPU local-reference revision avoids the key but retains only ~1.53% primary
shading gain. Neither is adopted or a reason for more automatic tuning/captures.
Production/profiles/configs/headers/histories/resources/passes/ratings remain.
The two-part goal is open, but no brightness implementation proposal survives
this finite screen. Keep the old color-only option isolated; seek a distinct
supported brightness mechanism rather than treating density changes as gain.

## Earlier decision — late full-grade transfer not worth porting

The [full-frame screen](2026-11-06_shadow_wls_fullframe.md) weakens the preceding
crop result. Relative gains partly reflect density changes; shelf absolute
separation falls, warm-floor/cool-upper lose separation and timber gains remain
subtle. Two cheap guided forms fail to retain both noise restraint and fine
response. No late-transfer GPU trial, strength sweep or adoption follows.
Preserve PNG/source-stage limits and unchanged source-selected bright-highlight
masks. The next unvalidated design lead is black-offset-specific cooperation
before downstream grading, rather than treating all final-grade differences as
loss. No new implementation, resource/pass support or production change exists.

## Earlier research — common-base transfer reference

The [WLS-base research](2026-11-06_shadow_wls_base.md) uses a common source-guided
base without the hard noise classifier. A fixed black-relative/weighted-centered
transfer engages clean/noisy shading and gives small selected wall/metal/timber
4-px gains ~0.96%/3.91%/3.16%, with subtle native changes. Noise remains: ~1.8%/
3.3% unit white/grain and ~4.0%/5.6% at stronger noise; captured noise input is
+1.25% in offline evaluation. Calculated source-black correction stays zero and
tested step distortion is smaller, not universally removed. This is not a
runtime candidate: crop centering, intended grading, broader appearance and a
fixed-pass decomposition need design/validation. Do not port CG or sweep knobs.
Require a visibly useful full-frame result and plausible runtime form before
GPU work. Production/profiles/configs and ratings remain unchanged.

## Earlier validation — noise progress, material engagement still open

The user asked to validate and follow the lead. The [local/code-domain screen](2026-11-06_shadow_local_noise_validation.md)
retains model thresholds and validates conditional noise support. Offline
code-to-log propagation adds +0.56% luminance std on the preserved GPU noise
input, while new synthetic controls retain ~7.6–8.8% averaged shading response.
This is not a compiled brightness shader or real-material gain. All 12 real
cells still reject; clean/noisy engagement differs and noisy steps retain rims.
Do not activate or loosen checks. The design task is supported material/shading
engagement with stable clean/noisy behavior and boundary/order restraint, using
the local noise result as a benchmark. No new GPU run or active change follows.

## Earlier continuation — observation selection abstains on real inputs

The user asked to keep working. The [selection screen](2026-11-06_shadow_noise_observations.md)
uses separate observations for ranking, noise estimation and validation. It
rejects unsupported texture/banding controls but cannot justify transferring
quiet-region estimates into noisier materials. All dense real regions reject;
broader PNG/intensity proxies also have no model-consistent estimates. Preserve
valid-noise false rejections, support limits and semantic ambiguity. Do not tune
these checks until regions pass or use them to drive enhancement. No new material
gain, GPU run or active change follows. The remaining design needs justified
regional noise/texture assumptions or bounded coherent shading, with independent
boundary/order restraint. Earlier synthetic covariance results remain scoped.

## Earlier lead — conditional covariance-estimation progress

The user requested continuing noise estimation. The
[covariance report](2026-11-06_shadow_covariance_estimation.md) separates local
quadratic structure from a finite short-range stationary noise model. On new
known-signal scalar controls, correlation/energy-uncertainty modeling reduces
grain amplification ~42%→3.6% while keeping ~15% averaged shading response;
holdouts retain the result in their stated scope. This is not a real-material
gain or the earlier RGB GPU fixture. Noiseless texture still produces false
noise, actual material estimates are inconsistent, and banding/step rims remain.
The design question is credible noise observations separate from texture and
explicit abstention where unreliable. No production adoption, runtime or new
shader candidate follows; preserve the synthetic/real evidence distinction.

## Previous research — no better combined candidate yet

The user requested web research and retaining high gradient gains while reducing
noise. The [research/reference screen](2026-11-06_shadow_noise_structure_research.md)
assesses four fixed offline models inspired by primary sources: parent support,
bivariate shrinkage, patch recurrence and quadratic structure. None establishes
a better overall noise/material tradeoff; none clears step rims and shade
reversals. Bivariate is quietest (+0.021% RGB fixture) but keeps only 0.6–2.0%
material gains. Recurrence retains 2.2–4.8% gains at +1.42% RGB noise with larger
correlated-noise costs. These remain research references, not implementations
or exact reproductions of published algorithms. No new GPU process or active
change. The design lead is separating noise estimation from structured material
variation and modeling its correlation, before adding more filter machinery.
Boundary/order behavior remains unresolved; preserve the earlier models' limits.

## Earlier follow-up — synthetic noise reduced, broader constraints open

The user requested continuing and reducing synthetic noise. The
[noise-restraint screen](2026-11-06_shadow_noise_restraint.md) reuses dense GPU
inputs. Independent-noise confidence reduces the RGB fixture's added std from
38.6% to 2.4% versus color-only while retaining 6.5%/10.9%/14.9% selected
wall/metal/timber gap gains. It does not handle correlated noise well. Conservative
within-band uncertainty reaches 0.2% on that fixture and improves correlation
stresses, but material gains fall to 1.9%/4.3%/3.4%. Step rims and shade reversals
remain. Keep both as fixed research references; neither is an implementation or
adoption candidate. No new GPU runtime or production/profile/config change.
The remaining design work is coherent shading support plus constraints on the
reconstructed boundary/neighbor response. Existing color-only noise costs remain.

## Previous brightness work — combined reference rejected

The user requested starting brightness-gradient work and assessing both parts
together. The [dense pre-dither reference](2026-11-06_shadow_dense_brightness.md)
uses twelve new private GPU processes and four-way CPU comparisons. Selected
larger wall/metal/timber brightness gaps rise about 10%/15%/19%, with subtle
color alongside, but noise amplification, held shade reversals and synthetic
step rims reject it for implementation. Coarse-only attribution does not clear
those costs. The separate [source-common scalar references](2026-11-06_shadow_source_component.md)
are also rejected for lighting/material changes. Production remains unchanged;
no viable brightness candidate exists yet. Preserve dense inputs and native
comparisons for a distinct future model rather than rerunning these versions
or adding a strength/threshold sweep. Color-only validation is not completion
of the combined goal, and no adoption decision is currently pending.

## Direction — revisit both parts

Read the [two-part review](2026-11-06_shadow_two_parts_review.md). The user asked
to revisit brightness gradients and subtle material colors together after the
color-only adoption proposal. Keep that fixed color candidate isolated; the
immediate task is brightness design, not obtaining adoption approval. No viable
brightness candidate exists yet. Preserve the rejected curve/spatial-model
decisions and require a distinct mechanism before another candidate screen.
When one is worthwhile, compare current, color-only, brightness-only and combined
behavior under the same epoch. Production remains unchanged.

## Completed color work and retained adoption option

Read the [half-color adoption review](2026-11-06_shadow_color_half_validation.md).
The fixed half-strength color candidate now has independent warm-material,
same-update float, direct numeric, whole-chain zero-bypass, broad still/chart,
source-black/noise and measured motion evidence. Forty-three new private GPU
processes complete with zero drops/delays; 192 candidate/ordinary controls are
exact. The source-neutral attribution is corrected: selected weak source colors
were already present, with source/input RGB identical. Exact-gray sample outputs
remain unchanged.

1. Retain the later adoption option for this **modest color-only change**.
   Review the native images and the retained approximately 24% synthetic
   chromatic-noise increase versus current, weak-color shifts, one-code repeat
   variation and small broad-control costs. Production remains unchanged.
2. If adopted, apply only the reviewed shared grade patch and capture both
   unchanged actual active configs with repeats. The prepared script is
   `captures/shadow_color_half_review_20261106/actual_after_adoption.py` and checks
   the exact expected source epoch before running. No commit/push is authorized.
3. Continue the brightness goal from a distinct design. The compact curve and
   constrained local-slope reference are rejected; they are not part of the
   color proposal. Do not resume their parameter sweeps.

The original broad-goal checklist below remains as historical scope/context.
Its stronger coverage and combined-brightness requirements must not obscure
the specific completed half-color measurements or be called universally passed.

## Earlier checklist and experiment record

Latest decision: the [independent warm-material screen](2026-11-06_compact_tone_held_material.md) rejects the fixed compact tone curve for production. A held GZW timber interior loses roughly 15% neighboring-shade separation in two lighter dark bands while the warm pack improves. Candidate repeats are exact; current repeats retain a 675-pixel one-code variation. No curve sweep, adoption or rating change follows. The broader goal remains open; remaining contract/motion checks below are conditional on a worthwhile future design, not a queue for the rejected curve.

The subsequent [structure-confidence/design check](2026-11-06_shadow_structure_design.md) rejects a CPU scale-confidence correction: synthetic noise response is small, but steps acquire rims and a smooth ramp remains unchanged. It also shows that exact paired-base grade evaluation reduces to the prior shared-offset mechanism in the affine limit. Neither warrants GPU implementation alone. The report records the fixed-curve contrast budget and primary research sources; it does not establish a new implementation candidate.

The [local-slope reference](2026-11-06_shadow_local_slope.md) improves a clean ramp and preserves tested hard steps/noise, but suppresses a noisy ramp, rims a soft step and leaks integrated correction into black. Reject this version before real-image/GPU work. Future reconstruction needs final-output constraints and a justified signal/noise estimate together; gating requested gradients is insufficient.

- [x] Establish a real lead: measure source-selected dark color relationships and screen the luminance-preserving black-offset color candidate against current output, black-off and bright controls. Record reversals, neutral-source shifts and internal overrange.
- [x] Screen mathematically bounded color correction and a near-neutral safeguard on a CPU RGB grid and screenshot proxies; document whether safeguards suppress desired weak colors. These proxies are not the actual post-inverse shader input.
- [x] Capture the post-inverse grade input in isolated private GPU diagnostics and compare its encoded screenshot against source-neutral masks; evaluate whether the proposed neutral guard would engage. See [guard findings](2026-11-06_shadow_color_guards.md).
- [x] If the CPU screen is promising, test one isolated bounded shader variant against the unguarded candidate and current chain on matched shelf, metal, neutral, vivid and emitter cases, with exact repeats and verified identities. Reject or revise if the clear appearance benefit disappears or neutral/color costs remain unacceptable.
- [ ] Exercise the compiled helper with independent GPU readback for exact black, neutral ramp, BLACKS=0, luma preservation, saturated faces, gamut/headroom, near-black continuity and both profile values. Contrast CPU expectations against actual pre/post values; do not infer a GPU contract from 8-bit screenshots.
- [ ] Test neutral-to-colored ramps, near-black warm/cool gradients and ordinary edges, including source noise and one-code perturbation. Measure shade reversals and quantization alongside native comparisons, without treating increased saturation or color distance as a quality score.
- [ ] Test a separate brightness-gradient lead against the color candidate and current chain. Preserve the chosen black anchor, avoid halos and protect original lighting; compare both dimensions together. Do not reopen rejected curves without a specific new mechanism.
- [ ] If held stills justify continued work, run measured same-update motion and cut controls, compare repeated histories and evaluate near-black flicker. Do not equate source-pose matching or static warmup with GPU-update alignment.
- [ ] Validate final behavior across dark, bright, vivid and intentionally muted scenes, multiple materials and both active profiles; include real warm/red-black examples rather than assuming the current shelf supplies them. Assess user-visible appearance, hue/neutral drift, highlights and documented tradeoffs.
- [ ] Decide whether a candidate meets the goal without meaningful regressions. Only then complete actual-config activation checks and document final scope, risks, identities and any retained cost. If the effect remains subtle or risky, close the lead without changing production or ratings.

The [bounded still screen](2026-11-06_shadow_color_bounded_screen.md) retains the earlier subtle color benefit and neutral/reversal costs; brightness gradients barely change. The bound changes at most three pixels by one code in these stills. It is not an adoption or GPU-contract result.

The [numeric and ramp checks](2026-11-06_shadow_color_numeric_ramps.md) pass sampled profile-value GPU arithmetic and average chart-luma ordering, but all chart repeats vary by up to one code. The limited saturated sample, pixelwise/color/noise continuity, actual material edges and motion remain open; do not read these partial checks as full contract or stability acceptance.

The [half-strength screen](2026-11-06_subtle_shadow_color.md) is complete. Selected color distances improve and the native change is subtle, but source-neutral shifts remain, shelf and metal reversals worsen, and brightness gradients barely improve. Do not adopt or start another strength sweep based on these two stills. On resumption, seek a concrete brightness-gradient mechanism, respecting the rejected prior screens; use the color candidate as provisional context rather than assuming it will be adopted. Revisit remaining color validation only if a coherent, visually worthwhile combined approach warrants it.

The [local shared-offset feasibility calculation](2026-11-06_shared_offset_feasibility.md) identifies a possible mechanism for retaining local relative brightness response at the existing flat-field level, but its naive form loses the black anchor at boundaries. It is not a shader candidate or an image result. Any continuation must first address that failure and test edge, noise and ordering behavior; the earlier offline detail-transfer costs still apply as a warning.

The [bounded shared-offset synthetic screen](2026-11-06_shared_offset_synthetic.md) rejects one black-protected bilateral model before shader or image testing: it creates opposing rims on a small step, amplifies synthetic noise, and barely changes a smooth ramp. This does not rule out all local models; it does not justify a parameter sweep or production change. A genuinely distinct lead needs a demonstrated way to retain useful shading while protecting edges and noise, rather than simply amplifying local residuals.

The [monotone output-curve research](2026-11-06_shadow_monotone_research.md) tests a scene-fitted offline proxy: selected shelf/metal gradients rise, but cool-material separation falls and source-black output is not anchored. Its scalar ordering does not establish full-chain ordering, color or temporal behavior. It is a feasibility lead rather than an adoptable curve; solve the actual black-response reference and test input/noise/held scenes before considering a shader candidate.

The [source-gated curve screen](2026-11-06_shadow_curve_black_guard.md) shows that a zero grade-input gate can preserve that pixel's existing pre-dither output algebraically, subject to verifying the inverse handoff. Its two-input CPU stress test exposes possible reversed response from the varying gate; the screenshot proxy retains cool-material costs and does not observe actual grade input. This particular version is not an implementation candidate, and no threshold sweep follows.

The [diagnostic grade-input screenshot follow-up](2026-11-06_shadow_curve_grade_input.md) produces the same quantized proxy crops and finds small new continuous pair reversals from separately captured 8-bit images. It is closer to the intended gate input but is not a same-update floating-point observation or evidence of actual GPU reversals. The selected cool-material cost remains; no adoption or repeated proxy screen follows.

The [combined brightness/color proxy](2026-11-06_combined_shadow_proxy.md) tests the curve on the isolated subtle-color output. Selected shelf and metal improve in both measured dimensions, but ordering costs, a cool-window brightness loss and blue-wall color loss remain. This is a doubly quantized offline proxy, not a combined shader or motion/black validation; no adoption or parameter sweep follows.

The [redistribution screen](2026-11-06_shadow_curve_redistribution.md) tests a broad return to identity and an absolute-lift-bounded return. The broad version harms selected cool-material response; the bounded version reduces those costs but leaves blue-wall loss and the inherited black/ordering uncertainties. Neither is a production candidate. Continue from a materially different, evidence-backed mechanism rather than an automatic curve-parameter sweep.

The [ordered brightness and grade-input color screen](2026-11-06_ordered_shadow_design.md) develops a nonnegative two-input correction that is analytically monotone in either scalar input, and a separate ideal-luma-preserving output-color proxy. It improves selected shelf statistics with smaller measured ordering costs than the earlier combined proxy, but changes are subtle, cool-material and GZW source-neutral costs remain, and its pivot is scene-fitted. Independent 8-bit images and synthetic perturbations do not establish GPU, black-handoff, actual noise or temporal behavior. Do not adopt; seek evidence of a visual benefit and palette-preserving design across held materials before a compiled candidate.

The [output-color headroom screen](2026-11-06_output_color_headroom.md) finds a constructed saturated-face overrange missed by random samples and gives a CPU-only common-factor safeguard preserving ideal luma. It does not resolve color or visual risks. The [warm-material proxy check](2026-11-06_warm_material_proxy.md) finds small brightness/color-gap losses in two warm regions of the existing scenes; they are not independent scenes or deep red-black coverage.

The [ordered-brightness headroom screen](2026-11-06_ordered_brightness_headroom.md) finds that its common RGB gain can exceed SDR on saturated faces, and tests a CPU-only common-gain cap. This cap changes the ordering contract and needs its own continuity and GPU tests if the visual design warrants further work. It did not engage in the two independently captured 8-bit output proxies; that is not broad gamut evidence.

The [same-update float-pair diagnostic](2026-11-06_shadow_float_pairs.md) captures grade input and a pre-dither production-grade clone in RGBA32F at 16×16 native-pixel-center grids in four selections; four repeat pairs are exact at encoded precision. Simulated 8-bit output changed some coarse pair-order classifications, while simulated 16-bit retained them on this sample. A CPU-only model evaluation changes more sample values at 16 bits, as expected. This is a measurement improvement, not a 16-bit game-output or candidate GPU/visual/motion result. The report records excluded values above its 0.25 encoding ceiling and earlier diagnostic failures.

The [four-pixel float follow-up](2026-11-06_shadow_float_detail.md) repeats the probe on four 64×64 patches. Simulated 16-bit changes one of 1,653 pair classifications versus float; 8-bit changes 19. The CPU research model increases selected shelf/metal mean linear-Y gaps and slightly reduces wall/window gaps. The initial window capture dropped one frame and is excluded; its successful retry pair and the other three pairs repeat exactly. These are sparse patches from the same scenes, not production-candidate or motion validation.

The [relative-response model](2026-11-06_relative_response_curve.md) replaces the brightness pedestal with a proportional gain, preserving fixed-context relative response over a broader shadow range. Its selected shelf gain is tiny while cool-material luminance rises, so it is not adopted or a basis for a parameter sweep; CPU float pairs and screenshot proxies do not establish a user-visible benefit.

The [float black-handoff check](2026-11-06_float_black_handoff.md) observes zero post-inverse input at the diagnostic resolution for a source-black fixture in both profiles, with small nonzero pre-dither grade-clone output. Four private captures produce exact within-profile repeats. This supports the zero-input gate in that fixture only; it is not a compiled-candidate or arbitrary-scene endpoint contract.

The [output-chroma proxy](2026-11-06_output_chroma_proxy.md) tests a zero-luma, exact-gray color expansion with a common SDR headroom cap. Although selected shadow-color and ordering measurements improve, it strengthens neutral casts and makes up-to-11-code changes to saturated foliage and a HUD element in the two 8-bit still proxies. Reject this version; the cap does not establish unobtrusive palette behavior.

The [shared-component output-chroma proxy](2026-11-06_shared_chroma_proxy.md) attenuates that color correction near RGB faces, reducing the tested color-only maxima to 1–2 codes and retaining some selected metal separation. The shelf color-only gain is small, existing source-neutral tint is strengthened, and cool-material brightness costs remain. Same-update float-pair CPU evaluation is consistent with the metal/neutral tradeoff; no GPU candidate, motion, broad-scene or visible-benefit acceptance follows.

The [local chromatic-residual screen](2026-11-06_local_chroma_residual.md) preserves a spatially uniform tint algebraically, but the tested filter gives small shelf/metal color gains, opposing synthetic color-edge rims and about 37.5% continuous amplification of a synthetic one-code red-noise fixture. It is rejected before GPU implementation; it is not a universal rejection of spatial color processing.

The [slope-limited monotone tone fit](2026-11-06_float_tone_fit.md) uses the same-update float pairs and improves selected shelf/metal relative gaps while roughly retaining selected cool-patch gaps. Its 8-bit still proxy also changes broad daylight/vivid/emitter regions by up to 6–7 codes, darkens some near-black ramp values, and amplifies a synthetic one-code noise fixture. It is fitted to two scenes and one black-field context, not an adoptable shader or a 16-bit-output validation.

The [compact tone GPU screen](2026-11-06_compact_tone_gpu_screen.md) confines that fitted curve to output Y 0.00175–0.02 and tests an isolated compiled implementation. Five candidate/repeat pairs are exact; selected shelf/metal gradients improve while cool-window, foliage and vivid-field costs remain. The scene-fitted black threshold, synthetic ramp/noise costs, knot continuity, missing red/blue-black color benefit, numerical GPU and measured motion checks remain open. It is promising but not adopted; no profile, active shader or rating changed. Continue from native visual evaluation, warm/red-black material and the stated controls before any adoption.
