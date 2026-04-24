// alpha_zone_contrast.fx — Levels + S-curve luma contrast
//
// Expands tonal range by anchoring a smoothstep S-curve at the scene's
// own p10/p90. Shadows below p10 push darker; highlights above p90 push
// brighter; midtones between are gently stretched. No redistribution —
// the relative tonal relationships are preserved, not flattened.
//
// Applied multi-scale: curve runs on low-frequency luma (1/8 res) only.
// High-frequency detail (edges, texture) is added back unchanged.
//
// Three passes:
//   Pass 1 — BuildLevels: find p10/p90 from LumHistTex, lerp into
//             LevelsTex (1×1) for temporal stability.
//   Pass 2 — ComputeLowFreq: downsample BackBuffer luma to 1/8 res.
//   Pass 3 — ApplyContrast: S-curve on low-freq, reconstruct with
//             high-freq detail, scale RGB (hue+sat preserved).
//
// Requires frame_analysis.fx to run before this in the chain.

#define CURVE_STRENGTH  20      // 0–100; blend toward S-curve. 20 = technical baseline.
#define LERP_SPEED      10      // % per frame temporal smoothing for levels
#define HIST_BINS       64

// ─── Shared histogram texture — must match frame_analysis.fx exactly ───────
texture2D LumHistTex { Width = HIST_BINS; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumHist
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Scene levels (p10, p90) — 1×1, temporally smoothed ──────────────────
// .r = lo (p10), .g = hi (p90), .b = initialised flag
texture2D LevelsTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D LevelsSamp
{
    Texture   = LevelsTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Low-frequency luma — 1/8 resolution, bilinear upsampled on read ───────
texture2D LowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16F; MipLevels = 1; };
sampler2D LowFreqSamp
{
    Texture   = LowFreqTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

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

// ─── Vertex shader ─────────────────────────────────────────────────────────
void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ─── Pass 1 — Build scene levels (p10, p90) ────────────────────────────────

float4 BuildLevelsPS(float4 pos : SV_Position,
                     float2 uv  : TEXCOORD0) : SV_Target
{
    float total = 0.0;
    [loop]
    for (int i = 0; i < HIST_BINS; i++)
        total += tex2Dlod(LumHist, float4((i + 0.5) / HIST_BINS, 0.5, 0, 0)).r;

    float4 prev = tex2Dlod(LevelsSamp, float4(0.5, 0.5, 0, 0));
    if (total < 0.001) return float4(prev.r, prev.g, 1, 1);

    float cum = 0.0;
    float lo = 0.10, hi = 0.90;
    bool  found_lo = false;

    [loop]
    for (int j = 0; j < HIST_BINS; j++)
    {
        cum += tex2Dlod(LumHist, float4((j + 0.5) / HIST_BINS, 0.5, 0, 0)).r / total;
        if (!found_lo && cum >= 0.10) { lo = (j + 0.5) / HIST_BINS; found_lo = true; }
        if (cum >= 0.90) { hi = (j + 0.5) / HIST_BINS; break; }
    }

    float speed = (prev.b < 0.5) ? 1.0 : LERP_SPEED / 100.0;
    return float4(lerp(prev.r, lo, speed), lerp(prev.g, hi, speed), 1.0, 1.0);
}

// ─── Pass 2 — Downsample to low-frequency luma ─────────────────────────────

float4 ComputeLowFreqPS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    float2 px = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float luma = 0.0;
    luma += Luma(tex2Dlod(BackBuffer, float4(uv + float2(-1.5, -1.5) * px, 0, 0)).rgb);
    luma += Luma(tex2Dlod(BackBuffer, float4(uv + float2( 1.5, -1.5) * px, 0, 0)).rgb);
    luma += Luma(tex2Dlod(BackBuffer, float4(uv + float2(-1.5,  1.5) * px, 0, 0)).rgb);
    luma += Luma(tex2Dlod(BackBuffer, float4(uv + float2( 1.5,  1.5) * px, 0, 0)).rgb);
    return float4(luma * 0.25, 0, 0, 1);
}

// ─── Pass 3 — Apply levels S-curve, multi-scale ────────────────────────────
// Smoothstep anchored at p10/p90: shadows pushed darker, highlights brighter.
// Applied to low-freq luma only — fine detail reconstructed unchanged.

float4 ApplyContrastPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2473 && pos.x < 2485 && pos.y > 15 && pos.y < 27)
        return float4(0.0, 0.7, 0.7, 1.0);

    float4 col       = tex2D(BackBuffer, uv);
    float  luma_full = Luma(col.rgb);
    if (luma_full < 0.005) return col;

    float luma_low  = tex2D(LowFreqSamp, uv).r;
    float luma_high = luma_full - luma_low;

    float4 levels = tex2D(LevelsSamp, float2(0.5, 0.5));
    float lo = levels.r;
    float hi = levels.g;

    // Smoothstep S-curve: maps [lo,hi] → [0,1]; tails scale proportionally
    float t = saturate((luma_low - lo) / max(hi - lo, 0.01));
    float s = t * t * (3.0 - 2.0 * t);

    float new_luma_low = lerp(luma_low, s, CURVE_STRENGTH / 100.0);
    float new_luma     = max(0.001, new_luma_low + luma_high);
    float scale        = clamp(new_luma / luma_full, 0.0, 3.0);

    return float4(saturate(col.rgb * scale), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique AlphaZoneContrast
{
    pass BuildLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildLevelsPS;
        RenderTarget = LevelsTex;
    }
    pass ComputeLowFreq
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeLowFreqPS;
        RenderTarget = LowFreqTex;
    }
    pass ApplyContrast
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyContrastPS;
    }
}
