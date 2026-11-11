# Current state — 2026-11-11

Goal and priorities: [GOAL.md](GOAL.md), [PLAN.md](PLAN.md). Earlier full text of this file:
[2026-11-11 ledger](research/2026-11-11_root_document_history.md) (older:
[11-10](research/2026-11-10_root_document_history.md), [11-08](research/2026-11-08_root_document_history.md),
[11-06](research/2026-11-06_root_document_history.md)). No runtime is active.

## Production

Both configs run one combined `ShaderPipeline` (40 passes; grade's share is 24).
Stage contracts: [docs/pipeline.md](docs/pipeline.md). Knob values: read the profiles
(`gamespecific/*/shaders/creative_values.fx`); docs do not copy them.

Adopted 2026-11-11 ([CHANGELOG](CHANGELOG.md)):
- **Light-aware CC:** `KEY_WARMTH` (warm mid/highlight only when the frame shows a warm key
  against cool fill) and `SHADOW_FILL_FOLLOW` (shadow CC only where shade reads cooler than
  adjacent sunlit surfaces). Both use the light-map sun-edge cue `sun_key` and default to 0
  (production bit-identical). The GZW profile uses them (user live-play choice); Arc does not yet.
- **Cost:** shader cost on GZW ~2.2 → ~1.15 ms (user FPS 92/115 → ~100/113, shader on/off).
  Main win: `OklabToSDR` returns in-gamut colours directly (user-authorized output-preserving
  branch, CODE_RULES). Other cuts are bit-identical or ≤ 1 code
  ([cost report](research/2026-11-11_cost_reduction.md)).

Identity (SHA-256 prefixes, 2026-11-11): `grade.fx` a02b5865e145d052, `light_map.fxh`
d880e0bfa2e07539, `pipeline.fx` bff2ecac020d30fc, `analysis_frame.fx` ffd93491d824d6af,
`corrective.fx` 932ce5274f20b0a9, `inverse_grade.fx` 8abe46d485d8f037, `common.fxh`
aa18c3fbf5e25ad9. Configs unchanged. Match identities before reusing evidence.

## Open

- **Look target** (user, 2026-11-11): mock `mix_tsb`. Live GZW sun: sunlit wall cream (on
  target); shade still reads cyan-grey at the current shadow CC strength (house 193054: front
  wall 73 89 89, shaded hill foliage 32 48 48). A shader-off screenshot of the same view is
  needed to separate paint/sky fill from our tint. Unreached by knobs: far-hill haze (needs
  depth), sky vs shade hue, dark-foliage lift ([look target](research/2026-11-11_look_target.md)).
- **Live play of the new cue:** pan breathing of warmth/shade colour (offline mid-ramp wobble
  ~25% of the effect); warm-lamp interiors read as sun. Fix if seen: denser cue sampling.
  Arc: the cue missed one sun frame (211131); the knobs are untried on the Arc profile.
- **Blue-cusp overshoot:** the analytic inverse-grade gamut limit is up to .047 C too high for
  ~.016% of colours (hue ≈ −96°, L ≈ .45); `OklabToSDR` still projects those. Watch strong blues.
- **Further cost options** (each ≤ ~0.15 ms): 25-tap tonal neighbourhood at 1/8 (changes the
  image, needs pan check); rounding-only bundle (surround-tint skip on lit pixels, Oklab
  round-trip merges, dither re-encode).
- **Earlier live-play items:** shadow-edge crawl in slow pans; Arc menu UI patches (≤ 1.4% px);
  soft patch beside the rifle on Arc 211202 (.03% px, light-map coarse correction).
- **Forest-edge dark green line** (GZW): the shader does not darken tree lines on 133729; the
  line is most likely game haze. The user keeps `SAT_GREEN` 0.
- **Settled look:** judge absolute strengths only on settled captures
  ([recheck](research/2026-11-10_settled_capture_recheck.md)).

## Parked

See PLAN "Closed". Motion/temporal work stays unwired
([checkpoint](research/2026-11-07_motion_brightness_prototype.md)).

Captures, scripts and media stay local and ignored.
