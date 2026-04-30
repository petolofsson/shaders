// creative_values.fx — tune here

// ── EXPOSURE ─────────────────────────────────────────────────────────────────
// First thing that runs. Applied as pow(rgb, EXPOSURE) before any zone or curve
// work. Sets where pixels sit tonally — which directly changes what every knob
// below "sees". Raising this (>1.0) darkens; lowering (<1.0) brightens.
// Rule of thumb: dial EXPOSURE until overall brightness feels right, then tune
// the contrast/chroma knobs beneath.
#define EXPOSURE            1.04

// ── 3-WAY COLOR CORRECTOR ────────────────────────────────────────────────────
// Runs after EXPOSURE and FilmCurve, before zone contrast. Primary color grade.
// TEMP: positive = warm (R up, B down), negative = cool. Range ±100.
// TINT: positive = magenta (G down, R+B up slightly), negative = green. Range ±100.
// All default to 0 — passthrough. No output change at defaults.
#define SHADOW_TEMP    -20
#define SHADOW_TINT      0
#define MID_TEMP         4
#define MID_TINT         0
#define HIGHLIGHT_TEMP  30
#define HIGHLIGHT_TINT  -5

// ── ZONE CONTRAST ────────────────────────────────────────────────────────────
// Zone S-curve depth and spatial normalization are both automatic: driven by
// zone_std (spread of the 16 spatial zone medians). Flat scenes get stronger
// contrast (~0.30) and lighter normalization; contrasty scenes get less contrast
// (~0.18) and stronger normalization. No user knobs.

// CLARITY adds local midtone contrast at pixel scale — finer-grained than zones.
// It stacks on top of zone work. Keep modest: above 35 it starts to feel
// sharpened rather than film-like.
#define CLARITY_STRENGTH     35

// Shadow lift, density, and chroma strength are now automated:
//   shadow_lift   = lerp(20, 5, smoothstep(0.04, 0.28, p25))
//   chroma_str    = lerp(55, 30, smoothstep(0.05, 0.20, mean_chroma))
//   density_str   = lerp(35, 52, smoothstep(0.05, 0.20, mean_chroma))

// ── CHROMA ───────────────────────────────────────────────────────────────────
// HALATION_STR — warm glow from bright highlights (film emulsion scatter).
// Red scatters widest, blue narrowest — warm orange bloom by construction.
// 0.0 = off, 0.18 = subtle film look, 0.35 = pronounced.
#define HALATION_STR       0.18

// ── FILM CURVE CHARACTER ──────────────────────────────────────────────────────
// Per-channel knee and toe offsets for the FilmCurve (Stage 1). These encode the
// physical dye-layer cross-over character of different film stocks: red compresses
// earlier than green (negative knee offset), blue toe lifts slightly, etc.
// Default values match ARRI ALEXA latitude. Range approximately ±0.015.
// R knee < 0 = red compresses earlier (film-like warm shadows).
// B knee > 0 = blue compresses later (open highlights). B toe < 0 = cool toe.
#define CURVE_R_KNEE  -0.003
#define CURVE_B_KNEE  +0.002
#define CURVE_R_TOE    0.000
#define CURVE_B_TOE    0.000

// ── HUE ROTATION ─────────────────────────────────────────────────────────────
// Per-band rotation in Oklab LCh. ±1.0 → ±36°. Positive = clockwise
// (Red→Yellow, Green→Cyan, Blue→Magenta). Default 0.0 = passthrough.
#define ROT_RED     0.25   // skintones → amber
#define ROT_YELLOW -0.05   // yellows → golden
#define ROT_GREEN   0.20   // foliage → teal
#define ROT_CYAN    0.15   // cyans → deep blue
#define ROT_BLUE   -0.12   // sky → cerulean
#define ROT_MAG    -0.08   // magentas → violet

// ── STAGE GATES ──────────────────────────────────────────────────────────────
// Bypass entire stages for A/B comparison. Not tuning knobs — leave at 100.
#define CORRECTIVE_STRENGTH 100
#define TONAL_STRENGTH      100
