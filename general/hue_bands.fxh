// hue_bands.fxh — 12-hue band centers, weights, and natural chroma ceilings
//
// Covers the full color wheel at primary + secondary + tertiary positions.
// Hue is normalized 0–1 (Oklab atan2(b,a) / 2π, frac-wrapped).
// Included by inverse_grade.fx and grade.fx — edit ceiling values here only.
//
// Ceiling values are Munsell-calibrated natural scene maxima (Oklab C):
//   Yellow tightest — smallest MacAdam discrimination ellipses.
//   Warm hues moderate. Cool hues relaxed (larger ellipses in blue).
//   Red/Magenta loosest — highest natural object-color saturation.
//
// Band width: smoothstep falloff over ±0.08 normalized hue (~29°).

#define HB_BAND_WIDTH   0.08

#define HB_BAND_RED     0.083   // ~30°
#define HB_BAND_ORANGE  0.181   // ~65°
#define HB_BAND_AMBER   0.242   // ~87°
#define HB_BAND_YELLOW  0.305   // ~110°
#define HB_BAND_GREEN   0.396   // ~143°
#define HB_BAND_TEAL    0.469   // ~169°
#define HB_BAND_CYAN    0.542   // ~195°
#define HB_BAND_AZURE   0.639   // ~230°
#define HB_BAND_BLUE    0.735   // ~265°
#define HB_BAND_VIOLET  0.825   // ~297°
#define HB_BAND_MAGENTA 0.913   // ~329°
#define HB_BAND_ROSE    0.997   // ~359°

#define HB_CEIL_RED     0.24  // R138: 7.5R  V=5 ig_max=0.236 (was 0.28, above sRGB gamut max — never fired)
#define HB_CEIL_ORANGE  0.13  // R138: 7.5YR V=5 ig_max=0.130 (was 0.16, estimated)
#define HB_CEIL_AMBER   0.12  // R138: 2.5Y  V=5 ig_max=0.116 (was 0.15, estimated)
#define HB_CEIL_YELLOW  0.14
#define HB_CEIL_GREEN   0.16
#define HB_CEIL_TEAL    0.12  // R138: 5G    V=5 ig_max=0.123 (was 0.15, estimated)
#define HB_CEIL_CYAN    0.15
#define HB_CEIL_AZURE   0.13  // R138: 2.5PB V=5 ig_max=0.128 (was 0.17, estimated)
#define HB_CEIL_BLUE    0.19
#define HB_CEIL_VIOLET  0.22  // R138: 10PB  V=5 ig_max=0.217 (was 0.20, estimated)
#define HB_CEIL_MAGENTA 0.22
#define HB_CEIL_ROSE    0.24  // R138: 7.5RP V=5 ig_max=0.242 (was 0.22, estimated)

float HueBandWeight(float hue, float center)
{
    hue = frac(hue);
    float d = abs(hue - center);
    d = min(d, 1.0 - d);
    float t = saturate(1.0 - d / HB_BAND_WIDTH);
    return t * t * (3.0 - 2.0 * t);
}

// Returns the blended natural chroma ceiling at the given normalized hue.
// Apply as: new_C = min(new_C, max(HueCeil(hue), incoming_C))
// The max(ceil, incoming_C) guard preserves existing saturation above the
// ceiling — only expansion/lift above the natural maximum is blocked.
// Normalized: divides by weight sum so output equals the calibrated ceiling
// values regardless of band spacing (bands are unevenly spaced 0.061–0.098).
float HueCeil(float hue)
{
    hue = frac(hue);
    float w0  = HueBandWeight(hue, HB_BAND_RED);
    float w1  = HueBandWeight(hue, HB_BAND_ORANGE);
    float w2  = HueBandWeight(hue, HB_BAND_AMBER);
    float w3  = HueBandWeight(hue, HB_BAND_YELLOW);
    float w4  = HueBandWeight(hue, HB_BAND_GREEN);
    float w5  = HueBandWeight(hue, HB_BAND_TEAL);
    float w6  = HueBandWeight(hue, HB_BAND_CYAN);
    float w7  = HueBandWeight(hue, HB_BAND_AZURE);
    float w8  = HueBandWeight(hue, HB_BAND_BLUE);
    float w9  = HueBandWeight(hue, HB_BAND_VIOLET);
    float w10 = HueBandWeight(hue, HB_BAND_MAGENTA);
    float w11 = HueBandWeight(hue, HB_BAND_ROSE);
    float num = w0  * HB_CEIL_RED     + w1  * HB_CEIL_ORANGE
              + w2  * HB_CEIL_AMBER   + w3  * HB_CEIL_YELLOW
              + w4  * HB_CEIL_GREEN   + w5  * HB_CEIL_TEAL
              + w6  * HB_CEIL_CYAN    + w7  * HB_CEIL_AZURE
              + w8  * HB_CEIL_BLUE    + w9  * HB_CEIL_VIOLET
              + w10 * HB_CEIL_MAGENTA + w11 * HB_CEIL_ROSE;
    return num / max(w0+w1+w2+w3+w4+w5+w6+w7+w8+w9+w10+w11, 1e-6);
}

