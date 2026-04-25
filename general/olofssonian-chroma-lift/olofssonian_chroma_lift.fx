// olofssonian_chroma_lift.fx — Per-frame adaptive chroma S-curve
//
// Scene-adaptive saturation contrast via percentile-pivoted S-curves.
// Analogous to OlofssonianZoneContrast but operating on HSV saturation.
//
// Six hue bands — one per primary/secondary color, 60° each with smooth overlap:
//   Red (0°), Yellow (60°), Green (120°), Cyan (180°), Blue (240°), Magenta (300°)
//
// Pass 1: 64 Halton-sampled pixels per frame. Computes per-band weighted mean
//         and variance (E[x²]-E[x]² identity). Lerps into ChromaHistoryTex.
// Pass 2: Per-band S-curve using Normal distribution percentile approximation:
//         p25 = mean - 0.674*stddev, p50 = mean, p75 = mean + 0.674*stddev.

// ─── Tuning ────────────────────────────────────────────────────────────────
#include "creative_values.fx"
#define LERP_SPEED      8      // 0–100; adaptation speed
#define BAND_WIDTH      15     // 0–100; hue band overlap width
#define MIN_WEIGHT      1.0
#define SAT_THRESHOLD   5      // 0–100; minimum saturation to process
#define GREEN_HUE_COOL  (4.0 / 360.0)

#define BAND_RED     (0.0   / 360.0)
#define BAND_YELLOW  (60.0  / 360.0)
#define BAND_GREEN   (120.0 / 360.0)
#define BAND_CYAN    (180.0 / 360.0)
#define BAND_BLUE    (240.0 / 360.0)
#define BAND_MAGENTA (300.0 / 360.0)

