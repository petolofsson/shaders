// creative_values.fx — tune here

// ── EXPOSURE ─────────────────────────────────────────────────────────────────
// First thing that runs. Applied as pow(rgb, EXPOSURE) before any zone or curve
// work. Sets where pixels sit tonally — which directly changes what every knob
// below "sees". Raising this (>1.0) darkens; lowering (<1.0) brightens.
// Rule of thumb: dial EXPOSURE until overall brightness feels right, then tune
// the contrast/chroma knobs beneath.
#define EXPOSURE            0.90

// ── CAMERA SIGNAL RANGE ───────────────────────────────────────────────────────
// Remaps the raw pixel into [FILM_FLOOR, FILM_CEILING] before EXPOSURE runs.
// FILM_FLOOR: black pedestal — prevents absolute digital black. 0 = off.
//   0.005 matches actual linear-light value at the ARRI LogC3 black point.
// FILM_CEILING: white headroom — pulls true white below clip before EXPOSURE.
//   0.95 matches ARRI LogC3 usable ceiling (~91-92% of full scale).
// Both at defaults (0 / 1) = passthrough (identity).
#define FILM_FLOOR    0.005
#define FILM_CEILING  0.95

// ── 3-WAY COLOR CORRECTOR ────────────────────────────────────────────────────
// Runs after EXPOSURE and FilmCurve, before zone contrast. Primary color grade.
// TEMP: positive = warm (R up, B down), negative = cool. Range ±100.
// TINT: positive = magenta (G down, R+B up slightly), negative = green. Range ±100.
// All default to 0 — passthrough. No output change at defaults.
#define SHADOW_TEMP     -5
#define SHADOW_TINT      0
#define MID_TEMP         3
#define MID_TINT         0
#define HIGHLIGHT_TEMP  +2
#define HIGHLIGHT_TINT   0

// ── ZONE CONTRAST ────────────────────────────────────────────────────────────
// Scales the adaptive zone S-curve strength. 1.0 = calibrated default.
// Adaptive range is ~0.16–0.26 × ZONE_STRENGTH, driven by zone_std + scene key.
// 0 = flat image. Above 1.5 = aggressive crushing.
#define ZONE_STRENGTH  1.15

// ── SHADOW LIFT ───────────────────────────────────────────────────────────────
// Scales the auto shadow lift. 1.0 = calibrated default. 0 = off.
// Raise for dark games with poor visibility, lower if lift feels too aggressive.
#define SHADOW_LIFT_STRENGTH  1.4

// ── HUNT LOCALITY (R61) ───────────────────────────────────────────────────────
// Per-pixel Hunt effect adaptation. 0 = global scene mean (current behaviour).
// 0.35 = blend toward pixel-local luminance — highlights get more chroma boost,
// shadows get less. CAM16 local-field specification.
#define HUNT_LOCALITY  0.35

// ── FILM CURVE CHARACTER ──────────────────────────────────────────────────────
// Per-channel knee and toe offsets for the FilmCurve (Stage 1). These encode the
// physical dye-layer cross-over character of different film stocks: red compresses
// earlier than green (negative knee offset), blue toe lifts slightly, etc.
// Default values match ARRI ALEXA latitude. Range approximately ±0.015.
// R knee < 0 = red compresses earlier (film-like warm shadows).
// B knee > 0 = blue compresses later (open highlights). B toe < 0 = cool toe.
#define CURVE_R_KNEE  -0.0102
#define CURVE_B_KNEE   0.0000
#define CURVE_R_TOE   +0.0050
#define CURVE_B_TOE   -0.0218

// ── PRINT STOCK ───────────────────────────────────────────────────────────────
// Kodak 2383 print emulsion on top of FilmCurve: lifts blacks, compresses
// highlights, desaturates mids ~15%, adds warm shadow cast. 0 = off (current
// behaviour). 1 = full 2383. 0.35 = recommended starting point.
#define PRINT_STOCK  0.45

