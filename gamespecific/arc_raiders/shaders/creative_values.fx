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
// Zone S-curve depth is automatic: driven by zone_std (spread of the 16 spatial
// zone medians). Flat scenes get stronger contrast (~0.30), contrasty scenes
// get less (~0.18). Higher EXPOSURE lifts pixels into the midtone range where
// the S-curve is most active, so overall contrast still responds to EXPOSURE.

// SPATIAL_NORM_STRENGTH pulls zone medians toward the global scene key after
// the S-curve — dark zones lift slightly, bright zones compress slightly.
// Keep modest; at 20 the effect is subtle balancing.
#define SPATIAL_NORM_STRENGTH 20

// CLARITY adds local midtone contrast at pixel scale — finer-grained than zones.
// It stacks on top of zone work. Keep modest: above 35 it starts to feel
// sharpened rather than film-like.
#define CLARITY_STRENGTH     35

// SHADOW_LIFT raises the toe. Interacts with EXPOSURE: lowering EXPOSURE already
// lifts shadows upward through the gamma; SHADOW_LIFT then pushes the toe further.
// If blacks feel milky lower one or both. At 15 the lift is gentle and film-like.
#define SHADOW_LIFT          15
// ── CHROMA ───────────────────────────────────────────────────────────────────
// DENSITY compacts chroma first, CHROMA bends what remains per hue.
// Lower DENSITY = more chroma. H-K brightness correction (Hellwig 2022,
// baked at 0.25) and saturation-by-luminance rolloff run automatically.
//
// DENSITY_STRENGTH — subtractive dye density (film-like colour compaction).
//   Desaturates uniformly before other chroma work. The "film stock body" feel.
// CHROMA_STRENGTH — per-hue saturation bend after density.
//   Positive bends all hues more vibrant; negative mutes.
#define DENSITY_STRENGTH   45
#define CHROMA_STRENGTH    40

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
