// creative_values.fx — tune here

// ── INPUT ─────────────────────────────────────────────────────────────────────
// Adaptive inverse tone mapping. Expands Oklab chroma using the IQR-derived compression
// ratio — restoring chroma the game's tonemapper compressed. Luma is handled by zone
// S-curve. Works on any S-curve tonemapper. 0 = off. Start at 0.30–0.50.
#define INVERSE_STRENGTH  0.40

// ── CORRECTIVE ────────────────────────────────────────────────────────────────
// Exposure in stops. 0 = neutral, +1 = one stop brighter, -1 = one stop darker.
// Applied as rgb * pow(2, EXPOSURE) before any zone or curve work.
// Sets where pixels sit tonally — which directly changes what every knob below "sees".
// Rule of thumb: dial until overall brightness feels right, then tune beneath.
#define EXPOSURE  0.15

// Remaps the raw pixel into [BLACKS, WHITES] before EXPOSURE runs.
// BLACKS: black pedestal — prevents absolute digital black. 0 = off.
//   0.005 matches actual linear-light value at the ARRI LogC3 black point.
// WHITES: white headroom — pulls true white below clip before EXPOSURE.
//   0.95 matches ARRI LogC3 usable ceiling (~91-92% of full scale).
// Both at defaults (0 / 1) = passthrough (identity).
#define BLACKS  0.005
#define WHITES  0.95

// Per-channel knee and toe offsets for the FilmCurve. Encodes the physical dye-layer
// cross-over character of different film stocks.
// Default values match ARRI ALEXA latitude. Range approximately ±0.015.
// R knee < 0 = red compresses earlier (film-like warm shadows).
// B knee > 0 = blue compresses later (open highlights). B toe < 0 = cool toe.
#define CURVE_R_KNEE  -0.010
#define CURVE_B_KNEE  +0.008
#define CURVE_R_TOE   +0.010
#define CURVE_B_TOE   -0.005

// Kodak 2383 print emulsion on top of FilmCurve: gentle shadow density bow,
// restrained shoulder, desaturates mids ~15%, adds warm shadow cast. 0 = off.
// 1 = full 2383. 0.35 = recommended starting point.
#define PRINT_STOCK  0.35
// Skip the bleach step during print development — retains metallic silver alongside
// color dye. Desaturates shadows most (denser silver retention in unexposed areas),
// steepens midtone contrast, adds grit. Se7en, Saving Private Ryan, Traffic.
// 0 = off. 1 = full (near-monochrome shadows). Start: 0.1–0.3.
#define BLEACH_BYPASS  0.05

// Primary color grade. Runs after FilmCurve, before zone contrast.
// TEMP: positive = warm (R up, B down), negative = cool. Range ±100.
// TINT: positive = magenta (G down, R+B up slightly), negative = green. Range ±100.
// All default to 0 — passthrough. No output change at defaults.
#define SHADOW_TEMP     -5
#define SHADOW_TINT      0
#define MID_TEMP        +3
#define MID_TINT         0
#define HIGHLIGHT_TEMP  +5
#define HIGHLIGHT_TINT   0

// ── TONAL ─────────────────────────────────────────────────────────────────────
// Scales the adaptive zone S-curve strength. 1.0 = calibrated default. 0 = off.
// 2.0 = aggressive. Range 0–2.
#define CONTRAST  1.00

// Scales the auto shadow lift. 1.0 = calibrated default. 0 = off.
// Raise for dark games with poor visibility, lower if lift feels too aggressive.
#define SHADOWS  0.50

// Soft luma push/pull in the highlight range (L > 0.55). +1.0 brightens highlights,
// -1.0 recovers blown highlights. Range ±1.0. Default 0.0 = passthrough.
#define HIGHLIGHTS  0.00

// R183: pre-flash warm shadow cast. Fixed warm amber additive in deep shadows (L < 0.25),
// falls to zero at mid-gray. Models Deakins' colored negative pre-flash technique.
// Positive = warm amber, negative = cool blue-green. Range ±1.0. Default 0.0 = passthrough.
#define SHADOW_CAST  0.00

// ── CHROMA ────────────────────────────────────────────────────────────────────
// Per-hue chroma lift strength. Acts as a gain near each hue band's scene mean —
// lift-only, vibrance-masked (already-saturated pixels are attenuated).
// Reach for this first — lifts flat/dull areas without pushing vivid pixels further.
// 1.0 = calibrated default. 0 = off.
#define VIBRANCE  0.20

