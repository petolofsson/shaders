// creative_render_chain.fx — Creative chain (game-agnostic)
//
// Runs after corrective_render_chain on display-referred [0,1] BackBuffer.
// Zone contrast + chroma lift, tuned via creative_values.fx.
//
// Pass 1  ComputeLowFreq     BackBuffer → CreativeLowFreqTex      1/8 res downsample
// Pass 2  ComputeZoneHist    CreativeLowFreq → CreativeZoneHistTex 32-bin per-zone histogram
// Pass 3  BuildZoneLevels    CreativeZoneHist → CreativeZoneLevelsTex CDF → zone medians
// Pass 4  ApplyContrast      BackBuffer → BackBuffer               zone S-curve (ZONE_STRENGTH)
// Pass 5  BuildSatLevels     SatHistTex → CreativeSatLevelsTex     CDF → per-band sat medians
// Pass 6  ApplyChroma        BackBuffer → BackBuffer               per-hue sat S-curve (CHROMA_STRENGTH)

#include "creative_values.fx"

// ZONE_STRENGTH and CHROMA_STRENGTH come from creative_values.fx (0–100, 0=passthrough)

#define ZONE_LERP_SPEED   4.3
#define ZONE_HIST_LERP    4.3

uniform float frametime < source = "frametime"; >;

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

texture2D CreativeLowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; MipLevels = 1; };
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

// ─── Vertex shader ───────────────────────────────────────────────────────────

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ─── Shared helpers ──────────────────────────────────────────────────────────

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float SCurve(float x, float m, float strength)
{
    float p = 1.0 + strength * 2.0;
    if (x < m)
    {
        float t = x / max(m, 0.001);
        return m * pow(t, p);
    }
    else
    {
        float t = (x - m) / max(1.0 - m, 0.001);
        return m + (1.0 - m) * (1.0 - pow(1.0 - t, p));
    }
}

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


// ═══ Pixel shaders ════════════════════════════════════════════════════════════

// Pass 1 — 1/8 res downsample of BackBuffer
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

// Pass 2 — per-zone 32-bin luma histogram
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

    float v    = count / 100.0;
    float prev = tex2Dlod(CreativeZoneHistSamp,
        float4((float(b) + 0.5) / 32.0, (float(zone) + 0.5) / 16.0, 0, 0)).r;
    float h    = lerp(prev, v, (ZONE_HIST_LERP / 100.0) * (frametime / 10.0));
    return float4(h, h, h, 1.0);
}

// Pass 3 — CDF walk → zone medians
float4 BuildZoneLevelsPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    int zone_x = int(pos.x);
    int zone_y = int(pos.y);
    int zone   = zone_y * 4 + zone_x;

    float2 prev_uv = float2((float(zone_x) + 0.5) / 4.0, (float(zone_y) + 0.5) / 4.0);
    float4 prev    = tex2Dlod(CreativeZoneLevelsSamp, float4(prev_uv, 0, 0));
    float  speed   = (prev.r < 0.001) ? 1.0 : (ZONE_LERP_SPEED / 100.0) * (frametime / 10.0);

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

    return float4(lerp(prev.r, median, speed),
                  lerp(prev.g, p25,    speed),
                  lerp(prev.b, p75,    speed),
                  1.0);
}

// Pass 4 — Zone S-curve anchored at zone median
float4 ApplyContrastPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;  // data highway

    // Debug indicator — purple (slot 3)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 36) && pos.x < float(BUFFER_WIDTH - 24))
        return float4(0.7, 0.20, 1.0, 1.0);

    float luma = Luma(col.rgb);

    float4 zone_levels = tex2D(CreativeZoneLevelsSamp, uv);
    float  zone_median = zone_levels.r;
    float  zone_iqr    = saturate(zone_levels.b - zone_levels.g);

    float t        = luma * 2.0 - 1.0;
    float tonal_w  = 1.0 - t * t;
    float strength = (ZONE_STRENGTH / 100.0) * tonal_w * (1.0 - zone_iqr);

    float new_luma = SCurve(luma, zone_median, strength);
    float scale    = new_luma / max(luma, 0.001);

    return float4(col.rgb * scale, col.a);
}

// Pass 5 — Multiplicative saturation lift
float4 ApplyChromaPS(float4 pos : SV_Position,
                     float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;  // data highway

    float3 hsv    = RGBtoHSV(col.rgb);
    float  sat_w  = smoothstep(0.0, 0.15, hsv.y);
    float  boost  = (CHROMA_STRENGTH / 100.0) * sat_w;
    float  new_sat = saturate(hsv.y * (1.0 + boost));
    float3 result = HSVtoRGB(float3(hsv.x, new_sat, hsv.z));

    return float4(result, col.a);
}

// ─── Technique ───────────────────────────────────────────────────────────────

technique CreativeRenderChain
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
    pass ApplyContrast
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyContrastPS;
    }
    pass ApplyChroma
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyChromaPS;
    }
}
