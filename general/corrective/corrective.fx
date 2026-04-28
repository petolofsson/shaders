// corrective.fx — Game-agnostic corrective analysis chain
#include "debug_text.fxh"
//
// Prepares all analysis textures consumed by grade.fx (MegaPass).
// Single vkBasalt effect — no inter-effect BackBuffer clears, no wasted Passthroughs.
//
// Passes:
//   1. ComputeLowFreq       BackBuffer → CreativeLowFreqTex    1/8 res downsample
//   2. ComputeZoneHistogram CreativeLowFreqTex → CreativeZoneHistTex  32-bin per-zone histogram
//   3. BuildZoneLevels      CreativeZoneHistTex → CreativeZoneLevelsTex  CDF → zone medians
//   4. SmoothZoneLevels     CreativeZoneLevelsTex → ZoneHistoryTex  temporal smoothing
//   5. UpdateHistory        BackBuffer → ChromaHistoryTex  per-band Oklab chroma stats
//   6. Passthrough          BackBuffer → BackBuffer  keeps BB non-black for vkBasalt

#include "creative_values.fx"

#define ZONE_LERP_SPEED  8
#define LERP_SPEED       8
#define BAND_WIDTH       8
#define MIN_WEIGHT       1.0
#define SAT_THRESHOLD    2

#define BAND_RED     0.083
#define BAND_YELLOW  0.305
#define BAND_GREEN   0.396
#define BAND_CYAN    0.542
#define BAND_BLUE    0.735
#define BAND_MAGENTA 0.913

uniform int FRAME_COUNT < source = "framecount"; >;

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

