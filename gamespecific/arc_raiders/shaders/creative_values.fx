// Arc Raiders creative values.
// Keep user-facing tuning here; shader constants and analysis parameters stay in general/.

// INPUT
#define INVERSE_STRENGTH  0.5
#define INVERSE_LUMA      0.5

// CORRECTIVE
#define BLACKS            0.0025
#define WHITES            0.995
#define EXPOSURE          0.00
#define FILM_CURVE        0.6   // broken for now: no visible effect, print shoulder compensates (research/2026-11-09_effect_visibility.md)

// PRIMARY COLOR CORRECTION
#define SHADOW_TEMP       -0.225
#define SHADOW_TINT       0.0
#define SHADOW_CC_STRENGTH 2.5   // multiplies SHADOW_TEMP/TINT; shadow colour placed by the light map
#define MID_TEMP          0.0875
#define MID_TINT          0.00
#define HIGHLIGHT_TEMP    0.0875
#define HIGHLIGHT_TINT    0.00

// TONAL
#define CONTRAST              1.0
#define SHADOWS               1.0
#define RETINEX_STRENGTH      0.4
#define ZONE_CONTRAST_STRENGTH 1.0
#define SHADOW_LIFT_STRENGTH   0.75
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
#define PRINTER_R             0.0
#define PRINTER_G             0.00
#define PRINTER_B             0.00

// OUTPUT

// STAGE GATES: comparison controls, leave at 100 unless isolating a stage.
#define CORRECTIVE_STRENGTH   100
#define TONAL_STRENGTH        100
#define CHROMA_STRENGTH       100
#define LOOK_STRENGTH         100
