// highway.fxh — Data highway slot index
//
// BackBuffer row y=0 is the shared data bus. All scalar scene statistics
// are stored here by slot index. Effects read via ReadHWY(slot).
//
// Encoding: highway is 8-bit UNORM — all values must be in [0,1].
// Values outside [0,1] use a documented linear encoding; see column notes.
//
// Write order:
//   Slots   0–209  written by analysis_frame (or analysis_scope_pre)
//   Slots 210–255  written by corrective
//   Effects that run before corrective must not read slots 210+.

// ── analysis_scope_pre ────────────────────────────────────────────────────────
#define HWY_LUMA_HIST_START   0    // x=0..127  — pre-correction luma histogram
#define HWY_LUMA_MEAN_PRE   128    // pre-correction mean luma
#define HWY_LUMA_MEAN_POST  129    // post-correction mean luma (written by analysis_scope)
#define HWY_HUE_HIST_START  130    // x=130..193 — pre-correction hue histogram

// ── analysis_frame ────────────────────────────────────────────────────────────
#define HWY_P25             194    // scene p25 luma
#define HWY_P50             195    // scene p50 luma
#define HWY_P75             196    // scene p75 luma
#define HWY_SLOPE           197    // R90 chroma slope; encode: (v-1.0)/1.5  decode: v*1.5+1.0
#define HWY_MEAN_CHROMA     198    // scene mean Oklab C (saturated pixels only); raw [0,0.4]
#define HWY_SCENE_CUT       199    // scene cut signal [0,1]
#define HWY_P90             200    // scene p90 luma (specular floor tracker); raw [0,1]
#define HWY_CHROMA_ANGLE    201    // dominant hue angle; encode: (atan2(b,a)+π)/(2π)  decode: v*2π-π
#define HWY_ACHROM_FRAC     202    // fraction of pixels with Oklab C < 0.05 [0,1]

// ── corrective ────────────────────────────────────────────────────────────────
#define HWY_WARM_BIAS       210    // highlight warm bias EMA [0,1]
#define HWY_ZONE_KEY        211    // zone log key; raw [0,0.5] fits in [0,1]
#define HWY_ZONE_STD        212    // zone luminance std
#define HWY_STEVENS         213    // fc_stevens; encode: v/1.3  decode: v*1.3  range [0.72,1.22]

// ── Helper ───────────────────────────────────────────────────────────────────
#define ReadHWY(slot) \
    tex2Dlod(BackBuffer, float4(((slot) + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT, 0, 0)).r
