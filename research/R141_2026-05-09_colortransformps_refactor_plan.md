# R141 — ColorTransformPS Refactor Plan (F4-A)

**Date:** 2026-05-09
**Status:** Plan only — no code changed
**Scope:** `general/grade/grade.fx` — `ColorTransformPS` (~427 lines)

---

## Why this is hard

`ColorTransformPS` is a strict linear pipeline. Every stage reads intermediate
values produced by the stage above it. Variables cross stage boundaries:

| Variable | Computed in | Consumed later in |
|---|---|---|
| `lf_mip2` / `illum_s2` | preamble (hoisted) | CORRECTIVE (halation), TONAL (R66), CHROMA (R117C) |
| `perc` | preamble | CORRECTIVE (fc_knee), TONAL (shadow lift) |
| `zone_log_key`, `zone_std`, derived | preamble | CORRECTIVE (FilmCurve), TONAL (Retinex, lift), CHROMA (hk_exp, chroma_str) |
| `lms_illum_norm` | preamble | CORRECTIVE (cfilm_floor) |
| `lin` | preamble | mutated through all three stages |
| `fc_knee`, `fc_knee_toe` | CORRECTIVE | CORRECTIVE only (print stock re-uses) |
| `new_luma` | TONAL | CHROMA (Purkinje gate, scotopic) |
| `local_var` | TONAL | TONAL (shadow lift) + CHROMA (chroma_str R68A) |
| `lab.x` (final Oklab L) | CHROMA | CHROMA (multiple) |
| `h_perc`, `h_out`, `sh_h`, `ch_h` | CHROMA | CHROMA (multiple) |

Extracting a whole stage as a function means its parameters include all of
the above that cross its boundary — which is a long list.

---

## What CAN be extracted cleanly (self-contained sub-operations)

These blocks have well-defined inputs and a single return value. Each is
already wrapped in `{}` braces in the current code.

| Block | Lines (approx) | Inputs | Output |
|---|---|---|---|
| Halation (R105) | ~12 | `lin`, `uv`, `lf_mip2`, `HAL_*` | `float3 lin` |
| Print stock (R51) | ~14 | `lin`, `fc_knee_toe`, `fc_knee`, `PRINT_STOCK` | `float3 lin` |
| Masking coupler (R110) | ~8 | `lin`, `PRINT_STOCK` | `float3 lin` |
| Dye matrix (R130) | ~12 | `lin` | `float3 lin` |
| Bleach bypass | ~10 | `lin`, `BLEACH_BYPASS` | `float3 lin` |
| 3-way CC (R19) | ~14 | `lin`, `SHADOW_*`, `MID_*`, `HIGHLIGHT_*` | `float3 lin` |
| Ambient shadow tint (R66) | ~12 | `lab_t`, `lf_mip2`, `r65_sw`, `scene_cut` | `float3 lab_t.yz` |
| Chromatic induction (R117C) | ~8 | `f_oka`, `f_okb`, `lf_mip2`, `final_C` | `f_oka`, `f_okb` |

These 8 helpers would reduce `ColorTransformPS` by roughly **90 lines**.
Each fits comfortably within the 60-line rule.

---

## What CANNOT be extracted cleanly

These sections are tightly coupled to surrounding context — they both read and
write shared intermediate values and are not worth extracting:

- **FilmCurve coefficient setup** — 12 lines of scalar arithmetic feeding
  directly into `FilmCurveApply()`. Already a helper call; extracting the
  setup adds a large parameter list for no gain.
- **Zone S-curve + Retinex** — `new_luma` is computed across Retinex,
  shadow lift, and R62 in a single chain. Splitting would require passing
  `new_luma` in and out multiple times.
- **CHROMA body** — hue weights (`hw_o0`…`hw_ros`), `h_perc`, `h_out`,
  `final_C`, `final_L` all feed each other. The whole chroma block is one
  interconnected computation.

---

## Recommended approach: extract the 8 self-contained helpers only

Do not attempt to extract full stages (CORRECTIVE/TONAL/CHROMA) as named
helper functions. The parameter lists would be as long as the stages themselves
and the refactor would be pure churn with regression risk.

Instead, extract the 8 blocks above. Proposed signatures:

```hlsl
float3 ApplyHalation(float3 lin, float2 uv, float3 lf_mip2);
float3 ApplyPrintStock(float3 lin, float fc_knee_toe, float fc_knee);
float3 ApplyMaskingCoupler(float3 lin);
float3 ApplyDyeMatrix(float3 lin);
float3 ApplyBleachBypass(float3 lin);
float3 Apply3WayCC(float3 lin);
float2 ApplyAmbientTint(float2 lab_yz, float3 lf_mip2, float r65_sw, float scene_cut, float lab_x, float lab_C);
float2 ApplyChromaticInduction(float2 ab, float3 lf_mip2, float final_C);
```

After extraction `ColorTransformPS` itself would be ~320 lines — still above
the 60-line cap, but the MegaPass exception is already documented. The goal
is reducing cognitive load, not hitting the cap.

---

## Risk assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| Accidentally reorder a variable read | Medium | Extract one block per commit; compare screenshots |
| SPIR-V inlining behaviour changes | Very low | Inline functions are identical compiled output |
| `lf_mip2` passed by value copies 12 bytes | Negligible | Compiler optimises trivially |
| `Apply3WayCC` uses 6 creative_values uniforms — long parameter list | Low | Pass uniforms directly; they're compile-visible |

---

## Suggested order of extraction (safest first)

1. `ApplyDyeMatrix` — purely arithmetic, no texture reads, no cross-stage deps
2. `ApplyMaskingCoupler` — 8 lines, fully self-contained
3. `ApplyBleachBypass` — one Oklab round-trip, fully self-contained
4. `Apply3WayCC` — slightly more complex but still isolated
5. `ApplyPrintStock` — reads `fc_knee_toe`/`fc_knee` from caller
6. `ApplyHalation` — reads two textures, straightforward
7. `ApplyChromaticInduction` — reads `lf_mip2`, straightforward
8. `ApplyAmbientTint` — most parameters; do last

Each extraction is one commit, one visual verify in-game.

---

## Open question before starting

`Apply3WayCC` uses `SHADOW_TEMP`, `SHADOW_TINT`, `MID_TEMP`, `MID_TINT`,
`HIGHLIGHT_TEMP`, `HIGHLIGHT_TINT` — six creative_values uniforms. HLSL
uniforms are globally visible, so the function body can reference them
directly without passing as parameters. But that hides the dependency.
Decision needed: accept implicit uniform access (shorter signature) or pass
them explicitly (self-documenting but verbose)?