// R133 Munsell highlight rolloff exponents.
// Power n in f=(4(1-L))^n, calibrated from Munsell Renotation V=8→9→10 C_max ratios.
// f=1 at L≤0.75 (V≈7.5), f=0 at L=1.0. Larger n = faster rolloff into highlights.
// Yellow n=0.22: chroma peaks at V=9 (L≈0.90) — rolloff only in the last 10%.
// Yellow-Green n=0.27: slowest — stays colorful deep into highlights.
// Orange n=0.81: fastest — strong highlight desaturation, matches Munsell data.
#define HB_ROLL_N_RED     0.74
#define HB_ROLL_N_ORANGE  0.81
#define HB_ROLL_N_AMBER   0.74
#define HB_ROLL_N_YELLOW  0.22
#define HB_ROLL_N_GREEN   0.27
#define HB_ROLL_N_TEAL    0.42
#define HB_ROLL_N_CYAN    0.59
#define HB_ROLL_N_AZURE   0.67
#define HB_ROLL_N_BLUE    0.59
#define HB_ROLL_N_VIOLET  0.67
#define HB_ROLL_N_MAGENTA 0.74
#define HB_ROLL_N_ROSE    0.74

// 6-band Oklab hue dispatcher (normalized 0–1). Used by grade.fx and corrective.fx.
float GetBandCenter(int b)
{
    b = clamp(b, 0, 5);
    if (b == 0) return HB_BAND_RED;
    if (b == 1) return HB_BAND_YELLOW;
    if (b == 2) return HB_BAND_GREEN;
    if (b == 3) return HB_BAND_CYAN;
    if (b == 4) return HB_BAND_BLUE;
    return HB_BAND_MAGENTA;
}

float HueBandRollN(float hue)
{
    hue = frac(hue);
    float w0  = HueBandWeight(hue, HB_BAND_RED);
    float w1  = HueBandWeight(hue, HB_BAND_ORANGE);
    float w2  = HueBandWeight(hue, HB_BAND_AMBER);
    float w3  = HueBandWeight(hue, HB_BAND_YELLOW);
    float w4  = HueBandWeight(hue, HB_BAND_GREEN);
    float w5  = HueBandWeight(hue, HB_BAND_TEAL);
    float w6  = HueBandWeight(hue, HB_BAND_CYAN);
    float w7  = HueBandWeight(hue, HB_BAND_AZURE);
    float w8  = HueBandWeight(hue, HB_BAND_BLUE);
    float w9  = HueBandWeight(hue, HB_BAND_VIOLET);
    float w10 = HueBandWeight(hue, HB_BAND_MAGENTA);
    float w11 = HueBandWeight(hue, HB_BAND_ROSE);
    float num = w0  * HB_ROLL_N_RED     + w1  * HB_ROLL_N_ORANGE
              + w2  * HB_ROLL_N_AMBER   + w3  * HB_ROLL_N_YELLOW
              + w4  * HB_ROLL_N_GREEN   + w5  * HB_ROLL_N_TEAL
              + w6  * HB_ROLL_N_CYAN    + w7  * HB_ROLL_N_AZURE
              + w8  * HB_ROLL_N_BLUE    + w9  * HB_ROLL_N_VIOLET
              + w10 * HB_ROLL_N_MAGENTA + w11 * HB_ROLL_N_ROSE;
    return num / max(w0+w1+w2+w3+w4+w5+w6+w7+w8+w9+w10+w11, 1e-6);
}
