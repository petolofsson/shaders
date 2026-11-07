# Shadow-gradient refinement — 2026-11-05

**Decision: do not adopt.** The user requested improving the rejected shadow-gradient candidate. A smooth source-luminance window largely protects its shelf and sky regressions, but the refined candidate reduces selected Arc dark-metal and cool-upper shadow separation. The measured gain is mixed and no clear cross-scene visual improvement is established. No production shader, profile, config or score changed.

The [original candidate](2026-11-05_shadow_gradient_screen.md) uses a scene-key anchored S-shaped luminance redistribution. The isolated refinement multiplies that term by `smoothstep(0.004,0.020,source_Y) * (1-smoothstep(0.080,0.150,source_Y))`; source Y is reconstructed from the existing `NativeGuideLogTex`, which floors luma at 0.001. Deep shadow and bright source pixels thus fade toward the existing production response. This is pixel-dependent smooth arithmetic, without a new history, pass or user control. The gating itself can alter slope and makes no guarantee that all dark shades improve or that boundaries remain unobtrusive.

| Source-selected region | Metric | Current | First candidate | Refined |
|---|---|---:|---:|---:|
| GZW shelf | median L | 15.735 | 14.062 | 15.735 |
| GZW shelf | fixed source-quartile L gap | 2.661 | 2.269 | 2.657 |
| Arc dark metal | L gap | 8.981 | 8.910 | 8.320 |
| Arc dark metal | relative log-Y gap, stops | 1.949 | 2.064 | 1.821 |
| Arc cool upper | L gap | 20.385 | 19.650 | 19.650 |
| Arc cool window | L gap | 31.973 | 33.851 | 32.550 |
| GZW-profile vivid blue sky | L gap | 10.567 | 9.076 | 10.590 |

These are source-selected measurements, not quality scores. The refined metal L gap falls about 7.4% relative to current; the cool-window gap improves about 1.8%. Shelf and sky values are restored in these selected regions. Native crops show little obvious improvement; visual user preference was not measured. Arc vivid content with a GZW profile is not a third game.

All four candidate/repeat pairs (GZW dark, Arc interior, Arc emitter, GZW-profile vivid) are pixel-identical after masking the 2x2 marker. Eight fresh private headless processes report zero dropped/delayed frames. Current production hashes were unchanged before and after; captured isolated config and shader file hashes were verified. Existing current baselines and first-candidate images retain their recorded source/profile/config epochs. Full-image maxima versus current are 3/6/4/18 codes for those scenes; no additional all-channel-black pixels were counted, which does not prove near-black gradient preservation. Runtime settling was 20 seconds and does not prove convergence or motion stability.

For context only, a CPU scalar test assumes `source_Y == new_luma` and fixed anchors 0.04, 0.08, 0.12, 0.20, 0.40; minimum numerical derivatives of the windowed mapping are approximately 0.64, 0.457, 0.406, 0.482 and 0.64. This does not prove monotonicity of the actual pipeline, where source and corrected luma differ and the adaptive anchor moves. No GPU numerical/zero-bypass contracts, native transition charts, measured motion/cut or actual-config adoption validation were performed. This mixed early result does not justify production adoption or another parameter sweep. Scripts, captures, identities and native comparisons are ignored local artifacts in `captures/shadow_gradient_refined_20261105/`.
