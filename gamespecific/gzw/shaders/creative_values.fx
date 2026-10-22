// Arc Raiders creative values.
// Keep user-facing tuning here; shader constants and analysis parameters stay in general/.

// INPUT
#define INVERSE_STRENGTH  0.75
#define INVERSE_LUMA      0.5

// CORRECTIVE
#define BLACKS            0.005
#define WHITES            1.0
#define EXPOSURE          0.17
#define FILM_CURVE        0.65
#define CURVE_R_KNEE      0.05
#define CURVE_B_KNEE      0.05

// PRIMARY COLOR CORRECTION
#define SHADOW_TEMP       -0.15
#define SHADOW_TINT       -0.05
#define MID_TEMP          0.10
#define MID_TINT          0.00
#define HIGHLIGHT_TEMP    0.10
#define HIGHLIGHT_TINT    0.00

// TONAL
#define CONTRAST              1.0
#define SHADOWS               1.0
#define RETINEX_STRENGTH      1.0
#define ZONE_CONTRAST_STRENGTH 1.0
#define SHADOW_LIFT_STRENGTH   1.0

// LOOK
#define PRINT_STOCK           1.0
#define PRINTER_R             1.0
#define PRINTER_G             1.00
#define PRINTER_B             1.00

// OUTPUT

// STAGE GATES: comparison controls, leave at 100 unless isolating a stage.
#define CORRECTIVE_STRENGTH   100
#define TONAL_STRENGTH        100
#define CHROMA_STRENGTH       100
#define LOOK_STRENGTH         100
