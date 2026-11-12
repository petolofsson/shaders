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
- **Skyline crown fade:** the surround tint's vertical blur takes sky above shade at a weak,
  long triangle (.30, reach 28 at 1/16), so tree crowns under skylines keep a deeper green that
  fades over ~225 px (user choice D, live-played and accepted;
  [tree line](research/2026-11-11_treeline.md)). Tilt-stable; independent of cloud vs blue sky.
  At night the tint fades out with near-black surroundings (luma .002–.008), removing a dark
  sky-tinted band under night ridgelines (user live play; day ≤ 3 codes).
- **Shade neutralize:** `SHADOW_NEUTRALIZE` removes the measured fill-vs-key tint from shade before
  the shadow CC, toward neutral only (default 0; GZW profile 1).
- **One highlight shoulder:** the film curve (before the SDR projection, keeps near-white colour)
  is the only shoulder; print stock keeps its toe and look. `FILM_CURVE` is a grade.fx default
  (.70) and left the GZW profile; Arc still sets it.
- **GZW brightness (user):** `EXPOSURE` and `SHADOWS` changed together so mids/brights rise
  slightly while deep shadows stay.
- **Cost:** shader cost on GZW ~2.2 → ~1.15 ms (user FPS 92/115 → ~100/113, shader on/off).
  Main win: `OklabToSDR` returns in-gamut colours directly (user-authorized output-preserving
  branch, CODE_RULES). Other cuts are bit-identical or ≤ 1 code, including the follow-up
  (chroma Oklab straight to the SDR projection, dither written sRGB-encoded)
  ([cost report](research/2026-11-11_cost_reduction.md)).

Identity (SHA-256 prefixes, 2026-11-11): `grade.fx` c1223b5eed6666d3, `light_map.fxh`
30a9f807c7d31cd1, `pipeline.fx` ddbe26f2ecf2e839, `analysis_frame.fx` ffd93491d824d6af,
`corrective.fx` 932ce5274f20b0a9, `inverse_grade.fx` 8abe46d485d8f037, `common.fxh`
4c0b810a9e820f6f. Configs unchanged. Match identities before reusing evidence.

## Open

- **Look target** (user, 2026-11-11): mock `mix_tsb`. Live GZW sun: sunlit wall cream (on
  target). Shade cyan came from the game fill plus our shadow CC; `SHADOW_NEUTRALIZE` 1 (GZW
  profile) removes the measured fill tint before the CC (172413 shade wall b −2.7 → −1.8, target
  −1.5). In live play since 11-11, no issue reported; not pan-checked. Dark chroma still above target. Unreached by knobs: far-hill haze (needs
  depth), sky vs shade hue, dark-foliage lift ([look target](research/2026-11-11_look_target.md)).
- **Live play of the new cue:** pan breathing of warmth/shade colour (offline mid-ramp wobble
  ~25% of the effect); warm-lamp interiors read as sun. Fix if seen: denser cue sampling.
  Arc: the cue missed one sun frame (211131); the knobs are untried on the Arc profile.
- **Blue-cusp overshoot:** the analytic inverse-grade gamut limit is up to .047 C too high for
  ~.016% of colours (hue ≈ −96°, L ≈ .45); `OklabToSDR` still projects those. Watch strong blues.
- **Further cost options** (each ≤ ~0.15 ms): 25-tap tonal neighbourhood at 1/8 (changes the
  image, needs pan check); surround-tint skip on lit pixels (outside the branch exception);
  CC → tonal Oklab merge. User FPS after the follow-up not yet read.
- **Tree-line side fade:** only the vertical tint blur has the long taper; crowns with sky beside
  them may still fade abruptly sideways. Act only if seen in play.
- **Arc `FILM_CURVE`:** the Arc profile still sets .6; removing it would use the .70 default
  (small highlight change, capture first).
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
