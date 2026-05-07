// creative_values.fx — tune here

// ── INVERSE GRADE (R90) ───────────────────────────────────────────────────────
// Adaptive inverse tone mapping. Expands display IQR toward the ACES-derived
// 3.28-stop reference. Works on any S-curve tonemapper. 0 = off. 1.0 = full.
// 0.30 is the recommended starting point.
#define INVERSE_STRENGTH  0.40

// ── EXPOSURE ─────────────────────────────────────────────────────────────────
// First thing that runs. Applied as pow(rgb, EXPOSURE) before any zone or curve
// work. Sets where pixels sit tonally — which directly changes what every knob
// below "sees". Raising this (>1.0) darkens; lowering (<1.0) brightens.
// Rule of thumb: dial EXPOSURE until overall brightness feels right, then tune
// the contrast/chroma knobs beneath.
#define EXPOSURE            0.95

// ── CAMERA SIGNAL RANGE ───────────────────────────────────────────────────────
// Remaps the raw pixel into [FILM_FLOOR, FILM_CEILING] before EXPOSURE runs.
// FILM_FLOOR: black pedestal — prevents absolute digital black. 0 = off.
//   0.005 matches actual linear-light value at the ARRI LogC3 black point.
// FILM_CEILING: white headroom — pulls true white below clip before EXPOSURE.
//   0.95 matches ARRI LogC3 usable ceiling (~91-92% of full scale).
// Both at defaults (0 / 1) = passthrough (identity).
#define FILM_FLOOR    0.005
#define FILM_CEILING  1.00

// ── PRINT STOCK ───────────────────────────────────────────────────────────────
// Kodak 2383 print emulsion on top of FilmCurve: lifts blacks, compresses
// highlights, desaturates mids ~15%, adds warm shadow cast. 0 = off.
// 1 = full 2383. 0.35 = recommended starting point.
#define PRINT_STOCK  0.45

// ── BLEACH BYPASS ─────────────────────────────────────────────────────────────
// Skip the bleach step during print development — retains metallic silver alongside
// color dye. Desaturates shadows most (denser silver retention in unexposed areas),
// steepens midtone contrast, adds grit. Se7en, Saving Private Ryan, Traffic.
// 0 = off. 1 = full (near-monochrome shadows). Start: 0.1–0.3.
#define BLEACH_BYPASS  0.0

// ── DIR COUPLERS ──────────────────────────────────────────────────────────────
// Developer-inhibitor-release cross-channel masking. Each dye layer releases
// inhibitors that suppress adjacent layers, increasing colour separation.
// Fires after EXPOSURE, before FilmCurve — pure SDR-log effect.
// 0 = off (default). 0.3 = subtle. 0.6 = visible colour pop. 1.0 = strong.
#define COUPLER_STRENGTH  0.4

// ── FILM CURVE CHARACTER ──────────────────────────────────────────────────────
// Per-channel knee and toe offsets for the FilmCurve (Stage 1). These encode the
// physical dye-layer cross-over character of different film stocks: red compresses
// earlier than green (negative knee offset), blue toe lifts slightly, etc.
// Default values match ARRI ALEXA latitude. Range approximately ±0.015.
// R knee < 0 = red compresses earlier (film-like warm shadows).
// B knee > 0 = blue compresses later (open highlights). B toe < 0 = cool toe.
#define CURVE_R_KNEE  -0.0102
#define CURVE_B_KNEE   0.0000
#define CURVE_R_TOE   +0.0100
#define CURVE_B_TOE   -0.0218

// ── ZONE CONTRAST ────────────────────────────────────────────────────────────
// Scales the adaptive zone S-curve strength. 1.0 = calibrated default.
// Adaptive range is ~0.16–0.26 × ZONE_STRENGTH, driven by zone_std + scene key.
// 0 = flat image. Above 1.5 = aggressive crushing.
#define ZONE_STRENGTH  1.3

