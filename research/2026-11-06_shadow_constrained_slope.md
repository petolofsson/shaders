# Constrained local-slope reference

**Do not port this reference to the shader.** It repairs several synthetic failures of the [first local-slope model](2026-11-06_shadow_local_slope.md), including the noisy ramp and mixed black-ramp case. On seven native material crops it produces almost no visible benefit. This is useful feasibility evidence for constraints, not an implementation candidate or a universal rejection of gradient-domain processing.

## Model

Retain sigma-4 source/output log-luminance slope fitting and the screened gradient solve. Estimate high-frequency variance from a sigma-0.7 residual, normalized by that filter's squared impulse-response norm and averaged at sigma 4. Subtract its predicted contribution from the plane-explained variance and residual variance. Require both plane-like structure and estimated slope significance before requesting half the missing gradient. This assumes locally independent noise-like high-frequency content; game texture, quantization and correlated noise violate that assumption. It is not a calibrated noise estimator.

After solving, constrain log gain to ±0.15 stops. Connected cardinal neighbors with exactly equal original output luminance share one gain; components containing exact source-black pixels are pinned to zero gain. Alternating pair projections enforce original horizontal/vertical adjacent output order. These constraints operate on continuous luminance and only adjacent pairs, not all source order or post-quantization RGB. The projection is an audited feasibility calculation, not a proof of optimality or a practical GPU method.

## Synthetic results

The new 64×256 fixtures are distinct from the first reference's dimensions. Constant black/gray and tested hard steps remain unchanged. Code-16 ±1 independent noise has continuous encoded std 0.645719→0.645726 codes, about +0.0011%. A clean code-8→40 ramp increases std 5.96869→6.47120 (+8.4%); its noisy version increases 6.01054→6.45127 (+7.3%). Those numbers describe variation, not a quality score. A mixed black-ramp fixture retains exact source-black output, with maximum measured adjacent-order residual 5.52e-10 stops. The soft-step fixture has zero adjacent-order violation, but its flat sides move apart: below/above the original plateaus by 0.00003153/0.00004029 linear. Removing reversing rims does not preserve the original contrast or lighting.

The final projection does not establish a complete gamut, color, spatial continuity or temporal contract. The small black-ramp residual is retained rather than described as exact monotonicity. `synthetic.json` records the full tests. Sinusoid/noise negative derivatives are naturally expected and are not treated as defects.

## Native crop reference

Run the model on 64-pixel-padded current/source crops, apply its gain to current linear RGB, limit common gain to SDR channel headroom, and encode to 8-bit. This is an offline proxy using separate source/output screenshots, not actual grade-input or compiled candidate evaluation. Existing image SHA-256 values are checked against prior records. The new timber/pack source uses the original PNG and retains its missing source-only playback transfer check. Input/UI/dither and original baseline epoch limits remain.

| Region | Mean signed four-pixel log-Y gap current → reference | Maximum encoded change |
| --- | ---: | ---: |
| Shelf | 0.115959 → 0.115959 | 0 codes |
| Blue wall | 0.075890 → 0.075890 | 0 |
| Dark metal | 0.137007 → 0.137196 | 4 |
| Cool window | 0.149966 → 0.149966 | 0 |
| Held rear timber | 0.140041 → 0.140039 | 1 |
| Held lower timber | 0.158673 → 0.158673 | 0 |
| Held warm pack | 0.117209 → 0.117209 | 0 |

The held rows use source L 12–35 without the preceding warm-ab restriction, hence do not share populations with the compact-tone held report. Pairs overlap and are descriptive. The metal's approximately +0.14% gap change does not establish a visible improvement; the native comparison shows no clear useful return. Whole-crop maximum changes do not describe typical or selected-pair effects.

An initial solve stopped at 600 iterations with relative residuals up to 0.00102. Its metrics are preserved in `initial_solver/images.json`. Raising only the numerical iteration limit to 4000 yields 1038–1298 actual iterations and residuals below 1e-6; the lack of material benefit remains. This is solver correction, not a visual strength sweep. Final projection residuals are below 3.76e-10 stops in these crops. No headroom limiter engages. These are continuous adjacent output constraints before encoding, not global source-order or quantized guarantees.

Artifacts/scripts/metrics/native comparisons: `captures/shadow_constrained_slope_20261106/`. No new runtime/GPU capture, full-frame model, actual motion, numerical shader contract, performance or activation check occurred. Production, profiles, configs and ratings remain unchanged. The natural-image screen does not justify a GPU implementation or loosening the classifier simply to force visible engagement.
