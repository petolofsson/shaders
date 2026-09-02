// Arc Raiders creative values.
// Keep user-facing tuning here; shader constants and analysis parameters stay in general/.

// INPUT
#define INVERSE_STRENGTH  1.0
#define INVERSE_LUMA      0.0

// CORRECTIVE
#define BLACKS            0.005
#define WHITES            1.00
#define EXPOSURE          0.10
#define FILM_CURVE        0.65
#define CURVE_R_KNEE     -0.10
#define CURVE_B_KNEE      0.20

// PRIMARY COLOR CORRECTION
#define SHADOW_TEMP       0.00
#define SHADOW_TINT       0.00
#define MID_TEMP          0.00
#define MID_TINT          0.00
#define HIGHLIGHT_TEMP    0.00
#define HIGHLIGHT_TINT    0.00

// TONAL
#define CONTRAST              0.50
#define SHADOWS               0.50

// LOOK
#define PRINT_STOCK           0.75
#define PRINTER_R             1.00
#define PRINTER_G             1.00
#define PRINTER_B             1.00

// OUTPUT
#define DIFFUSION             0.00
#define GRAIN                 0.40

// STAGE GATES: comparison controls, leave at 100 unless isolating a stage.
#define CORRECTIVE_STRENGTH   100
#define TONAL_STRENGTH        100
#define CHROMA_STRENGTH       100
#define LOOK_STRENGTH         100
