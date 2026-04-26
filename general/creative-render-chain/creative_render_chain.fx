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

#define ZONE_LERP_SPEED  8    // 0–100; temporal adaptation speed (matches chroma)

texture2D ZoneHistoryTex { Width = 4; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D ZoneHistorySamp
{
    Texture   = ZoneHistoryTex;
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

    float v = count / 100.0;
    return float4(v, v, v, 1.0);
}

// Pass 3 — CDF walk → zone medians
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

// Pass 4 — Lerp fresh zone levels into history texture (temporal smoothing)
float4 SmoothZoneLevelsPS(float4 pos : SV_Position,
                          float2 uv  : TEXCOORD0) : SV_Target
{
    float4 current = tex2D(CreativeZoneLevelsSamp, uv);
    float4 prev    = tex2D(ZoneHistorySamp, uv);
    float  speed   = (prev.r < 0.001) ? 1.0 : (ZONE_LERP_SPEED / 100.0);
    return lerp(prev, current, speed);
}

// Pass 5 — Zone S-curve anchored at zone median
float4 ApplyContrastPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;  // data highway

    float luma        = Luma(col.rgb);
    float zone_median = tex2D(ZoneHistorySamp, uv).r;
    float strength   = ZONE_STRENGTH / 100.0;

    // Olofssonian pivoted S-curve — applied directly to pixel luma, anchored at zone_median.
    // Self-limiting: effect tapers to zero at extremes (true blacks/whites unaffected).
    // No LF-grid intermediary — no 8×8-block spatial artifacts in smooth bright areas.
    float dt       = luma - zone_median;
    float bent     = dt + strength * dt * (1.0 - saturate(abs(dt)));
    float new_luma = saturate(zone_median + bent);

    // Clarity — base/detail local contrast, midtone-focused (like Lightroom Clarity)
    // detail = deviation from 1/8-res base; mask peaks at midtones, tapers at shadows/highlights
    float low_luma     = tex2D(CreativeLowFreqSamp, uv).a;
    float detail       = luma - low_luma;
    float clarity_mask = smoothstep(0.0, 0.2, luma) * (1.0 - smoothstep(0.6, 0.9, luma));
    new_luma = saturate(new_luma + detail * clarity_mask * (CLARITY_STRENGTH / 100.0));

    // Shadow lift — expand dark range, tapers to zero at 0.4 luma
    float lift_w = smoothstep(0.4, 0.0, new_luma);
    new_luma     = saturate(new_luma + (SHADOW_LIFT / 100.0) * 0.15 * lift_w);

    float scale = new_luma / max(luma, 0.001);

    // Debug indicator — purple (slot 4)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 64) && pos.x < float(BUFFER_WIDTH - 52))
        return float4(0.7, 0.20, 1.0, 1.0);

    return float4(saturate(col.rgb * scale), col.a);
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
    pass SmoothZoneLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = SmoothZoneLevelsPS;
        RenderTarget = ZoneHistoryTex;
    }
    pass ApplyContrast
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyContrastPS;
    }
}
