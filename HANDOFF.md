# Handoff — 2026-05-18

> **Purpose (for AI context):** Current session state. Read at session start. Update at session end. Changelog entries go in CHANGELOG.md. **Hard limit: 60 lines including this header. Trim aggressively — one fact per line, no prose.**

## Active chain (testbed)
`analysis_frame : inverse_grade : corrective : grade`
grade: 11 passes — LFDownscale1 → LFDownscale2 → NeutralIllum → GuidedCoeff → GuidedBase → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion → **TexHwyWrite**

## Known state
- No compile errors. Log: `/tmp/vkbasalt.log`
- **Knob convention**: 0 = passthrough universally. 1 = full designed effect.
- **INVERSE_LUMA**: Mertens bell weight mu=0.05 sigma=0.18; proportional Oklab (L,a,b). mu range 0.05–0.20.
- **Halation**: luma-neutral orange `float3(0.316,−0.064,−0.294)`; sky_w exp gate (B>R factor 7.0).
- **CLARITY**: fully midtone-gated — `smoothstep(0.15,0.40,luma) × (1−smoothstep(0.60,0.85,luma))`.
- **LUMA_CONTRAST_***: 6-band hue-selective clarity, ungated, chroma-gated (smoothstep 0.04→0.10).
- **above_w**: restored — zone S-curve one-sided again (only lifts above zone median).
- **SHADOW_CAST**: gate smoothstep(0.40, 0.70).
- **3-way CC**: ±1.0 range. Scale 0.06 in shader. Oklab a/b (temp→b, tint→a).
- **DIR_COUPLER**: hardcoded 0.30 in shader (no knob).
- **R200 slow_key**: dual-rate EMA — K_slow=0.0000346 (T_half=20s), K_fast=0.01034 on scene cut.
- **R202 M_neg**: Kodak Vision3 500T sensitivity matrix; after EXPOSURE+halation, before FilmCurve.

## R203 Texture Highway — shipped 2026-05-18 (commit ce39e0e)
- **TexHwyTex**: BUFFER_WIDTH/8 × BUFFER_HEIGHT/8+5 RGBA16F, declared once in `common.fxh`.
- **Spatial lane** (rows 0..BUFFER_HEIGHT/8−1): pre-correction scene RGB+Luma, written by analysis_frame.
- **Data row +0** pixels 0-4: p25/p50/p75/P · p90/p10/p75_C/κ · MeanChroma · SceneCut+mode+entropy · NeutralIllum(grade→inv_grade, one-frame delay).
- **Data rows +1..+4**: ChromaHistoryTex 8×4 packed, written by corrective.
- **Eliminated**: CreativeLowFreqTex, PercTex (cross-effect), ChromaHistoryTex (cross-effect), NeutralIllumTex (cross-effect via name). ComputeLowFreqPS pass removed (−1 full BB read).
- **Behavioral**: low-freq source is now pre-inverse_grade (was post). Retinex/guided filter see pre-corrected signal.
- **ZoneLuma(uv)** helper in common.fxh — infrastructure for spatial zone gates; not yet used as pixel-L replacement.
- **Dead code audit done (2026-05-18)**: removed `CreativeZoneHistTex`/`CreativeZoneHistSamp` from grade.fx; corrected 6 stale comments across grade.fx and analysis_frame.fx referencing removed textures. 2×2 red activity indicator kept by choice.

## Next
- Dial SHADOW/MID/HIGHLIGHT TEMP/TINT on both profiles (knobs still at zero).
- Recalibrate BLEACH_BYPASS on both profiles.
