# Black-offset color-preservation candidate

## Status

Promising isolated color lead, **not adopted**. A shader experiment preserves more of the dark material's color through the configured black offset while retaining its calculated luminance. The selected shelf becomes visibly warmer, and measured dark color-group separation increases on shelf, metal and cool window. The selected brightness gaps barely change; this does not yet deliver the user's full color-and-brightness gradient goal. Neutral-source shadows change, source-relative ordering reversals increase, and synthetic saturated inputs can exceed one internally. Further risk work is required before considering adoption.

## Isolated change

After the existing affine black/white mapping in an isolated grade copy, add `BLACKS * gate * (RGB/max(Y, 1e-6) - 1)` where `Y` is the decoded post-inverse input to the grade and the gate fades in over Y=0.0005–0.005 and out over 0.08–0.15. This uses smooth arithmetic and adds no control, pass, history or texture. For a valid nonnegative input and ideal arithmetic, it transfers some neutral pedestal into the input's color ratios while keeping its weighted linear luminance: the correction's luma is zero when the denominator is Y. Exact black remains the configured pedestal because the gate is zero; neutral input and BLACKS=0 also have algebraic bypasses. It does not change or relax the user's profile setting.

Those are fixed-input properties, not claims about the downstream pipeline or a compiled GPU contract. A 204,099-input independent CPU check including gray ramps, exact black and random SDR RGB reports a maximum luma difference of 1.38e-17, gray difference 8.68e-19, and exact zero-BLACKS equality in double precision. Of these inputs, 345 create an intermediate channel above one, versus zero with the original affine mapping; the maximum is 1.0266 on a saturated-blue example. Positive overrange is allowed in internal grade calculations and final output remains SDR, but downstream response and gamut projection can change. This is a concrete control gap, not proof of output clipping or a production-safe contract. The sampling is not exhaustive.

## Held screenshot measurements

Dark color-group distances use the same fixed source-b quartiles and source-L 12–35 selection as the [preceding screen](2026-11-06_shadow_color_nuance.md), in Oklab ×100. These broad groups can also differ in brightness; the quantities are not perceptual quality scores. Four-pixel values use source-selected neighboring pairs. Captures are 8-bit stills from separate processes, with no direct input/output GPU telemetry; source-selected comparisons are sensitive to quantization.

| Region | Color distance current → candidate | Four-pixel signed log-Y gap current → candidate | Median L current → candidate |
| --- | ---: | ---: | ---: |
| GZW shelf | 0.327 → 0.516 | 0.115959 → 0.116279 | 16.073 → 16.073 |
| GZW blue wall | 0.092 → 0.086 | 0.075890 → 0.075977 | 23.717 → 23.678 |
| Arc dark metal | 1.575 → 1.986 | 0.137007 → 0.136837 | 17.559 → 17.589 |
| Arc cool window | 1.970 → 2.251 | 0.149966 → 0.150062 | 22.372 → 22.365 |

The corresponding shelf four-pixel source-relative reversal rate increases 6.488% → 8.039%; metal 5.754% → 6.420%, blue wall 2.626% → 3.709%, cool window 1.984% → 2.076%. Source ordering is not an absolute visual target, but the increases and 8-bit sensitivity need investigation. Source-neutral shadows are not necessarily neutral at the actual grade input: in source-selected C<0.5, L=12–35 samples, median output a/b changes GZW [-0.158,-0.043] → [-0.217,0.097] (5,744 sampled pixels) and Arc [0.165,-0.396] → [0.219,-0.479] (5,138). Thus the fixed neutral-input property does not prove neutral-source appearance is unchanged.

Control regions show white-core and halo L gaps unchanged at displayed precision, red-lamp 18.546 → 18.452, vivid blue-field 27.390 → 27.357 and vivid blue-sky 10.567 unchanged. These do not establish absence of hue, texture or boundary costs. The vivid control uses Arc source with GZW settings, not a third game. Four whole-frame candidate/repeat pairs are exact with the 2×2 activity marker masked. Whole-image maximum per-channel differences from the verified baselines are 7, 8, 8 and 10 codes for GZW dark, Arc interior, Arc emitters and vivid respectively. No additional all-channel black or channel-255 samples were counted in these images, which is not an endpoint/gamut proof.

All eight new private headless GPU processes report zero dropped/delayed frames after the fixed 20-second settle. The first sandboxed attempt failed to start its private runtime (`/tmp/shader-runtime-4enuitv0/gamescope.log`); the successful captures used approved private GPU access. Grade snapshots are identical across all isolated captures; before/after production hash sets match. The static repeat protocol does not prove full convergence or temporal stability.

Native crops and full metrics are in `captures/shadow_offset_color_20261106/`. The candidate has not had a direct GPU numeric contract, gradient/neutral charts, near-black noise or motion testing, actual-config activation, or broad game and saturated-color coverage. In particular, there is no demonstrated brightness-gradient improvement. The appropriate next work is a bounded test for overrange and dark-neutral behavior, followed by actual visual and temporal evaluation if the appearance remains worthwhile; do not treat this screen as adoption authorization.
