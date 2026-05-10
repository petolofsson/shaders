// creative_values.fx — tune here

// ── INPUT ─────────────────────────────────────────────────────────────────────
// Adaptive inverse tone mapping. Expands Oklab chroma using the IQR-derived compression
// ratio — restoring chroma the game's tonemapper compressed. Luma is handled by zone
// S-curve. Works on any S-curve tonemapper. 0 = off. Start at 0.30–0.50.
#define INVERSE_STRENGTH  0.50

// ── CORRECTIVE ────────────────────────────────────────────────────────────────
// Applied as pow(rgb, EXPOSURE) before any zone or curve work.
// Sets where pixels sit tonally — which directly changes what every knob below "sees".
// Raising this (>1.0) darkens; lowering (<1.0) brightens.
// Rule of thumb: dial EXPOSURE until overall brightness feels right, then tune beneath.
#define EXPOSURE  0.85

// Remaps the raw pixel into [FILM_FLOOR, FILM_CEILING] before EXPOSURE runs.
// FILM_FLOOR: black pedestal — prevents absolute digital black. 0 = off.
//   0.005 matches actual linear-light value at the ARRI LogC3 black point.
// FILM_CEILING: white headroom — pulls true white below clip before EXPOSURE.
//   0.95 matches ARRI LogC3 usable ceiling (~91-92% of full scale).
// Both at defaults (0 / 1) = passthrough (identity).
#define FILM_FLOOR    0.005
#define FILM_CEILING  0.97

// Developer-inhibitor-release cross-channel masking. Each dye layer releases
// inhibitors that suppress adjacent layers, increasing colour separation.
// Fires after EXPOSURE, before FilmCurve — pure SDR-log effect.
// 0 = off (default). 0.3 = subtle. 0.6 = visible colour pop. 1.0 = strong.
#define COUPLER_STRENGTH  0.3

// Per-channel knee and toe offsets for the FilmCurve. Encodes the physical dye-layer
// cross-over character of different film stocks.
// Default values match ARRI ALEXA latitude. Range approximately ±0.015.
// R knee < 0 = red compresses earlier (film-like warm shadows).
// B knee > 0 = blue compresses later (open highlights). B toe < 0 = cool toe.
#define CURVE_R_KNEE  -0.0102
#define CURVE_B_KNEE   0.0000
#define CURVE_R_TOE   +0.0100
#define CURVE_B_TOE   -0.010

// Kodak 2383 print emulsion on top of FilmCurve: lifts blacks, compresses
// highlights, desaturates mids ~15%, adds warm shadow cast. 0 = off.
// 1 = full 2383. 0.35 = recommended starting point.
#define PRINT_STOCK  0.50

// Skip the bleach step during print development — retains metallic silver alongside
// color dye. Desaturates shadows most (denser silver retention in unexposed areas),
// steepens midtone contrast, adds grit. Se7en, Saving Private Ryan, Traffic.
// 0 = off. 1 = full (near-monochrome shadows). Start: 0.1–0.3.
#define BLEACH_BYPASS  0.10

// Primary color grade. Runs after FilmCurve, before zone contrast.
// TEMP: positive = warm (R up, B down), negative = cool. Range ±100.
// TINT: positive = magenta (G down, R+B up slightly), negative = green. Range ±100.
// All default to 0 — passthrough. No output change at defaults.
#define SHADOW_TEMP     -5
#define SHADOW_TINT      0
#define MID_TEMP        +3
#define MID_TINT         0
#define HIGHLIGHT_TEMP  +8
#define HIGHLIGHT_TINT   0

// ── TONAL ─────────────────────────────────────────────────────────────────────
// Scales the adaptive zone S-curve strength. 1.0 = calibrated default. 0 = off.
// 2.0 = aggressive. Range 0–2.
#define ZONE_STRENGTH  1.10

// Scales the auto shadow lift. 1.0 = calibrated default. 0 = off.
// Raise for dark games with poor visibility, lower if lift feels too aggressive.
#define SHADOW_LIFT_STRENGTH  1.5

