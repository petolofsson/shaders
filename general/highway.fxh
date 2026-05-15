// highway.fxh — Data highway slot index
//
// HighwayTex (256×1 R16F) is the shared data bus. Scene statistics are stored
// by slot index (x position). Effects read via ReadHWY(slot).
// HighwayTex and HighwaySamp declared here — every effect that includes this
// header shares the same GPU resource via matched name + format.
//
// Encoding: all values in [0,1]. Values outside that range use a linear
// encoding; see column notes.
//
// Write order (dedicated HighwayWritePS pass per effect, RenderTarget=HighwayTex):
//   Slots 194–202, 206–208  written by analysis_frame (HighwayWritePS, last pass)
//   Slots 203–205       written by corrective     (HighwayWritePS, last pass)
//   Both passes pass through the other's slots from the previous HighwayTex state.

texture2D HighwayTex { Width = 256; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D HighwaySamp
{
    Texture   = HighwayTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ── analysis_frame ────────────────────────────────────────────────────────────
#define HWY_P25             194    // scene p25 luma
#define HWY_P50             195    // scene p50 luma
#define HWY_P75             196    // scene p75 luma
#define HWY_CHROMA_SLOPE    197    // chroma expansion slope from median Oklab C: lerp(1.8,1.15,saturate(median_C/0.15)); encode: (v-1.0)/1.5  decode: v*1.5+1.0
#define HWY_MEDIAN_C        198    // scene median Oklab C (histogram p50, all pixels); raw [0, 0.30]
#define HWY_SCENE_CUT       199    // scene cut signal [0,1]
#define HWY_P90             200    // scene p90 luma (specular floor tracker); raw [0,1]
#define HWY_CHROMA_ANGLE    201    // mean hue angle (centroid of ab plane); encode: (atan2(b,a)+π)/(2π)  decode: v*2π-π
#define HWY_ACHROM_FRAC     202    // fraction of pixels with Oklab C < 0.05 [0,1]
#define HWY_MODE            206    // histogram mode (argmax bin center), EMA-smoothed [0,1]
#define HWY_H_NORM          207    // normalized histogram entropy [0,1]; 0=all mass one bin, 1=uniform
#define HWY_IQR             208    // IQR = p75 − p25 [0,1]; scene contrast width

// ── corrective ────────────────────────────────────────────────────────────────
#define HWY_ZONE_KEY        203    // zone_log_key — linear mean of zone medians [0,1]
#define HWY_ZONE_STD        204    // zone_std — mean intra-zone pixel variance [0,1]
#define HWY_SLOW_KEY        205    // slow ambient key EMA [0,1]

// ── Helper ───────────────────────────────────────────────────────────────────
#define ReadHWY(slot) \
    tex2Dlod(HighwaySamp, float4(((slot) + 0.5) / 256.0, 0.5, 0, 0)).r
