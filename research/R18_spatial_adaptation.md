**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)  
**Task:** Use the **Brave Search MCP** to research spatial tone mapping methods and determine how to apply per-zone local exposure normalization using the existing 4×4 zone grid — without block artifacts and without adding new passes if possible.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/grade/grade.fx`, `general/corrective/corrective.fx`

**Current zone usage in stage 2** (`grade.fx`):
```hlsl
float4 zone_lvl   = tex2D(ZoneHistorySamp, uv);   // per-pixel zone lookup
float zone_median = zone_lvl.r;
// PivotedSCurve around zone_median — boosts within-zone contrast
float bent     = dt + (ZONE_STRENGTH / 100.0) * iqr_scale * dt * (1.0 - saturate(abs(dt)));
float new_luma = saturate(zone_median + bent);
```

**ZoneHistoryTex:** 4×4 RGBA16F, sampled with `MinFilter = LINEAR; MagFilter = LINEAR`.

**Problem:** The zone S-curve increases local contrast within each zone (bends luma around zone_median) but does NOT normalize the absolute luminance between zones. A dark zone at median 0.10 and a bright zone at median 0.70 both get S-curves around their respective medians — the overall luminance disparity between zones is unchanged.

**Scene key available from R16:**
- `zone_log_key` = geometric mean of all 16 zone medians (globally unbiased scene key)
- Represents the "correct" Zone V target for this scene

**Philosophy:** SDR, linear light. Gate-free. Ideally no new passes. Halo-free.

---

### 2. Autonomous Brave Search (The Hunt)

Search `arxiv.org`, `dl.acm.org`, `graphics.cs.yale.edu`, `graphics.ucsd.edu` for:

- **Reinhard 2002 local operator:** Exact formula for per-pixel local adaptation luminance `V(x,y)`. How is the adaptation scale chosen to prevent halos? Center-surround Gaussian.
- **Halo prevention in local tone mapping:** What are the necessary and sufficient conditions (monotonicity, smoothness of V) to prevent halos? Literature 2002–2024.
- **Low-resolution luminance map for local tone mapping:** Has anyone used a coarse (4×4 or 8×8) luminance map for spatial adaptation in real-time rendering? What blending strategy prevents visible block boundaries?
- **Bilinear texture sampling as spatial blur:** Is bilinear interpolation of a 4×4 texture sufficient spatial smoothing for avoiding tone-mapping artifacts? What frequencies does it suppress?
- **Power-law local adaptation:** Any local tone mapping formulation using fractional power `(L/V)^k` instead of Reinhard's `L/(1+V)`? More suitable for SDR (gentler compression).

---

### 3. Documentation

Output findings to `research/R18_spatial_adaptation_findings.md`. Address:

- **Reinhard local operator formula:** `Ld = L / (1 + V)`. How does it connect to our zone medians?
- **New pass requirement:** Is a new pass needed, or does bilinear sampling of the 4×4 ZoneHistoryTex provide sufficient spatial smoothness?
- **Halo analysis:** For a zone median ratio of 4:1 (dark:bright adjacent zones), does bilinear interpolation of a 4×4 grid prevent visible halos? What is the spatial frequency cutoff?
- **Normalization formula:** Propose a gate-free, SPIR-V-safe formulation that pulls each pixel's zone median toward `zone_log_key`. Power-law preferred over linear for SDR.
- **Strength calibration:** Default strength for subtle spatial balancing. What is the maximum safe strength before the image looks flat?
- **SPIR-V compliance:** `pow(x, y)` with positive args — PASS/FAIL.

---

### 4. Strategic Recommendation

Anticipated minimum viable R18 upgrade (verify with research):
1. After zone S-curve computes `new_luma`, apply: `new_luma *= pow(zone_log_key / zone_median, strength * 0.4)`
2. This pulls dark zones toward the global key (brightening) and bright zones away (darkening)
3. Bilinear interpolation of zone_median at full-res UV may provide sufficient spatial smoothness
4. `SPATIAL_NORM_STRENGTH` knob in creative_values.fx (default 20)

**Key research question:** Does the existing LINEAR sampler on ZoneHistoryTex + 4×4 resolution provide sufficient spatial smoothing, or is a separate blur/blending pass needed?

**Constraint:** No hard conditionals on pixel properties (no gate on zone_median range). Output must be bounded [0,1].
