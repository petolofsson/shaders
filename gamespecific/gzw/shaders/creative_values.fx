// GZW creative values.
// Keep user-facing tuning here; shader constants and analysis parameters stay in general/.

// INPUT
#define INVERSE_STRENGTH  0.60
#define INVERSE_LUMA      0.60

// CORRECTIVE
#define BLACKS            0.001
#define WHITES            0.995
#define EXPOSURE          0.00
#define FILM_CURVE        0.70   // broken for now: no visible effect, print shoulder compensates (research/2026-11-09_effect_visibility.md)

// PRIMARY COLOR CORRECTION
#define SHADOW_TEMP       -0.15
#define SHADOW_TINT       -0.030
#define SHADOW_CC_STRENGTH 1.25  // multiplies SHADOW_TEMP/TINT; shadow colour placed by the light map
#define SHADOW_FILL_FOLLOW 1.0    // 1 = shadow colour only where shade reads cooler than adjacent sunlit surfaces (0 = everywhere)
#define SHADOW_NEUTRALIZE  1.0    // remove measured fill-vs-key tint from shade before the shadow CC (toward neutral only; 0 = off)
#define KEY_WARMTH         0.5    // extra mid/highlight warmth only when the frame shows a warm key against cool fill
#define MID_TEMP          0.0875
#define MID_TINT          0.00
#define HIGHLIGHT_TEMP    0.10
#define HIGHLIGHT_TINT    0.00

// TONAL
#define CONTRAST              1.0
#define SHADOWS               1.0
#define RETINEX_STRENGTH      0.0
#define ZONE_CONTRAST_STRENGTH 1.0
#define SHADOW_LIFT_STRENGTH   0.50
#define SHADOW_SURROUND_TINT   1.0   // shadows take a slight tint of surrounding surface colour (0 = off)

// CHROMA
#define SATURATION           0.075
#define WARM_RESTRAINT       1.0    // red..yellow keep none of the chroma stage boost (0 = full boost); never cuts below its input
#define SAT_RED              0.0    // per-band saturation, -1..1 = -80..+80% chroma (bands ~±50 deg)
#define SAT_YELLOW           0.0
#define SAT_GREEN            0.0
#define SAT_CYAN             0.0
#define SAT_BLUE             0.0
#define SAT_MAG              0.0

// LOOK
#define PRINT_STOCK           0.5
#define PRINTER_R             0.00
#define PRINTER_G             0.00
#define PRINTER_B             0.00

// OUTPUT

// STAGE GATES: comparison controls, leave at 100 unless isolating a stage.
#define CORRECTIVE_STRENGTH   100
#define TONAL_STRENGTH        100
#define CHROMA_STRENGTH       100
#define LOOK_STRENGTH         100
