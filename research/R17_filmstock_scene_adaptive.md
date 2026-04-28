**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)  
**Task:** Use the **Brave Search MCP** to research film stock sensitometric behavior and produce a scene-adaptive upgrade to the film grade presets in `grade.fx` that modulates tint balance based on scene exposure state.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/grade/grade.fx`, `gamespecific/arc_raiders/shaders/creative_values.fx`

**Current film grade stage 4** (`grade.fx` lines 536–599):
- Log-space color matrix per preset (`FILM_RG`, `FILM_GR`, etc.) — fixed cross-channel coupling
- Per-preset tinting: `TOE_TINT`, `SHADOW_TINT`, `HIGHLIGHT_TINT` — all fixed magnitudes
- Chilliant gamma curve (sqrt chain)
- Gate: `fm_gate` on chroma+luma for film matrix activation

**Problem:** All tint contributions are fixed regardless of scene brightness. Real film stocks have characteristic curves where the color cross-over point (where shadow tint meets highlight tint) shifts with exposure rating. A bright scene has more highlight-character content; a dark scene has more shadow-character content.

**Scene exposure state available from R16:**
- `zone_log_key` = geometric mean of 16 zone medians = Reinhard scene key estimator
- Zone V (18% grey, normal exposure) = 0.18

**Philosophy:** SDR, linear light. Gate-free. No new passes. `creative_values.fx` is the only tuning surface.

---

### 2. Autonomous Brave Search (The Hunt)

Search Kodak/Fuji technical data sources, `arxiv.org`, `cinematography.com`, `filmmaker.com` for:

- **Kodak Vision3 sensitometric data:** Per-channel (cyan/magenta/yellow layer) D-log E curves. Are the per-layer gammas different? How does the color cross-over shift at different EI ratings?
- **Fuji Eterna 500 sensitometric curves:** Same questions. Known for flat/cool character.
- **Film cross-over shift with exposure:** How does the warm-highlight/cool-shadow cross-over point change when a film stock is over- or under-exposed? Is this documented in EV or density units?
- **Digital film emulation exposure adaptation:** Any shader or DCTL that adapts film stock behavior based on scene key. Open-source implementations (Filmulator, darktable filmic, Thatcher Freeman DCTLs).
- **Per-channel gamma differences:** For Kodak Vision3 family, what is the measured difference between R, G, B layer gammas? Is this 0.03–0.08 range documented?

---

### 3. Documentation

Output findings to `research/R17_filmstock_scene_adaptive_findings.md`. Address:

- **Cross-over mechanism:** What physical mechanism causes the warm/cool cross-over in film stocks? Is it per-layer gamma difference, shoulder behavior, or dye density?
- **Exposure dependence formula:** How does the cross-over shift with scene key? Linear in stops? Power law?
- **Per-stock scale factors:** Propose a `TINT_ADAPT_SCALE` value for each of the 6 presets. Cite sources or clearly flag as empirical.
- **Alternative: per-channel gamma offset:** If per-channel gamma data is available, propose a luminance-dependent channel offset instead of tint scaling.
- **SPIR-V compliance:** `log2()` — PASS/FAIL.
- **Injection point:** The tinting block in stage 4 (grade.fx, after Chilliant gamma).

---

### 4. Strategic Recommendation

Minimum viable R17 upgrade:
1. Compute `r17_stops = log2(zone_log_key / 0.18)` — stops above/below normal exposure
2. Scale highlight tint by `1 + TINT_ADAPT_SCALE * saturate(+r17_stops)` for bright scenes
3. Scale shadow/toe tint by `1 + TINT_ADAPT_SCALE * saturate(-r17_stops)` for dark scenes
4. Per-preset `TINT_ADAPT_SCALE` constants matched to each stock's cross-over strength

Assess whether per-channel gamma offsets (requiring raw sensitometric data) are achievable or whether tint scaling is the right level of fidelity given data availability.

**Constraint:** `zone_log_key` is computed in stage 1 (R16 block) and available as a shader variable throughout ColorTransformPS.