// ─── Textures ──────────────────────────────────────────────────────────────

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// History texture — 8x4 RGBA16F, row 0 only, one texel per band (6 texels)
//   R = mean saturation, G = stddev, B = weight sum
texture2D ChromaHistoryTex
{
    Width     = 8;
    Height    = 4;
    Format    = RGBA16F;
    MipLevels = 1;
};
sampler2D ChromaHistory
{
    Texture   = ChromaHistoryTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Halton(2,3) sample table — 256 pre-computed UV points ─────────────────

uniform int FRAME_COUNT < source = "framecount"; >;

static const float2 kHalton[256] = {
    float2(0.500000, 0.333333),
    float2(0.250000, 0.666667),
    float2(0.750000, 0.111111),
    float2(0.125000, 0.444444),
    float2(0.625000, 0.777778),
    float2(0.375000, 0.222222),
    float2(0.875000, 0.555556),
    float2(0.062500, 0.888889),
    float2(0.562500, 0.037037),
    float2(0.312500, 0.370370),
    float2(0.812500, 0.703704),
    float2(0.187500, 0.148148),
    float2(0.687500, 0.481481),
    float2(0.437500, 0.814815),
    float2(0.937500, 0.259259),
    float2(0.031250, 0.592593),
    float2(0.531250, 0.925926),
    float2(0.281250, 0.074074),
    float2(0.781250, 0.407407),
    float2(0.156250, 0.740741),
    float2(0.656250, 0.185185),
    float2(0.406250, 0.518519),
    float2(0.906250, 0.851852),
    float2(0.093750, 0.296296),
    float2(0.593750, 0.629630),
    float2(0.343750, 0.962963),
    float2(0.843750, 0.012346),
    float2(0.218750, 0.345679),
    float2(0.718750, 0.679012),
    float2(0.468750, 0.123457),
    float2(0.968750, 0.456790),
    float2(0.015625, 0.790123),
    float2(0.515625, 0.234568),
    float2(0.265625, 0.567901),
    float2(0.765625, 0.901235),
    float2(0.140625, 0.049383),
    float2(0.640625, 0.382716),
    float2(0.390625, 0.716049),
    float2(0.890625, 0.160494),
    float2(0.078125, 0.493827),
    float2(0.578125, 0.827160),
    float2(0.328125, 0.271605),
    float2(0.828125, 0.604938),
    float2(0.203125, 0.938272),
    float2(0.703125, 0.086420),
    float2(0.453125, 0.419753),
    float2(0.953125, 0.753086),
    float2(0.046875, 0.197531),
    float2(0.546875, 0.530864),
    float2(0.296875, 0.864198),
    float2(0.796875, 0.308642),
    float2(0.171875, 0.641975),
    float2(0.671875, 0.975309),
    float2(0.421875, 0.024691),
    float2(0.921875, 0.358025),
    float2(0.109375, 0.691358),
    float2(0.609375, 0.135802),
    float2(0.359375, 0.469136),
    float2(0.859375, 0.802469),
    float2(0.234375, 0.246914),
    float2(0.734375, 0.580247),
    float2(0.484375, 0.913580),
    float2(0.984375, 0.061728),
    float2(0.007812, 0.395062),
    float2(0.507812, 0.728395),
    float2(0.257812, 0.172840),
    float2(0.757812, 0.506173),
    float2(0.132812, 0.839506),
    float2(0.632812, 0.283951),
    float2(0.382812, 0.617284),
    float2(0.882812, 0.950617),
    float2(0.070312, 0.098765),
    float2(0.570312, 0.432099),
    float2(0.320312, 0.765432),
    float2(0.820312, 0.209877),
    float2(0.195312, 0.543210),
    float2(0.695312, 0.876543),
    float2(0.445312, 0.320988),
    float2(0.945312, 0.654321),
    float2(0.039062, 0.987654),
    float2(0.539062, 0.004115),
    float2(0.289062, 0.337449),
    float2(0.789062, 0.670782),
    float2(0.164062, 0.115226),
    float2(0.664062, 0.448560),
    float2(0.414062, 0.781893),
    float2(0.914062, 0.226337),
    float2(0.101562, 0.559671),
    float2(0.601562, 0.893004),
    float2(0.351562, 0.041152),
    float2(0.851562, 0.374486),
    float2(0.226562, 0.707819),
    float2(0.726562, 0.152263),
    float2(0.476562, 0.485597),
    float2(0.976562, 0.818930),
    float2(0.023438, 0.263374),
    float2(0.523438, 0.596708),
    float2(0.273438, 0.930041),
    float2(0.773438, 0.078189),
    float2(0.148438, 0.411523),
    float2(0.648438, 0.744856),
    float2(0.398438, 0.189300),
    float2(0.898438, 0.522634),
    float2(0.085938, 0.855967),
    float2(0.585938, 0.300412),
    float2(0.335938, 0.633745),
    float2(0.835938, 0.967078),
    float2(0.210938, 0.016461),
    float2(0.710938, 0.349794),
    float2(0.460938, 0.683128),
    float2(0.960938, 0.127572),
    float2(0.054688, 0.460905),
    float2(0.554688, 0.794239),
    float2(0.304688, 0.238683),
    float2(0.804688, 0.572016),
    float2(0.179688, 0.905350),
    float2(0.679688, 0.053498),
    float2(0.429688, 0.386831),
    float2(0.929688, 0.720165),
    float2(0.117188, 0.164609),
    float2(0.617188, 0.497942),
    float2(0.367188, 0.831276),
    float2(0.867188, 0.275720),
    float2(0.242188, 0.609053),
    float2(0.742188, 0.942387),
    float2(0.492188, 0.090535),
    float2(0.992188, 0.423868),
    float2(0.003906, 0.757202),
    float2(0.503906, 0.201646),
    float2(0.253906, 0.534979),
    float2(0.753906, 0.868313),
    float2(0.128906, 0.312757),
    float2(0.628906, 0.646091),
    float2(0.378906, 0.979424),
    float2(0.878906, 0.028807),
    float2(0.066406, 0.362140),
    float2(0.566406, 0.695473),
    float2(0.316406, 0.139918),
    float2(0.816406, 0.473251),
    float2(0.191406, 0.806584),
    float2(0.691406, 0.251029),
    float2(0.441406, 0.584362),
    float2(0.941406, 0.917695),
    float2(0.035156, 0.065844),
    float2(0.535156, 0.399177),
    float2(0.285156, 0.732510),
    float2(0.785156, 0.176955),
    float2(0.160156, 0.510288),
    float2(0.660156, 0.843621),
    float2(0.410156, 0.288066),
    float2(0.910156, 0.621399),
    float2(0.097656, 0.954733),
    float2(0.597656, 0.102881),
    float2(0.347656, 0.436214),
    float2(0.847656, 0.769547),
    float2(0.222656, 0.213992),
    float2(0.722656, 0.547325),
    float2(0.472656, 0.880658),
    float2(0.972656, 0.325103),
    float2(0.019531, 0.658436),
    float2(0.519531, 0.991770),
    float2(0.269531, 0.008230),
    float2(0.769531, 0.341564),
    float2(0.144531, 0.674897),
    float2(0.644531, 0.119342),
    float2(0.394531, 0.452675),
    float2(0.894531, 0.786008),
    float2(0.082031, 0.230453),
    float2(0.582031, 0.563786),
    float2(0.332031, 0.897119),
    float2(0.832031, 0.045267),
    float2(0.207031, 0.378601),
    float2(0.707031, 0.711934),
    float2(0.457031, 0.156379),
    float2(0.957031, 0.489712),
    float2(0.050781, 0.823045),
    float2(0.550781, 0.267490),
    float2(0.300781, 0.600823),
    float2(0.800781, 0.934156),
    float2(0.175781, 0.082305),
    float2(0.675781, 0.415638),
    float2(0.425781, 0.748971),
    float2(0.925781, 0.193416),
    float2(0.113281, 0.526749),
    float2(0.613281, 0.860082),
    float2(0.363281, 0.304527),
    float2(0.863281, 0.637860),
    float2(0.238281, 0.971193),
    float2(0.738281, 0.020576),
    float2(0.488281, 0.353909),
    float2(0.988281, 0.687243),
    float2(0.011719, 0.131687),
    float2(0.511719, 0.465021),
    float2(0.261719, 0.798354),
    float2(0.761719, 0.242798),
    float2(0.136719, 0.576132),
    float2(0.636719, 0.909465),
    float2(0.386719, 0.057613),
    float2(0.886719, 0.390947),
    float2(0.074219, 0.724280),
    float2(0.574219, 0.168724),
    float2(0.324219, 0.502058),
    float2(0.824219, 0.835391),
    float2(0.199219, 0.279835),
    float2(0.699219, 0.613169),
    float2(0.449219, 0.946502),
    float2(0.949219, 0.094650),
    float2(0.042969, 0.427984),
    float2(0.542969, 0.761317),
    float2(0.292969, 0.205761),
    float2(0.792969, 0.539095),
    float2(0.167969, 0.872428),
    float2(0.667969, 0.316872),
    float2(0.417969, 0.650206),
    float2(0.917969, 0.983539),
    float2(0.105469, 0.032922),
    float2(0.605469, 0.366255),
    float2(0.355469, 0.699588),
    float2(0.855469, 0.144033),
    float2(0.230469, 0.477366),
    float2(0.730469, 0.810700),
    float2(0.480469, 0.255144),
    float2(0.980469, 0.588477),
    float2(0.027344, 0.921811),
    float2(0.527344, 0.069959),
    float2(0.277344, 0.403292),
    float2(0.777344, 0.736626),
    float2(0.152344, 0.181070),
    float2(0.652344, 0.514403),
    float2(0.402344, 0.847737),
    float2(0.902344, 0.292181),
    float2(0.089844, 0.625514),
    float2(0.589844, 0.958848),
    float2(0.339844, 0.106996),
    float2(0.839844, 0.440329),
    float2(0.214844, 0.773663),
    float2(0.714844, 0.218107),
    float2(0.464844, 0.551440),
    float2(0.964844, 0.884774),
    float2(0.058594, 0.329218),
    float2(0.558594, 0.662551),
    float2(0.308594, 0.995885),
    float2(0.808594, 0.001372),
    float2(0.183594, 0.334705),
    float2(0.683594, 0.668038),
    float2(0.433594, 0.112483),
    float2(0.933594, 0.445816),
    float2(0.121094, 0.779150),
    float2(0.621094, 0.223594),
    float2(0.371094, 0.556927),
    float2(0.871094, 0.890261),
    float2(0.246094, 0.038409),
    float2(0.746094, 0.371742),
    float2(0.496094, 0.705075),
    float2(0.996094, 0.149520),
    float2(0.001953, 0.482853)
};

float GetBandCenter(int b)
{
    if (b == 0) return BAND_RED;
    if (b == 1) return BAND_YELLOW;
    if (b == 2) return BAND_GREEN;
    if (b == 3) return BAND_CYAN;
    if (b == 4) return BAND_BLUE;
    return BAND_MAGENTA;
}

// ─── Vertex shader ─────────────────────────────────────────────────────────

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ─── Helpers ───────────────────────────────────────────────────────────────

float3 RGBtoHSV(float3 c)
{
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float  d = q.x - min(q.w, q.y);
    float  e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 HSVtoRGB(float3 c)
{
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

float HueBandWeight(float hue, float center)
{
    float d = abs(hue - center);
    d = min(d, 1.0 - d);
    return saturate(1.0 - d / (BAND_WIDTH / 100.0));
}

float PivotedSCurve(float x, float m, float strength)
{
    float t    = x - m;
    float bent = t + strength * t * (1.0 - saturate(abs(t)));
    return saturate(m + bent);
}

// ─── Pass 1 — Sample 64 Halton points, compute per-band mean/stddev ────────

float4 UpdateHistoryPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    int band_idx = int(pos.x);
    if (pos.y >= 1.0 || band_idx >= 6) return float4(0, 0, 0, 0);

    int   base_idx = (FRAME_COUNT % 128);
    float sum_w    = 0.0;
    float sum_ws   = 0.0;
    float sum_ws2  = 0.0;

    for (int i = 0; i < 64; i++)
    {
        float2 s_uv  = kHalton[(base_idx + i) % 256];
        float3 rgb   = tex2Dlod(BackBuffer, float4(s_uv, 0, 0)).rgb;
        float3 hsv_s = RGBtoHSV(rgb);

        float w    = HueBandWeight(hsv_s.x, GetBandCenter(band_idx)) + MIN_WEIGHT;
        float s    = hsv_s.y;
        sum_w   += w;
        sum_ws  += w * s;
        sum_ws2 += w * s * s;
    }

    float mean   = sum_ws  / max(sum_w, 0.001);
    float var    = max(sum_ws2 / max(sum_w, 0.001) - mean * mean, 0.0);
    float stddev = sqrt(var);

    float4 prev      = tex2D(ChromaHistory, float2((band_idx + 0.5) / 8.0, 0.5 / 4.0));
    float  new_mean  = lerp(prev.r, mean,   LERP_SPEED / 100.0);
    float  new_std   = lerp(prev.g, stddev, LERP_SPEED / 100.0);
    float  new_wsum  = lerp(prev.b, sum_w,  LERP_SPEED / 100.0);

    return float4(new_mean, new_std, new_wsum, 1.0);
}

// ─── Pass 2 — Apply per-band saturation S-curves ───────────────────────────

float4 ApplyChromaPS(float4 pos : SV_Position,
                     float2 uv  : TEXCOORD0) : SV_Target
{
    // Debug box — must be first so compile failures don't hide it
    if (pos.x > 2504 && pos.x < 2516 && pos.y > 15 && pos.y < 27)
        return float4(1.0, 0.0, 0.0, 1.0);

    float4 col = tex2D(BackBuffer, uv);
    float3 hsv = RGBtoHSV(col.rgb);

    if (hsv.y < SAT_THRESHOLD / 100.0) return col;

    float new_sat = 0.0;
    float total_w = 0.0;
    float green_w = 0.0;

    for (int b = 0; b < 6; b++)
    {
        float w        = HueBandWeight(hsv.x, GetBandCenter(b));
        float2 hist_uv = float2((b + 0.5) / 8.0, 0.5 / 4.0);
        float4 hist    = tex2D(ChromaHistory, hist_uv);

        float mean   = hist.r;
        float stddev = hist.g;
        float p25    = max(mean - 0.674 * stddev, 0.0);
        float p50    = mean;
        float p75    = min(mean + 0.674 * stddev, 1.0);

        float band_s = PivotedSCurve(hsv.y, p50, CHROMA_STRENGTH / 100.0);

        new_sat += band_s * w;
        total_w += w;

        if (b == 2) green_w = w;  // GREEN band
    }

    float final_sat = (total_w > 0.001) ? new_sat / total_w : hsv.y;

    // Nudge green-band hues 4° toward cyan
    float final_hue = hsv.x - GREEN_HUE_COOL * green_w * final_sat;

    float3 result = HSVtoRGB(float3(final_hue, final_sat, hsv.z));
    return float4(result, col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique OlofssonianChromaLift
{
    pass UpdateHistory
    {
        VertexShader = PostProcessVS;
        PixelShader  = UpdateHistoryPS;
        RenderTarget = ChromaHistoryTex;
    }
    pass ApplyChroma
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyChromaPS;
    }
}