// ── SHADOW LIFT ───────────────────────────────────────────────────────────────
// Scales the auto shadow lift. 1.0 = calibrated default. 0 = off.
// Raise for dark games with poor visibility, lower if lift feels too aggressive.
#define SHADOW_LIFT_STRENGTH  0.8

// ── 3-WAY COLOR CORRECTOR ────────────────────────────────────────────────────
// Runs after EXPOSURE and FilmCurve, before zone contrast. Primary color grade.
// TEMP: positive = warm (R up, B down), negative = cool. Range ±100.
// TINT: positive = magenta (G down, R+B up slightly), negative = green. Range ±100.
// All default to 0 — passthrough. No output change at defaults.
#define SHADOW_TEMP     -8
#define SHADOW_TINT      0
#define MID_TEMP        +3
#define MID_TINT         0
#define HIGHLIGHT_TEMP  +6
#define HIGHLIGHT_TINT   0

// ── CHROMA LIFT ───────────────────────────────────────────────────────────────
// Strength of the per-hue chroma lift (grade.fx LiftChroma). Acts as a gain
// near each hue band's scene mean — lift-only, vibrance-masked (already-saturated
// pixels are attenuated). Spatial R68A modulation is applied on top.
// 1.0 = calibrated default. 0 = off. Above 2.0 = aggressive.
#define CHROMA_STR  0.30

// ── HUE ROTATION ─────────────────────────────────────────────────────────────
// Per-band rotation in Oklab LCh. ±1.0 → ±36°. Positive = clockwise
// (Red→Yellow, Green→Cyan, Blue→Magenta). Default 0.0 = passthrough.
#define ROT_RED     +0.03
#define ROT_YELLOW  -0.015
#define ROT_GREEN   -0.02
#define ROT_CYAN    +0.015
#define ROT_BLUE    -0.03
#define ROT_MAG      0.00

// ── HALATION ──────────────────────────────────────────────────────────────────
// Film emulsion scatter from specular highlights — orange/amber fringe around
// brightest sources. Red dominates (deepest dye layer), green small, blue near-zero
// (yellow filter layer blocks blue from reaching base). White sources glow orange.
// Fires inside game bloom radius, not on top of it.
// 0 = off. 0.35 = calibrated default. 1.0 = Ektachrome-style aggressive.
#define HAL_STRENGTH  0.5
// HAL_GAMMA: chromatic crossover threshold (ring luma units, R117).
// Controls where the inner/outer halation colour character transitions.
// Inner ring (large ring energy > HAL_GAMMA): spectrally balanced.
// Outer tail (small ring energy < HAL_GAMMA): orange/amber dominant.
// Lower = crossover occurs at lower ring brightness (more orange overall).
// Higher = crossover threshold rises (inner ring stays balanced further out).
// Range 0.02–0.20. Tune: raise until orange fringe looks physically correct.
#define HAL_GAMMA     0.01

// ── PRO MIST ──────────────────────────────────────────────────────────────────
// Highlight shimmer — bright sources bloom into adjacent dark areas (additive).
// Shadows stay dark; midtones unaffected. Recalibrate from scratch after R115:
// old values were tuned for diffusion. Start around 0.1–0.4. 0 = off.
#define MIST_STRENGTH  0.30

// ── PURKINJE SHIFT ────────────────────────────────────────────────────────────
// Rod-vision blue-green hue bias across the mesopic range (luma 0–0.30). Physiologically
// correct — Cao et al. 2008, implemented in Ghost of Tsushima. Neutrals unaffected
// (C=0 → zero shift). R117: transition widened from luma 0.12 → 0.30 to cover full
// scotopic-photopic range. Recalibrate from scratch: try 0.6–0.8 (wider range = more
// integrated effect at same strength). 0 = off.
#define PURKINJE_STRENGTH  1.0

// ── STAGE GATES ──────────────────────────────────────────────────────────────
// Bypass entire stages for A/B comparison. Not tuning knobs — leave at 100.
#define CORRECTIVE_STRENGTH 100
#define TONAL_STRENGTH      100
