# Shadow-color safeguard screen

The [research and test list](2026-11-06_shadow_color_todo.md) tracks this work. The isolated [black-offset color candidate](2026-11-06_shadow_offset_color_candidate.md) remains unadopted; this screen changes no production shader, profile or configuration.

Later [source/input alignment audit](2026-11-06_shadow_neutral_alignment.md): every weak-source-color sample below has identical RGB in source-only and grade-input screenshots. Its color was already in the source, not demonstrated to have been introduced by inverse processing. The absolute-C mask does not mean exact gray. The audit corrects the corresponding earlier startup interpretation; all original figures below remain valid.

## Saturated-color headroom

The proposed safeguard scales the candidate's zero-luminance RGB correction by the smallest available upper-channel headroom divided by its positive correction, clamped to 0–1. For the tested nonnegative SDR inputs, the original affine base is in range and the correction cannot drive a channel above one. A shared scalar preserves the correction's zero-luminance property in ideal arithmetic. This is an internal safeguard choice, not a claim that all positive overrange is invalid or a general gamut solution.

On the same 204,099 deterministic CPU inputs as the prior test, 345 unguarded samples exceed one (maximum 1.026595); the headroom-bounded version has zero above 1+1e-12 and zero below -1e-12, with maximum 1.0. The maximum luma difference from the original affine mapping is 1.38e-17 and maximum gray difference 8.68e-19 in double precision. These checks do not establish compiled-GPU behavior, behavior for signed/overrange inputs, or downstream gamut and appearance. The calculation uses a hard minimum, which is continuous but can change slope at a boundary; gradients still need testing.

On the four selected 8-bit source screenshot regions, no sampled source pixel with a nonzero correction needed the face safeguard. Those pixels are **proxies**, not the actual post-inverse input to the grade; this observation does not guarantee preservation of the held-scene effect. Scripts and full data are in `captures/shadow_color_guard_20261106/`.

## Near-neutral safeguard and grade-input observation

An exploratory safeguard multiplies the correction by a smoothstep over relative RGB channel range `(max(RGB)-min(RGB))/Y` from 0.02 to 0.10. It is one illustrative threshold, not a calibrated neutral definition. It attenuates very weak color, which could also suppress the very nuances being sought. The source-screen proxies suggested limited engagement, so a separate diagnostic intercepted the decoded color immediately before grade processing and returned it as sRGB for a screenshot. The grade input is downstream of inverse processing. This explicit interception is closer to the input of interest than the source screenshot, but the resulting image still passes through an 8-bit screenshot path and is not a floating-point readback; it is not captured on the same GPU update as the source-only image.

On the same 8×8 source-selected near-neutral samples used in the candidate screen (source Oklab C<0.5, L=12–35), the diagnostic grade-input screenshot has median relative RGB range 0.114 for GZW (5,744 samples) and 0.156 for Arc (5,138). The proposed 0.02–0.10 guard would have median multiplier 1.0 in both; it would attenuate 35.8% and 24.6% of those samples respectively. Grade-input median a/b is [-0.268,0.098] and [0.261,-0.095] on the Oklab ×100 scale. The selected source-neutral pixels can therefore already be colored at the input; a guard that only detects nearly equal input RGB cannot be assumed to preserve their source-neutral appearance. Conversely, suppressing more of that signal could erase intentional input color. These observations neither quantify noise nor establish a particular threshold.

Both diagnostic full/repeat pairs are exact, all four new private headless GPU processes report zero dropped/delayed frames, and before/after production hash sets match. Captures use fixed 20-second settling; no same-update temporal claim follows. `input_report.json` records capture identities, and `input_analysis.json` records the sampled measurements.

## Next decision

The headroom bound is worth testing in an isolated shader, including continuity and direct GPU checks. Do not assume the simple neutral guard solves the observed shifts: first distinguish intended inverse-stage color from later color treatment and inspect representative neutral and weak-color images. Test brightness gradients separately, and retain the user's requirement for visible combined improvement. Do not adopt the existing or bounded candidate solely on these numerical checks.