// ── CHROMA ────────────────────────────────────────────────────────────────────
// Master scalar for per-hue chroma lift. Acts as a gain near each hue band's scene
// mean — lift-only, vibrance-masked (already-saturated pixels are attenuated).
// R176 auto-modulates ×0.85–1.25 on top based on scene mean chroma: achromatic
// scenes get more lift (gamut-expansion mode), vibrant scenes back off.
// This knob scales the full automated range. 1.0 = calibrated default. 0 = off.
#define CHROMA_STR  1.10

// R133: per-hue chroma rolloff as Oklab L approaches 1.0, calibrated from Munsell
// Renotation data. f=(4(1-L))^n per hue: no effect below L=0.75, C→0 at L=1.0.
// Hue-specific exponents: yellow rolls off late (peaks at V=9), orange rolls off
// fastest — all from Munsell V=8→9→10 C_max ratios (hue_bands.fxh HB_ROLL_N_*).
// 1.0 = Munsell-calibrated default. 0 = off.
#define MUNSELL_HIGHLIGHT_ROLLOFF  1.0

// Rod-vision blue-green bias + scotopic desaturation across mesopic range (luma 0–0.30).
// Hue: shifts a* (green) + b* (blue) toward 507nm rod peak — blue-green, not pure blue.
// Desat: lab.yz *= (1 − 0.12 × w) — rods are achromatic; deep shadows lose chroma.
// Neutrals unaffected (C=0 → zero shift). R117: transition widened luma 0.12 → 0.30.
// Recalibrate from scratch: try 0.6–0.8. 0 = off.
#define PURKINJE_STRENGTH  0.80

// Per-band hue rotation in Oklab LCh. ±1.0 → ±36°. Positive = clockwise
// (Red→Yellow, Green→Cyan, Blue→Magenta). Default 0.0 = passthrough.
#define ROT_RED     +0.03
#define ROT_YELLOW  -0.015
#define ROT_GREEN   -0.02
#define ROT_CYAN    +0.015
#define ROT_BLUE    -0.03
#define ROT_MAG      0.00

// Film emulsion scatter from specular highlights — orange/amber fringe around
// brightest sources. Red dominates (deepest dye layer), green small, blue near-zero
// (yellow filter layer blocks blue from reaching base). White sources glow orange.
// Fires inside game bloom radius, not on top of it.
// 0 = off. 0.35 = calibrated default. 1.0 = Ektachrome-style aggressive.
#define HAL_STRENGTH  0.30
// Chromatic crossover threshold (ring luma units). Controls where the inner/outer
// halation colour character transitions. Lower = more orange overall.
// Range 0.02–0.20. Tune: raise until orange fringe looks physically correct.
#define HAL_GAMMA     0.05

// ── OUTPUT ────────────────────────────────────────────────────────────────────
// Hollywood Black Magic dual-component model (R131):
//   A) Additive shimmer — highlight bloom into dark areas only (micro-lenslet).
//   B) Soft midtone overlay — gentle airbrushed smoothing, zero at blacks/whites.
// R132 polydisperse: per-channel scatter — red ×1.15, green ×1.00, blue ×0.85.
// Rough grade mapping: 0.5–0.8 = HBM 1/4, 1.2–1.5 = HBM 1/2, 1.8–2.2 = HBM 1.
// 1.40 = HBM 1/2 (Hollywood large-format workhorse grade). 0 = off.
#define DIFFUSION_STRENGTH  0.70

// R136: Selwyn 2383 granularity — three decorrelated dye layers (R:G:B = 1.00:0.80:1.50).
// Peaks in upper shadows (Oklab L≈0.50), falls off toward blacks and highlights.
// Framerate-independent: turns over at ~24fps regardless of display fps.
// 0 = off. 1.0 = calibrated 2383 amplitude. 1.5 = pushed. 2.0 = stylistic.
#define GRAIN_STRENGTH 1.0

// ── STAGE GATES ───────────────────────────────────────────────────────────────
// Bypass entire stages for A/B comparison. Not tuning knobs — leave at 100.
#define CORRECTIVE_STRENGTH 100
#define TONAL_STRENGTH      100
