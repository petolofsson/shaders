# Pipeline Plan

Tracks implementation and validation. Earlier completion/novelty percentages were
subjective estimates, not measured fidelity scores.

| Stage | Implemented | Remaining validation |
|-------|-------------|----------------------|
| Input / inverse-grade | Local max-channel protection plus global near-clip history; bounded chroma expansion; inverse chroma changed a bright real-game stress input by 0.15 ΔE | GZW-specific vivid objects, reconstruction assumptions, small emitters |
| Corrective / FilmCurve | Explicit linear processing, internal range retention, zero-preserving DIR/tint, corrected shoulder; fixed-endpoint GZW corrective gate 2.38 ΔE, Arc bright-cloud FilmCurve 0.15 ΔE | GZW broad highlights and empirical strength calibration |
| Tonal | Corrected Retinex reconstruction, independent gates, spatial confidence, time-based selective adaptation; GZW tonal gate 1.51 ΔE and dark shadow lift 2.35 ΔE | Halos, real motion, longer transition recovery |
| Color | Corrected chroma normalization and two-sided Oklab gamut projection; GZW chroma gate 0.97 ΔE | Hue continuity, GZW saturation, GPU cost |
| Look | Print stock and dye/masking controls; GZW look gate 2.94 ΔE | Live preference and scene-specific print strength |
| Output | Explicit sRGB encode, endpoint-preserving code-domain dither, marker; runtime endpoints and marker checked | Display quantization and gradients in-game; noise-floor measurement |
| Diagnostics | Continuous lossless RGB playback, private IPC/logs, serial access, equal gates, repeat baseline, source hashes, cut probe | Direct offscreen highway readback and live game/performance capture |

## Current Priorities

1. Review the combined GZW trial live before changing `gzw.conf`; the four-effect config still loses cross-effect data.
2. Capture bright saturated GZW objects, broad highlights, emitters, and actual motion; use matched raw/graded captures for hue, halos, and transitions.
3. The user reports roughly a 10 FPS in-game cost and accepts it. Prioritize visual verification; profile GPU time only if performance becomes a concern.
4. Use `tools/noise_floor.py` on matched renders when evaluating dither and quantization changes.
5. Recalibrate profiles only from matched current captures; preserve user values until testing supports a change. Current GZW BLACKS is 0.0; do not reuse earlier BLACKS=0.05 conclusions.

Current run details and exact JSON artifacts: [research/2026-10-24_stage_verification.md](research/2026-10-24_stage_verification.md).

## Scoring Discipline

- Directional constants should be literature-backed where possible.
- Amplitudes and blend endpoints are allowed to be empirical, but must be tested.
- Do not inflate novelty for standard concepts such as exposure, saturation,
  bloom, LUT-like color shifts, or removed optical finishing effects.
- Prefer effect-attribution data over theoretical confidence when stages interact.
