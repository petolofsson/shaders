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

#define KALMAN_Q     0.0001  // process noise: expected frame-to-frame variance
#define KALMAN_R     0.01    // measurement noise: estimator variance
#define KALMAN_K_INF 0.095   // steady-state gain for secondary channels
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

// ─── Halton(2,3) sequence — procedural, avoids static const array SPIR-V issue ──

float Halton2(uint i)
{
    float r = 0.0, f = 0.5;
    [unroll] for (int b = 0; b < 8; b++) { r += f * float(i & 1u); i >>= 1u; f *= 0.5; }
    return r;
}

float Halton3(uint i)
{
    float r = 0.0, f = 1.0 / 3.0;
    [unroll] for (int b = 0; b < 6; b++) { r += f * float(i % 3u); i /= 3u; f /= 3.0; }
    return r;
}

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

    // Kalman: zone median (.r) — P in .a, cold-start when uninitialized
    float P_prev = (prev.a < 0.001) ? 1.0 : prev.a;
    float P_pred = P_prev + KALMAN_Q;
    float K      = P_pred / (P_pred + KALMAN_R);
    float median = prev.r + K * (current.r - prev.r);
    float P_new  = (1.0 - K) * P_pred;

    // EMA: p25/p75 — steady-state gain
    float p25 = lerp(prev.g, current.g, KALMAN_K_INF);
    float p75 = lerp(prev.b, current.b, KALMAN_K_INF);

    return float4(median, p25, p75, P_new);
}

// ─── Pass 5 — per-band chroma stats ────────────────────────────────────────

float4 UpdateHistoryPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    int band_idx = int(pos.x);
    if (pos.y >= 1.0 || band_idx >= 7) return float4(0, 0, 0, 0);

    // Column 6: zone global stats (zone_log_key, zone_std, zmin, zmax) — free pixel, no chroma work
    if (band_idx == 6)
    {
        float lk = 0.0, m = 0.0, m2 = 0.0, zmin = 1.0, zmax = 0.0;
        [unroll] for (int zy = 0; zy < 4; zy++)
        [unroll] for (int zx = 0; zx < 4; zx++)
        {
            float zm = tex2Dlod(ZoneHistorySamp,
                float4((zx + 0.5) / 4.0, (zy + 0.5) / 4.0, 0, 0)).r;
            lk  += log(max(zm, 0.001));
            m   += zm;
            m2  += zm * zm;
            zmin = min(zmin, zm);
            zmax = max(zmax, zm);
        }
        float zavg = m * 0.0625;
        return float4(exp(lk * 0.0625),
                      sqrt(max(m2 * 0.0625 - zavg * zavg, 0.0)),
                      zmin, zmax);
    }

    uint  base_idx = uint(FRAME_COUNT * 8) % 256u;
    float sum_w    = 0.0;
    float sum_wc   = 0.0;
    float sum_wc2  = 0.0;

    [unroll] for (int i = 0; i < 8; i++)
    {
        uint   idx  = (base_idx + uint(i)) % 256u;
        float2 s_uv = float2(Halton2(idx), Halton3(idx));
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

    // Kalman: chroma mean (.r) — P in .a, cold-start when uninitialized
    float P_prev   = (prev.a < 0.001) ? 1.0 : prev.a;
    float P_pred   = P_prev + KALMAN_Q;
    float K        = P_pred / (P_pred + KALMAN_R);
    float new_mean = prev.r + K * (mean - prev.r);
    float P_new    = (1.0 - K) * P_pred;

    // EMA: std and wsum — steady-state gain
    float new_std  = lerp(prev.g, stddev, KALMAN_K_INF);
    float new_wsum = lerp(prev.b, sum_w,  KALMAN_K_INF);

    return float4(new_mean, new_std, new_wsum, P_new);
}

// ─── Pass 6 — Passthrough ──────────────────────────────────────────────────

float4 PassthroughPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 c = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return c;  // data highway
    c = DrawLabel(c, pos.xy, 270.0, 26.0,
                  51u, 67u, 79u, 82u, float3(0.1, 0.90, 0.1));  // 3COR
    c = DrawLabel(c, pos.xy, 270.0, 34.0,
                  52u, 90u, 79u, 78u, float3(0.7, 0.20, 1.0));  // 4ZON
    c = DrawLabel(c, pos.xy, 270.0, 42.0,
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
