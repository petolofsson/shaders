// alpha_zone_contrast.fx — Levels + S-curve luma contrast
//
// Expands tonal range by anchoring a smoothstep S-curve at the scene's
// own p10/p90. Shadows below p10 push darker; highlights above p90 push
// brighter; midtones between are gently stretched. Midtone at (p10+p90)/2
// is invariant — no grey lift.
//
// Applied multi-scale: curve runs on low-frequency luma (1/8 res) only.
// High-frequency detail (edges, texture) is added back unchanged.
//
// Stats are derived from the BackBuffer this shader receives — NOT from
// frame_analysis histograms. This ensures p10/p90 match the post-
// primary_correction signal, not the raw game output.
//
// Three passes:
//   Pass 1 — ComputeLowFreq: downsample BackBuffer luma to 1/8 res.
//   Pass 2 — BuildLevels: binary-search p10/p90 from LowFreqTex,
//             lerp into LevelsTex (1×1) for temporal stability.
//   Pass 3 — ApplyContrast: S-curve on low-freq, reconstruct with
//             high-freq detail, scale RGB (hue+sat preserved).

#define CURVE_STRENGTH  20      // 0–100; blend toward S-curve. 20 = technical baseline.
#define LERP_SPEED      10      // % per frame temporal smoothing for levels

// ─── Low-frequency luma — 1/8 resolution ───────────────────────────────────
texture2D LowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16F; MipLevels = 1; };
sampler2D LowFreqSamp
{
    Texture   = LowFreqTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
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

// ─── BackBuffer ────────────────────────────────────────────────────────────
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

// ─── Pass 1 — Downsample to low-frequency luma ─────────────────────────────

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

// ─── Pass 2 — Build scene levels via binary search on LowFreqTex ───────────
// Reads the post-correction signal (not frame_analysis histogram).
// Binary search over 8×8 grid samples: 6 iterations × 64 samples per percentile.

float4 BuildLevelsPS(float4 pos : SV_Position,
                     float2 uv  : TEXCOORD0) : SV_Target
{
    float4 prev = tex2Dlod(LevelsSamp, float4(0.5, 0.5, 0, 0));

    // Binary search for p10
    float lo_lo = 0.0, lo_hi = 1.0;
    [loop]
    for (int i = 0; i < 6; i++)
    {
        float mid = (lo_lo + lo_hi) * 0.5;
        float below = 0.0;
        [loop]
        for (int y = 0; y < 8; y++)
        [loop]
        for (int x = 0; x < 8; x++)
        {
            float val = tex2Dlod(LowFreqSamp, float4((x + 0.5) / 8.0, (y + 0.5) / 8.0, 0, 0)).r;
            below += (val < mid) ? 1.0 : 0.0;
        }
        if (below / 64.0 < 0.10) lo_lo = mid; else lo_hi = mid;
    }

    // Binary search for p90
    float hi_lo = 0.0, hi_hi = 1.0;
    [loop]
    for (int j = 0; j < 6; j++)
    {
        float mid = (hi_lo + hi_hi) * 0.5;
        float below = 0.0;
        [loop]
        for (int y = 0; y < 8; y++)
        [loop]
        for (int x = 0; x < 8; x++)
        {
            float val = tex2Dlod(LowFreqSamp, float4((x + 0.5) / 8.0, (y + 0.5) / 8.0, 0, 0)).r;
            below += (val < mid) ? 1.0 : 0.0;
        }
        if (below / 64.0 < 0.90) hi_lo = mid; else hi_hi = mid;
    }

    float lo = (lo_lo + lo_hi) * 0.5;
    float hi = (hi_lo + hi_hi) * 0.5;

    float speed = (prev.b < 0.5) ? 1.0 : LERP_SPEED / 100.0;
    return float4(lerp(prev.r, lo, speed), lerp(prev.g, hi, speed), 1.0, 1.0);
}

// ─── Pass 3 — Apply levels S-curve, multi-scale ────────────────────────────
// S-curve maps [lo,hi] → [lo,hi] with enhanced contrast. Midtone is invariant.
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

    // S-curve within [lo,hi]: midtone at (lo+hi)/2 is invariant.
    // Only engages when tonal range is compressed (spread < 0.7).
    float spread    = hi - lo;
    float compress  = saturate(1.0 - spread / 0.7);
    float strength  = (CURVE_STRENGTH / 100.0) * compress;

    float t = saturate((luma_low - lo) / max(spread, 0.01));
    float s = lo + (t * t * (3.0 - 2.0 * t)) * spread;

    float new_luma_low = lerp(luma_low, s, strength);
    float new_luma     = max(0.001, new_luma_low + luma_high);
    float scale        = clamp(new_luma / luma_full, 0.0, 3.0);

    return float4(saturate(col.rgb * scale), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique AlphaZoneContrast
{
    pass ComputeLowFreq
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeLowFreqPS;
        RenderTarget = LowFreqTex;
    }
    pass BuildLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildLevelsPS;
        RenderTarget = LevelsTex;
    }
    pass ApplyContrast
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyContrastPS;
    }
}