// Global chroma multiplier. -1.0 = greyscale, 0.0 = passthrough, +1.0 = 2× chroma.
// Applied uniformly — use after Vibrance when you want a deliberate global push.
#define SATURATION 0.00


// Rod-vision blue-green bias + scotopic desaturation across mesopic range (luma 0–0.30).
// Hue: shifts a* (green) + b* (blue) toward 507nm rod peak — blue-green, not pure blue.
// Desat: lab.yz *= (1 − 0.12 × w) — rods are achromatic; deep shadows lose chroma.
// Neutrals unaffected (C=0 → zero shift). R117: transition widened luma 0.12 → 0.30.
// Recalibrate from scratch: try 0.6–0.8. 0 = off.
#define PURKINJE_STRENGTH  0.65

// Per-band hue rotation in Oklab LCh. ±1.0 → ±36°. Positive = clockwise
// (Red→Yellow, Green→Cyan, Blue→Magenta). Default 0.0 = passthrough.
#define ROT_RED      0.00
#define ROT_YELLOW  -0.017
#define ROT_GREEN   -0.02
#define ROT_CYAN    +0.015
#define ROT_BLUE    -0.03
#define ROT_MAG      0.00

// ── HUE SATURATION ───────────────────────────────────────────────────────────
// Per-band chroma scale in Oklab C. ±1.0 → ±80% chroma per hue band.
// Applied after Vibrance. Default 0.0 = passthrough.
#define SAT_RED    -0.05
#define SAT_YELLOW -0.08
#define SAT_GREEN   0.0
#define SAT_CYAN    0.0
#define SAT_BLUE    0.0
#define SAT_MAG     0.0

// Film emulsion scatter from specular highlights — orange/amber fringe around
// brightest sources. Red dominates (deepest dye layer), green small, blue near-zero
// (yellow filter layer blocks blue from reaching base). White sources glow orange.
// Fires inside game bloom radius, not on top of it.
// 0 = off. 0.35 = calibrated default. 1.0 = Ektachrome-style aggressive.
#define HAL_STRENGTH  0.45
// Chromatic crossover threshold (ring luma units). Controls where the inner/outer
// halation colour character transitions. Lower = more orange overall.
// Range 0.02–0.20. Tune: raise until orange fringe looks physically correct.
#define HAL_GAMMA     0.04

// ── OUTPUT ────────────────────────────────────────────────────────────────────
// Hollywood Black Magic dual-component model (R131):
//   A) Additive shimmer — highlight bloom into dark areas only (micro-lenslet).
//   B) Soft midtone overlay — gentle airbrushed smoothing, zero at blacks/whites.
// R132 polydisperse: per-channel scatter — red ×1.15, green ×1.00, blue ×0.85.
// Rough grade mapping: 0.5–0.8 = HBM 1/4, 1.2–1.5 = HBM 1/2, 1.8–2.2 = HBM 1.
// 1.40 = HBM 1/2 (Hollywood large-format workhorse grade). 0 = off.
#define DIFFUSION_STRENGTH  0.45

// R136: Selwyn 2383 granularity — three decorrelated dye layers (R:G:B = 1.00:0.80:1.50).
// Envelope sqrt(1−L_gamma): mathematically highest at pure black, tapers to zero at white.
// Perceived peak is in upper shadows — grain at pure black is invisible against the dark.
// Framerate-independent: turns over at ~24fps regardless of display fps.
// 0 = off. 1.0 = calibrated 2383 amplitude. 1.5 = pushed. 2.0 = stylistic.
#define GRAIN_STRENGTH 0.50

// ── STAGE GATES ───────────────────────────────────────────────────────────────
// Bypass entire stages for A/B comparison. Not tuning knobs — leave at 100.
#define CORRECTIVE_STRENGTH 100
#define TONAL_STRENGTH      100

// ── DEBUG ─────────────────────────────────────────────────────────────────────
// Spatially-adaptive tonal redistribution (R189). Bilateral base layer blends local
// illumination toward scene global key — lifts dark areas, pulls bright areas —
// while restoring the detail layer so all texture is preserved. 0 = off. 0.25–0.40 = cinematic.
#define BILATERAL_STRENGTH 0.40

// Local contrast / clarity (R189). Scales the bilateral detail layer before reconstruction.
// >0 = micro-contrast punch (Lightroom Clarity equivalent). <0 = spatial softening.
// 0 = off. 0.20–0.40 = subtle punch. Independent of BILATERAL_STRENGTH.
#define CLARITY_STRENGTH  0.00
