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

#define HB_CEIL_RED     0.28
#define HB_CEIL_ORANGE  0.16
#define HB_CEIL_AMBER   0.15
#define HB_CEIL_YELLOW  0.14
#define HB_CEIL_GREEN   0.16
#define HB_CEIL_TEAL    0.15
#define HB_CEIL_CYAN    0.15
#define HB_CEIL_AZURE   0.17
#define HB_CEIL_BLUE    0.19
#define HB_CEIL_VIOLET  0.20
#define HB_CEIL_MAGENTA 0.22
#define HB_CEIL_ROSE    0.22

float HueBandWeight(float hue, float center)
{
    float d = abs(hue - center);
    d = min(d, 1.0 - d);
    float t = saturate(1.0 - d / HB_BAND_WIDTH);
    return t * t * (3.0 - 2.0 * t);
}

// Returns the blended natural chroma ceiling at the given normalized hue.
// Apply as: new_C = min(new_C, max(HueCeil(hue), incoming_C))
// The max(ceil, incoming_C) guard preserves existing saturation above the
// ceiling — only expansion/lift above the natural maximum is blocked.
float HueCeil(float hue)
{
    return HueBandWeight(hue, HB_BAND_RED)     * HB_CEIL_RED
         + HueBandWeight(hue, HB_BAND_ORANGE)  * HB_CEIL_ORANGE
         + HueBandWeight(hue, HB_BAND_AMBER)   * HB_CEIL_AMBER
         + HueBandWeight(hue, HB_BAND_YELLOW)  * HB_CEIL_YELLOW
         + HueBandWeight(hue, HB_BAND_GREEN)   * HB_CEIL_GREEN
         + HueBandWeight(hue, HB_BAND_TEAL)    * HB_CEIL_TEAL
         + HueBandWeight(hue, HB_BAND_CYAN)    * HB_CEIL_CYAN
         + HueBandWeight(hue, HB_BAND_AZURE)   * HB_CEIL_AZURE
         + HueBandWeight(hue, HB_BAND_BLUE)    * HB_CEIL_BLUE
         + HueBandWeight(hue, HB_BAND_VIOLET)  * HB_CEIL_VIOLET
         + HueBandWeight(hue, HB_BAND_MAGENTA) * HB_CEIL_MAGENTA
         + HueBandWeight(hue, HB_BAND_ROSE)    * HB_CEIL_ROSE;
}
