# Pipeline Changelog

Session history extracted from HANDOFF.md. Most recent first.

---

## 2026-04-30 (session 2)

### Nightly job spec fixes
- Output naming: both jobs now use `R{next}N_{YYYY-MM-DD}_{topic}.md` convention
- Both jobs commit and push output to `alpha` branch
- `SPATIAL_NORM_STRENGTH` removed from automation job candidates (already done)

### Stability audit — R25N (local, alpha branch)
- Previous R25N (nightly run on wrong branch) deleted and re-run locally
- No CRASH or CORRUPT findings on actual alpha codebase
- Register pressure: `ColorTransformPS` ~129 scalars, at 128-scalar spilling threshold
- All BackBuffer row-0 guards correct; all EMA coefficients in range; R19–R22 safe

### Shader fixes (from R25N findings)
- X3206 warnings suppressed: all 8 `DrawLabel` call sites now pass `pos.xy` (was `pos`)
  — analysis_frame.fx, analysis_scope_pre.fx, analysis_scope.fx, corrective.fx (×3),
    grade.fx, pro_mist.fx
- Histogram textures: LumHistRaw, SatHistRaw, LumHist, SatHist — R32F → R16F
  in analysis_frame.fx (values are [0,1] fractions; R32F was unnecessary)

### Research filed
- `R25N_2026-04-30_Nightly_Stability_Audit.md` — full stability audit on alpha
- `R26N_2026-04-30_Register_Pressure_Research_Proposal.md` — research proposal:
  does `[unroll]` loop restructure of 16 zone reads actually reduce SPIR-V register
  pressure, or is it compiler-dependent? Pending execution next session.

---

## 2026-04-30

### SPATIAL_NORM_STRENGTH automated
`SPATIAL_NORM_STRENGTH` removed from `creative_values.fx` (arc_raiders + gzw).
`grade.fx:284` now derives r18_str from zone_std:
```hlsl
float r18_str = lerp(10.0, 30.0, smoothstep(0.08, 0.25, zone_std)) / 100.0 * 0.4;
```
Complementary to existing zone_str automation — contrasty scenes get stronger
normalization while getting a gentler S-curve, preventing double-amplification.
23 knobs remain.

### Nightly job fixes
- All three triggers: `git config user.email/name` + `git push origin HEAD:alpha`
- Stability audit + Automation research: `git checkout alpha` added at job start
  (jobs were running against `main` — wrong codebase)
- Automation research: Brave curl + arxiv search pattern added

### Research filed
- `R24N_2026-04-30_Nightly_Automation_Research.md` — 5-knob automation formulas

---

## 2026-04-29 (night)

### GZW fully configured
- Rewrote `gzw.conf` to mirror arc_raiders structure
- Created `gamespecific/gzw/shaders/creative_values.fx` and `debug_text.fxh`
- GZW chain: `analysis_frame:analysis_scope_pre:corrective:grade:pro_mist:analysis_scope`

### Debug label system extended
- Added '8' glyph to both `debug_text.fxh`: `if (ch == 56u) return 34287u;`
- Slots: 1ANL / 2SCP / 3COR+4ZON+5CHR (passthrough) / 6GRA / 7PMS / 8SCO
- analysis_scope moved from slot 7 (y=58) to slot 8 (y=66)

### pro_mist — new effect (R23N)
Physical model: Black Pro-Mist glass filter. Additive chromatic scatter (R>G>B).
Single pass, reads `CreativeLowFreqTex` as scatter source.
- `adapt_str = 0.36 * lerp(0.7, 1.3, saturate(iqr / 0.5))` — IQR-adaptive
- Gate onset from p75: `smoothstep(p75-0.12, p75+0.06, luma_in)`
- Additive: `base + max(0, diffused-base) * float3(1.15, 1.00, 0.75) * adapt_str * gate`
- Clarity component: `base - diffused` × bell × adapt_str × 1.10
**Constraint:** Must stay single-pass — see arc_raiders game-specific notes in HANDOFF.

### Bug fixes
1. `corrective.fx` kHalton — `static const float2 kHalton[256]` replaced with
   procedural `Halton2(uint)` / `Halton3(uint)` (SPIR-V-safe). Chroma stats now correct.
2. `analysis_scope_pre.fx` SCOPE_S — 16→8 (matches analysis_scope.fx).
3. Stage 4 (FILM GRADE) removed — dead code at GRADE_STRENGTH=0.
