# Consolidation Plan: corrective + grade merge + naming

## Target effects line
```
analysis_frame : analysis_scope_pre : corrective : grade : analysis_scope
```

---

## Phase 1 — Naming only (zero functional risk)

1. Rename `general/analysis-frame-analysis/analysis_frame_analysis.fx` → `general/analysis-frame/analysis_frame.fx`
2. Rename `general/creative-color-grade/creative_color_grade.fx` → `general/grade/grade.fx`
3. Update `arc_raiders.conf`: paths + keys + effects line
4. Test — output must be identical before proceeding

---

## Phase 2 — Build `general/corrective/corrective.fx`

Merge from: `corrective_render_chain.fx`, `creative_render_chain.fx`, `olofssonian_chroma_lift.fx`

### Includes & defines (no duplicates)
- `debug_text.fxh`, `creative_values.fx`
- `ZONE_LERP_SPEED 8`, `LERP_SPEED 8`, `BAND_WIDTH 8`, `MIN_WEIGHT 1.0`, `SAT_THRESHOLD 2`
- All 6 `BAND_*` hue positions

### Uniform
- `FRAME_COUNT` (from olofssonian_chroma_lift)

### Textures — declared once
- `BackBufferTex / BackBuffer`
- `CorrectiveSrcTex` (RGBA16F, full res)
- `CreativeLowFreqTex` (RGBA16F, 1/8 res)
- `CreativeZoneHistTex` (R16F, 32×16)
- `CreativeZoneLevelsTex` (RGBA16F, 4×4)
- `ZoneHistoryTex` (RGBA16F, 4×4)
- `ChromaHistoryTex` (RGBA16F, 8×4)

### One PostProcessVS

### Helpers (each once)
- `Luma()` — from creative_render_chain
- `RGBtoOklab()`, `OklabHueNorm()`, `HueBandWeight()`, `GetBandCenter()` — from olofssonian_chroma_lift

### Halton table
- Move `static const float2 kHalton[256]` as-is
- Risk: CLAUDE.md warns static const float[] / float3 broken in SPIR-V. float2 array currently works — verify output immediately after Phase 2

### Pixel shaders in pass order
1. `CopyToSrcPS` — BB → CorrectiveSrcTex
2. `ComputeLowFreqPS` — BB → CreativeLowFreqTex (reads BB = previous frame's grade)
3. `ComputeZoneHistogramPS` — CreativeLowFreqTex → CreativeZoneHistTex
4. `BuildZoneLevelsPS` — CreativeZoneHistTex → CreativeZoneLevelsTex
5. `SmoothZoneLevelsPS` — CreativeZoneLevelsTex → ZoneHistoryTex
6. `UpdateHistoryPS` — BB → ChromaHistoryTex (must run before CopyFromSrcPS while BB = previous frame)
7. `CopyFromSrcPS` — CorrectiveSrcTex → BB (new; cheap blit; keeps BB non-black; replaces 3 Passthroughs)

### Technique
- One technique, 7 passes, no Passthrough passes

---

## Phase 3 — Switchover

1. Add `corrective` to conf alongside the 3 old effects (do not remove old yet)
2. Run both in parallel temporarily to confirm identical output via scope
3. Remove the 3 old entries from effects line

---

## Phase 4 — Cleanup

1. Delete `general/corrective-render-chain/`
2. Delete `general/creative-render-chain/`
3. Delete `general/olofssonian-chroma-lift/`
4. Update `CLAUDE.md`: key paths table, chain description, pass order docs

---

## Risk register

| Risk | Mitigation |
|---|---|
| `static const float2 kHalton[256]` SPIR-V behaviour | Check chroma output immediately after Phase 2 |
| Texture sharing between corrective.fx and grade.fx | Shared by name — intentional; verify ZoneHistoryTex + ChromaHistoryTex round-trip |
| `BAND_WIDTH` is 8 in corrective, 14 in grade.fx | Separate files = separate preprocessor namespaces, no conflict |
| `UpdateHistoryPS` reads BB — must run before CopyFromSrcPS | Enforced by pass order |
| Debug labels from 3 Passthroughs collapse to 1 | Intentional; update or drop label in CopyFromSrcPS |