texture2D CreativeLowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; MipLevels = 3; };
sampler2D CreativeLowFreqSamp
{
    Texture   = CreativeLowFreqTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D CreativeZoneHistTex { Width = 32; Height = 16; Format = R16F; MipLevels = 1; };
sampler2D CreativeZoneHistSamp
{
    Texture   = CreativeZoneHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D CreativeZoneLevelsTex { Width = 4; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D CreativeZoneLevelsSamp
{
    Texture   = CreativeZoneLevelsTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D ZoneHistoryTex { Width = 4; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D ZoneHistorySamp
{
    Texture   = ZoneHistoryTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D ChromaHistoryTex { Width = 8; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D ChromaHistory
{
    Texture   = ChromaHistoryTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

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

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float3 RGBtoOklab(float3 rgb)
{
    float l = dot(rgb, float3(0.4122214708, 0.5363325363, 0.0514459929));
    float m = dot(rgb, float3(0.2119034982, 0.6806995451, 0.1073969566));
    float s = dot(rgb, float3(0.0883024619, 0.2817188376, 0.6299787005));

    l = sign(l) * pow(abs(l), 1.0 / 3.0);
    m = sign(m) * pow(abs(m), 1.0 / 3.0);
    s = sign(s) * pow(abs(s), 1.0 / 3.0);

    return float3(
        dot(float3(l, m, s), float3( 0.2104542553,  0.7936177850, -0.0040720468)),
        dot(float3(l, m, s), float3( 1.9779984951, -2.4285922050,  0.4505937099)),
        dot(float3(l, m, s), float3( 0.0259040371,  0.7827717662, -0.8086757660))
    );
}

float OklabHueNorm(float a, float b)
{
    float ay = abs(b) + 1e-10;
    float r  = (a - sign(a) * ay) / (ay + abs(a));
    float th = 1.5707963 - sign(a) * 0.7853982;
    th += (0.1963 * r * r - 0.9817) * r;
    return frac(sign(b + 1e-10) * th / 6.28318 + 1.0);
}

float HueBandWeight(float hue, float center)
{
    float d = abs(hue - center);
    d = min(d, 1.0 - d);
    return saturate(1.0 - d / (BAND_WIDTH / 100.0));
}

float GetBandCenter(int b)
{
    if (b == 0) return BAND_RED;
    if (b == 1) return BAND_YELLOW;
    if (b == 2) return BAND_GREEN;
    if (b == 3) return BAND_CYAN;
    if (b == 4) return BAND_BLUE;
    return BAND_MAGENTA;
}

// ─── Halton(2,3) sample table — 256 pre-computed UV points ─────────────────

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

// ─── Pass 1 — 1/8 res downsample ───────────────────────────────────────────

float4 ComputeLowFreqPS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    float2 px = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float3 rgb = 0.0;
    rgb += tex2Dlod(BackBuffer, float4(uv + float2(-1.5, -1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(BackBuffer, float4(uv + float2( 1.5, -1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(BackBuffer, float4(uv + float2(-1.5,  1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(BackBuffer, float4(uv + float2( 1.5,  1.5) * px, 0, 0)).rgb;
    rgb *= 0.25;
    return float4(rgb, Luma(rgb));
}

// ─── Pass 2 — per-zone 32-bin luma histogram ───────────────────────────────

float4 ComputeZoneHistogramPS(float4 pos : SV_Position,
                              float2 uv  : TEXCOORD0) : SV_Target
{
    int b        = int(pos.x);
    int zone     = int(pos.y);
    int zone_col = zone % 4;
    int zone_row = zone / 4;

    float u_lo      = float(zone_col) / 4.0;
    float v_lo      = float(zone_row) / 4.0;
    float bucket_lo = float(b)     / 32.0;
    float bucket_hi = float(b + 1) / 32.0;

    float count = 0.0;
    [loop] for (int sy = 0; sy < 10; sy++)
    [loop] for (int sx = 0; sx < 10; sx++)
    {
        float2 suv  = float2(u_lo + (sx + 0.5) / 10.0 * 0.25,
                             v_lo + (sy + 0.5) / 10.0 * 0.25);
        float  luma = tex2Dlod(CreativeLowFreqSamp, float4(suv, 0, 0)).a;
        count += (luma >= bucket_lo && luma < bucket_hi) ? 1.0 : 0.0;
    }

    float v = count / 100.0;
    return float4(v, v, v, 1.0);
}

// ─── Pass 3 — CDF walk → zone medians ──────────────────────────────────────

float4 BuildZoneLevelsPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    int zone_x = int(pos.x);
    int zone_y = int(pos.y);
    int zone   = zone_y * 4 + zone_x;

    float cumulative = 0.0;
    float p25 = 0.25, median = 0.5, p75 = 0.75;
    float lock25 = 0.0, lock50 = 0.0, lock75 = 0.0;

    [loop] for (int b = 0; b < 32; b++)
    {
        float bv   = float(b) / 32.0;
        float frac = tex2Dlod(CreativeZoneHistSamp,
            float4((float(b) + 0.5) / 32.0, (float(zone) + 0.5) / 16.0, 0, 0)).r;
        cumulative += frac;

        float at25 = step(0.25, cumulative) * (1.0 - lock25);
        float at50 = step(0.50, cumulative) * (1.0 - lock50);
        float at75 = step(0.75, cumulative) * (1.0 - lock75);
        p25    = lerp(p25,    bv, at25);
        median = lerp(median, bv, at50);
        p75    = lerp(p75,    bv, at75);
        lock25 = saturate(lock25 + at25);
        lock50 = saturate(lock50 + at50);
        lock75 = saturate(lock75 + at75);
    }

    return float4(median, p25, p75, 1.0);
}

// ─── Pass 4 — temporal smoothing ───────────────────────────────────────────

float4 SmoothZoneLevelsPS(float4 pos : SV_Position,
                          float2 uv  : TEXCOORD0) : SV_Target
{
    float4 current = tex2D(CreativeZoneLevelsSamp, uv);
    float4 prev    = tex2D(ZoneHistorySamp, uv);
    float  base    = ZONE_LERP_SPEED / 100.0;
    float  speed   = saturate(base * (1.0 + 10.0 * abs(current.r - prev.r)));
    return lerp(prev, current, speed);
}

// ─── Pass 5 — per-band chroma stats ────────────────────────────────────────

float4 UpdateHistoryPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    int band_idx = int(pos.x);
    if (pos.y >= 1.0 || band_idx >= 6) return float4(0, 0, 0, 0);

    int   base_idx = (FRAME_COUNT * 8) % 256;
    float sum_w    = 0.0;
    float sum_wc   = 0.0;
    float sum_wc2  = 0.0;

    for (int i = 0; i < 8; i++)
    {
        float2 s_uv = kHalton[(base_idx + i) % 256];
        float3 rgb  = tex2Dlod(BackBuffer, float4(s_uv, 0, 0)).rgb;
        float3 lab  = RGBtoOklab(rgb);
        float  C    = length(lab.yz);
        float  h    = OklabHueNorm(lab.y, lab.z);

        float w    = HueBandWeight(h, GetBandCenter(band_idx)) + MIN_WEIGHT;
        sum_w   += w;
        sum_wc  += w * C;
        sum_wc2 += w * C * C;
    }

    float mean   = sum_wc  / max(sum_w, 0.001);
    float var    = max(sum_wc2 / max(sum_w, 0.001) - mean * mean, 0.0);
    float stddev = sqrt(var);

    float4 prev    = tex2D(ChromaHistory, float2((band_idx + 0.5) / 8.0, 0.5 / 4.0));
    float delta_c  = abs(mean - prev.r);
    float speed_c  = saturate(LERP_SPEED / 100.0 * (1.0 + 10.0 * delta_c));
    float new_mean = lerp(prev.r, mean,   speed_c);
    float new_std  = lerp(prev.g, stddev, speed_c);
    float new_wsum = lerp(prev.b, sum_w,  speed_c);

    return float4(new_mean, new_std, new_wsum, 1.0);
}

// ─── Pass 6 — Passthrough ──────────────────────────────────────────────────

float4 PassthroughPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 c = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return c;  // data highway
    c = DrawLabel(c, pos, 270.0, 26.0,
                  51u, 67u, 79u, 82u, float3(0.1, 0.90, 0.1));  // 3COR
    c = DrawLabel(c, pos, 270.0, 34.0,
                  52u, 90u, 79u, 78u, float3(0.7, 0.20, 1.0));  // 4ZON
    c = DrawLabel(c, pos, 270.0, 42.0,
                  53u, 67u, 72u, 82u, float3(1.0, 0.20, 0.20)); // 5CHR
    return c;
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique Corrective
{
    pass ComputeLowFreq
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeLowFreqPS;
        RenderTarget = CreativeLowFreqTex;
    }
    pass ComputeZoneHistogram
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeZoneHistogramPS;
        RenderTarget = CreativeZoneHistTex;
    }
    pass BuildZoneLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildZoneLevelsPS;
        RenderTarget = CreativeZoneLevelsTex;
    }
    pass SmoothZoneLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = SmoothZoneLevelsPS;
        RenderTarget = ZoneHistoryTex;
    }
    pass UpdateHistory
    {
        VertexShader = PostProcessVS;
        PixelShader  = UpdateHistoryPS;
        RenderTarget = ChromaHistoryTex;
    }
    pass Passthrough
    {
        VertexShader = PostProcessVS;
        PixelShader  = PassthroughPS;
    }
}
