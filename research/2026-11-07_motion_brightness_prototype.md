# Motion-aware brightness prototype: 2026-11-07 checkpoint

The user wants a motion-aware brightness recovery that can be tested in GZW,
alongside the selected 100% shadow-color correction. Production remains
unchanged. This is an isolated prototype in
`captures/shadow_visual_pipeline_20261106/gzw_motion_100/`, not a finished
recovery effect.

## What currently compiles

The candidate pipeline now builds a 1/8-resolution R32F guide from four
pre-grade BackBuffer taps, decoding RGB to linear luminance and re-encoding the
guide. It retains the previous guide in an R32F target written after the grade
pass. A fixed six-iteration, 24×16 robust global translation fit reads both
guides and writes shift, residual and confidence to a 1×1 RGBA32F target. The
candidate ends with a BackBuffer passthrough after the explicit history write.

The first affine solver used indexed 3×3 matrices and triggered an assertion in
vkBasalt’s SPIR-V backend (`effect_codegen_spirv.cpp`, `emit_load`,
`op.from.is_integral()`). The helper was rewritten as row-vector Schur solves
without matrix indexing. With the helper included and the translation pass
added, the isolated pipeline compiles and captures on the private headless GPU.
The isolated HLSL helper also compiles with glslang. No coefficient readback or
measured-motion capture has yet verified the GPU estimate or its accuracy.

The guide and estimate passes do not yet affect image output. There is no
full-resolution source/history surface, no motion warp in the grade, no
per-pixel correspondence rejection, and no temporal brightness estimate passed
to the compact tone curve. Therefore this candidate is not yet motion-aware
brightness recovery and should not be offered as such for gameplay testing.
The successful held-reference capture proves shader compilation and pipeline
execution only; its image matches the existing combined build within one code.

The next work is to read back the translation estimate on matched moving course
frames, reject invalid/cut estimates, add a warped full-resolution luminance
history and local residual confidence, then carry current-frame detail through
the temporal brightness estimate. Test the resulting recovery on the dense
course at 80–110-fps source clocks, including persistent grain, moving
boundaries, lighting changes and cuts. Source-clock cadence is not achieved GPU
cadence; do not claim performance without an authorized measurement. Keep this
candidate isolated and preserve the current profile and eight production passes.

## Visual color and lift selection

The user reviewed 75% and 100% color candidates and selected 100% as acceptable.
Private headless GZW captures on
`autof_20260515_133058.png` at 20-second settling differ by at most two codes
between 75% and 100%. The 100% GZW repeat differs in 19,793 pixels by one code
after masking the activity marker. The 100% Arc Raiders capture on
`autof_20260515_205938.png` shows a measured 4.3° mean shadow hue shift versus
source. These are reference-image captures, not live gameplay repeats. The
gallery is `captures/shadow_visual_pipeline_20261106/visual_review.html`; metadata
is in `capture_report.json`.

The combined still candidate uses the previously GPU-screened compact spatial
brightness curve plus the 100% color correction. The color correction was
originally multiplied by `BLACKS`; therefore the first `BLACKS=0` config
disabled color, contrary to the user's intention. The current
`gzw_lift_025_black_000/gzw_lift_025_black_000.conf` candidate corrects this by
using a separate copied-profile `EXPERIMENTAL_COLOR_OFFSET=0.0025`, with
`BLACKS=0.0` and `SHADOW_LIFT_STRENGTH=0.25`. Its private headless GZW capture
compiled successfully. This separate experimental color offset is confined to
the candidate; it is not a production control or profile change.

Shadow lift was compared at 0.75, 0.50 and 0. In the GZW reference, disabling
lift lowers mean linear luminance in the source-defined shadow region by about
0.007 versus 0.75. These settings are copied-profile visual controls, not an
adopted profile change. The user asked for 0.25 lift and BLACKS 0.0; use the
corrected config above, not the superseded first config state.

## Production and validation status

All shader, include, profile and active-config files listed in
`captures/shadow_color_half_review_20261106/verification.json` still match their
recorded production hashes. Candidate shaders/configs live only under ignored
capture paths. No production adoption, rating change, commit or push occurred.
GPU capture was private and headless. Do not run profiling or use a desktop
fallback.
