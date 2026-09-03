// GZW creative values.
// Keep user-facing tuning here; shader constants and analysis parameters stay in general/.

// INPUT
#define INVERSE_STRENGTH  0.70
#define INVERSE_LUMA      0.70

// CORRECTIVE
#define BLACKS            0.005
#define WHITES            1.00
#define EXPOSURE          0.00
#define FILM_CURVE        0.15
#define CURVE_R_KNEE      0.00
#define CURVE_B_KNEE      0.00

// PRIMARY COLOR CORRECTION
#define SHADOW_TEMP       0.00
#define SHADOW_TINT       0.00
#define MID_TEMP          0.00
#define MID_TINT          0.00
#define HIGHLIGHT_TEMP    0.00
#define HIGHLIGHT_TINT    0.00

// TONAL
#define CONTRAST              1.00
#define SHADOWS               1.00

// LOOK
#define PRINT_STOCK           0.35
#define PRINTER_R             0.00
#define PRINTER_G             0.00
#define PRINTER_B             0.00

// OUTPUT
#define DIFFUSION             0.5
#define GRAIN                 0.60

// STAGE GATES: comparison controls, leave at 100 unless isolating a stage.
#define CORRECTIVE_STRENGTH   100
#define TONAL_STRENGTH        100
#define CHROMA_STRENGTH       100
#define LOOK_STRENGTH         100