// ── HALATION ──────────────────────────────────────────────────────────────────
// Film emulsion scatter from specular highlights — tight red fringe around
// brightest sources (luma > 0.80). Red scatters most (deepest dye layer),
// green tighter, blue none. Fires inside game bloom radius, not on top of it.
// 0 = off. 0.35 = calibrated default. 1.0 = Ektachrome-style aggressive.
#define HAL_STRENGTH  0.30

// ── HUE ROTATION ─────────────────────────────────────────────────────────────
// Per-band rotation in Oklab LCh. ±1.0 → ±36°. Positive = clockwise
// (Red→Yellow, Green→Cyan, Blue→Magenta). Default 0.0 = passthrough.
#define ROT_RED     +0.03
#define ROT_YELLOW  -0.015
#define ROT_GREEN   -0.02
#define ROT_CYAN    +0.015
#define ROT_BLUE    -0.03
#define ROT_MAG      0.00

// ── RETINAL VIGNETTE ─────────────────────────────────────────────────────────
// Peripheral luminance darkening (SCE) + chroma desaturation (Purkinje shift).
// Use for games with no built-in vignette. Skip if the game already has one.
// VIGN_STRENGTH: max corner darkening. 0 = off. Scales with scene brightness.
// VIGN_RADIUS:   Gaussian σ in aspect-corrected UV. Larger = wider bright centre.
// VIGN_CHROMA:   max corner chroma reduction. 0 = luma-only. Scales with darkness.
#define VIGN_STRENGTH  0.00
#define VIGN_RADIUS    0.40
#define VIGN_CHROMA    0.00

// ── VEIL ──────────────────────────────────────────────────────────────────────
// Veiling glare: additive luminance lift simulating intraocular scatter and lens
// reflections. Restores the contrast floor of real optical viewing.
// Use for games with no volumetric fog or atmospheric depth. Skip if the game
// has its own volumetric/fog system (it will compete).
// VEIL_STRENGTH: glare as fraction of scene p75 luminance. 0 = off. 0.05 = subtle, 0.15 = heavy.
#define VEIL_STRENGTH  0.05

// ── PRO MIST ──────────────────────────────────────────────────────────────────
// Overall scatter strength scalar. 1.0 = calibrated default (~9% base). 0 = off.
#define MIST_STRENGTH  0.25

// ── PURKINJE SHIFT ────────────────────────────────────────────────────────────
// Rod-vision blue-green hue bias in deep shadows (luma < 0.12). Physiologically
// correct — Cao et al. 2008, implemented in Ghost of Tsushima. Neutrals unaffected
// (C=0 → zero shift). 1.0 = calibrated default. 0 = off.
#define PURKINJE_STRENGTH  1.2

// ── VIEWING SURROUND ─────────────────────────────────────────────────────────
// CIECAM02 surround compensation (R76B). Corrects perceived contrast for dark-room
// viewing. 1.0 = off. dim→dark (gaming/desktop): 1.123. average→dark: 1.314.
#define VIEWING_SURROUND  1.123

// ── EYE LCA ───────────────────────────────────────────────────────────────────
// Longitudinal chromatic aberration of the human eye: blue focuses short, red
// focuses long. Simulates the natural per-channel fringe that real-world optics
// produce. 0 = off. 0.5 = subtle (~1.2D). 1.0 = full physiological LCA (~2.4D).
#define LCA_STRENGTH  0.2

// ── INVERSE GRADE (R90) ───────────────────────────────────────────────────────
// Adaptive inverse tone mapping. Expands display IQR toward the ACES-derived
// 3.28-stop reference. Works on any S-curve tonemapper. 0 = off. 1.0 = full.
// 0.30 is the recommended starting point.
#define INVERSE_STRENGTH  0.60

// ── STAGE GATES ──────────────────────────────────────────────────────────────
// Bypass entire stages for A/B comparison. Not tuning knobs — leave at 100.
#define CORRECTIVE_STRENGTH 100
#define TONAL_STRENGTH      100
