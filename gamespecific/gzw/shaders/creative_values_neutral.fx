// creative_values_neutral.fx — passthrough template
// Copy over creative_values.fx to get a clean zero-baseline for a new game
// or for debugging. Everything is at identity / off.
// Pipeline output should match the game's raw tonemapped output.

// ── INPUT ─────────────────────────────────────────────────────────────────────
#define INVERSE_STRENGTH  0.00
#define INVERSE_LUMA      0.00

// ── CORRECTIVE ────────────────────────────────────────────────────────────────
#define BLACKS          0.00
#define WHITE_HEADROOM  0.00
#define EXPOSURE 0.00
#define HAL_STRENGTH  0.00
#define HAL_CROSSOVER  0.04
#define CURVE_R_KNEE  -0.00
#define CURVE_B_KNEE  +0.00
#define CURVE_R_TOE   +0.00
#define CURVE_B_TOE   -0.00
#define SHADOW_TEMP     0
#define SHADOW_TINT     0
#define MID_TEMP        0
#define MID_TINT        0
#define HIGHLIGHT_TEMP  0
#define HIGHLIGHT_TINT  0

// ── TONAL ─────────────────────────────────────────────────────────────────────
#define LOCAL_TONE  0.00
#define CLARITY_STRENGTH  0.00
#define CONTRAST  0.00
#define SHADOWS  0.00
#define HIGHLIGHTS  0.00

// ── CHROMA ────────────────────────────────────────────────────────────────────
#define SHADOW_CAST  0.00
#define PURKINJE_STRENGTH  0.00
#define ROT_RED      0.00
#define ROT_YELLOW   0.00
#define ROT_GREEN    0.00
#define ROT_CYAN     0.00
#define ROT_BLUE     0.00
#define ROT_MAG      0.00
#define VIBRANCE  0.00
#define SAT_RED    0.0
#define SAT_YELLOW 0.0
#define SAT_GREEN  0.0
#define SAT_CYAN   0.0
#define SAT_BLUE   0.0
#define SAT_MAG    0.0
#define SATURATION  0.00

// ── LOOK ──────────────────────────────────────────────────────────────────────
#define PRINT_STOCK  0.00
#define BLEACH_BYPASS  0.00
#define PRINTER_R  0.0
#define PRINTER_G  0.0
#define PRINTER_B  0.0

// ── OUTPUT ────────────────────────────────────────────────────────────────────
#define DIFFUSION_STRENGTH  0.00
#define GRAIN_STRENGTH  0.00

// ── STAGE GATES ───────────────────────────────────────────────────────────────
#define CORRECTIVE_STRENGTH  100
#define TONAL_STRENGTH       100
#define CHROMA_STRENGTH      100
#define LOOK_STRENGTH        100
