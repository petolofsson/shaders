**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)  
**Task:** Use the **Brave Search MCP** to research zone-informed tone mapping and produce a drop-in upgrade for the FilmCurve block in `grade.fx` that uses all 16 spatial zone medians instead of 3 global pixel-histogram percentiles.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/grade/grade.fx`, `general/corrective/corrective.fx`

**Current FilmCurve** (`grade.fx`, lines 296–307):
```hlsl
float3 FilmCurve(float3 x, float p25, float p50, float p75)
{
    float knee    = lerp(0.90, 0.80, saturate((p75 - 0.60) / 0.30));
    float width   = 1.0 - knee;
    float stevens = (1.48 + sqrt(max(p50, 0.0))) / 2.03;
    float factor  = 0.05 / (width * width) * stevens;
    float knee_toe = lerp(0.15, 0.25, saturate((0.40 - p25) / 0.30));
    float3 above  = max(x - knee,      0.0);
    float3 below  = max(knee_toe - x,  0.0);
    return x - factor * above * above
               + (0.03 / (knee_toe * knee_toe)) * below * below;
}
```

Called as: `FilmCurve(pow(col.rgb, EXPOSURE), perc.r, perc.g, perc.b)` where `perc` is a 1×1 pixel-histogram percentile texture.

**ZoneHistoryTex** (4×4, RGBA16F) — contains `(median, p25, p75, 1.0)` per spatial zone (from `BuildZoneLevelsPS`). 16 zone medians are available but unused by FilmCurve.

**Problem:** p25/p50/p75 from the pixel histogram are biased toward large flat regions (sky, ground planes). Zone medians weight each spatial region equally — a better estimator of scene tonal structure.

**Philosophy:** SDR, linear light, Oklab. Gate-free. No new passes.

---

### 2. Autonomous Brave Search (The Hunt)

Search `arxiv.org`, `dl.acm.org`, `ieeexplore.ieee.org`, `color.org` for:

- **Reinhard 2002 log-average luminance:** Exact formula for geometric mean / log-average luminance as scene key estimator. Connection to Ansel Adams zone V (18% grey). `a/L̄_w` scale factor.
- **Zone system in digital tone mapping:** How spatial zone statistics (not histogram percentiles) are used to drive tone curves. Digital implementations of Adams zone system.
- **Monotone cubic spline for GPU tone curves:** Fritsch-Carlson / Steffen / Akima algorithms. Is a 16-point spline practical in HLSL/SPIR-V? Alternative: statistic-derived anchors.
- **Spatial luminance statistics for global tone curves:** How spatial averages (mean, std, min/max of zone medians) compare to histogram percentiles for tone curve parameterization.

---

### 3. Documentation

Output findings to `research/R16_filmcurve_zone_key_findings.md`. Address:

- **Scene key estimation:** Is the geometric mean of 16 zone medians a valid substitute for Reinhard's log-average luminance? What is the formula?
- **Anchor replacement:** Can zone min/max replace p25/p75 as knee/toe anchors? What calibration is needed?
- **Spread adaptation:** Can zone std dev modulate the FilmCurve factor to prevent over-compression of low-contrast scenes?
- **Spline viability:** Is a full 16-point monotone spline practical for HLSL/SPIR-V? Or is statistic-based parameterization the right approach for SDR?
- **SPIR-V compliance:** `log()`, `exp()`, `sqrt()` — PASS/FAIL. No `static const float[]`.
- **Cost:** How many extra instructions vs. current 3-sample approach?

---

### 4. Strategic Recommendation

Minimum viable R16 upgrade:
1. Compute geometric mean of 16 zone medians → use as p50 substitute (scene key, Reinhard 2002)
2. Compute zone min/max → blend with existing p25/p75 to improve toe/knee anchors
3. Compute zone std dev → scale FilmCurve factor for adaptive compression strength

Assess whether a full 16-point monotone spline through sorted zone medians is worth the sort-network cost (~56 comparators) for SDR content.

**Constraint:** All 16 zone reads must be at fixed UV coordinates (zone centers), not at the current pixel UV.
