## Nightly Job A — System Stability Audit

**Schedule:** 04:00 daily  
**Output:** `/home/pol/code/shaders/research/R{next}N_{YYYY-MM-DD}_Nightly_Stability_Audit.md`  
where `{next}` = one more than the highest R-number found in `ls research/R*N_*.md` (e.g. if R25N exists, use R26N).  
**Branch:** commit and push output file to `alpha`.  
**Do not modify any source files.**

---

### Context — read these first

1. `/home/pol/code/shaders/CLAUDE.md` — pipeline constraints and architecture
2. `/home/pol/code/shaders/research/HANDOFF.md` — current pipeline state and all implemented Rx jobs
3. `/home/pol/code/shaders/gamespecific/arc_raiders/shaders/creative_values.fx` — all user knobs and their current values
4. `/home/pol/code/shaders/general/grade/grade.fx` — the MegaPass (`ColorTransformPS`) and all Stage 1–3 logic
5. `/home/pol/code/shaders/general/corrective/corrective.fx` — all 6 corrective passes including BackBuffer Passthrough
6. `/home/pol/code/shaders/general/analysis-frame/analysis_frame.fx` — histogram and percentile passes
7. `/home/pol/code/shaders/general/analysis-scope/analysis_scope_pre.fx`
8. `/tmp/vkbasalt.log` — read this if present; flag any ERROR or WARNING lines

---

### Task

Audit the shader chain for sources of **GPU instability, driver crashes, and performance degradation**. The game (Arc Raiders) has started crashing intermittently. Crashes did not occur before the R19–R22 implementation batch. The vkBasalt chain is the primary suspect. This job must produce a prioritised risk map.

#### A. Register pressure — `ColorTransformPS` (grade.fx)

Count the distinct local variables declared inside `ColorTransformPS`. Group them by type (float, float2, float3, float4, int, bool). Estimate total scalar register usage (float3 = 3 scalars, float4 = 4, etc.). Flag if total exceeds 128 scalars — this is the threshold where many Vulkan drivers begin register spilling, which causes severe slowdowns and occasional crashes on integrated or mid-range GPUs.

Identify the top 5 largest variable groups by type. Note any variables that are written once and could be folded into the expression that consumes them.

#### B. Unsafe math sites

Scan all files listed above for operations that can produce NaN or INF without a guard:

- `log(x)` or `log2(x)` where `x` could be ≤ 0 — check histogram accumulation, zone median computation
- `pow(x, y)` where `x` could be negative — check EXPOSURE application
- `x / y` where `y` could be zero — check percentile normalization, zone IQR division, chroma C division
- `sqrt(x)` where `x` could be negative — check Oklab conversion
- `atan2(0, 0)` — check hue computation from (a, b) = (0, 0) i.e. achromatic pixels

For each site found: report file, line number, the expression, and the specific condition under which it goes unsafe. Rate severity: **CRASH** (NaN reaches render target), **CORRUPT** (wrong value propagates silently), **BENIGN** (clamped before output).

#### C. BackBuffer row guard — y=0 data highway

The pipeline stores analysis data in row y=0 of the BackBuffer (written by `analysis_scope_pre.fx`, read by downstream passes). Every pass that writes BackBuffer must contain the guard `if (pos.y < 1.0) return col;` before writing.

List every pixel shader in corrective.fx and grade.fx that writes to BackBuffer. For each, confirm whether the guard is present and correctly positioned (must be before any write, not just at the top of the function). Flag any missing or misplaced guards as **CRITICAL**.

#### D. Temporal history — accumulation safety

The zone and chroma history textures use exponential moving averages. Confirm:
- All EMA blending uses a coefficient in (0, 1) — a coefficient of exactly 0 or 1 would freeze or discard history
- History textures are declared with bounded formats (RGBA16F, R16F) — flag any RGBA32F as unnecessary precision + memory
- No texture is sampled before it has been written at least once (cold-start frame)

#### E. New since R19 — targeted review

The R19–R22 batch introduced the most complex recent changes. Specifically audit:
- R21 hue rotation: the 2×2 rotation matrix applied to (lab.y, lab.z) — does it correctly handle the zero-chroma case (C=0) without introducing NaN via the sincos path?
- R22 sat-by-luma: the chained `saturate()` expression — confirm it cannot produce negative C
- R19 3-way corrector: the temp/tint-to-RGB conversion — confirm it cannot push linear values below 0 or above 1 before Stage 2

---

### Output format

```
# Nightly Stability Audit — {YYYY-MM-DD}

## Summary
{2–3 sentence overall risk assessment}

## A. Register pressure
- Total estimated scalars in ColorTransformPS: {N}
- Risk level: LOW / MEDIUM / HIGH / CRITICAL
- {findings}

## B. Unsafe math sites
| File | Line | Expression | Unsafe condition | Severity |
|------|------|------------|-----------------|----------|
...

## C. BackBuffer row guard
| Pass | File | Line | Guard present? |
|------|------|------|---------------|
...

## D. Temporal history
{findings}

## E. R19–R22 targeted review
{findings}

## Priority fixes
1. {highest severity issue — file:line, specific fix}
2. ...
```

---

### After writing the output file

```bash
cd /home/pol/code/shaders
git checkout alpha
git add research/R*N_*_Nightly_Stability_Audit.md
git commit -m "nightly: stability audit {YYYY-MM-DD}"
git push origin alpha
```
