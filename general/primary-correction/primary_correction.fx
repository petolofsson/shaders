// primary_correction.fx — Full linear range normalization
//
// Maps scene [p5, p95] → [0, 0.90] via a true levels stretch.
// Pixels at the scene's 5th percentile map to black; pixels at the
// 95th percentile map to 0.90. Everything in between scales linearly.
//
// Stats computed from BackBuffer directly (8×8 grid, binary search)
// to ensure they reflect the actual post-WB signal, not a stale histogram.
//
// White balance (WB_R/G/B): neutral by default.

#define WB_R       100    // 0–200; 100 = neutral
#define WB_G       100
#define WB_B       100
#define TARGET_P95 1.0

// ─── Scene stats — 1×1 RGBA16F: .r = p95, .g = p5 ────────────────────────

texture2D ITMTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D ITMSamp
{
    Texture   = ITMTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer { Texture = BackBufferTex; };

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ─── Pass 1 — Compute p5 and p95 from BackBuffer ──────────────────────────

float4 ComputeStatsPS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    // Binary search for p95
    float hi_lo = 0.0, hi_hi = 1.0;
    [loop]
    for (int i = 0; i < 8; i++)
    {
        float mid = (hi_lo + hi_hi) * 0.5;
        float below = 0.0;
        [loop]
        for (int y = 0; y < 8; y++)
        [loop]
        for (int x = 0; x < 8; x++)
        {
            float luma = Luma(tex2Dlod(BackBuffer,
                float4((x + 0.5) / 8.0, (y + 0.5) / 8.0, 0, 0)).rgb);
            below += (luma < mid) ? 1.0 : 0.0;
        }
        if (below / 64.0 < 0.95) hi_lo = mid; else hi_hi = mid;
    }
    float p95 = (hi_lo + hi_hi) * 0.5;

    // Binary search for p5
    float lo_lo = 0.0, lo_hi = 1.0;
    [loop]
    for (int j = 0; j < 8; j++)
    {
        float mid = (lo_lo + lo_hi) * 0.5;
        float below = 0.0;
        [loop]
        for (int y2 = 0; y2 < 8; y2++)
        [loop]
        for (int x2 = 0; x2 < 8; x2++)
        {
            float luma = Luma(tex2Dlod(BackBuffer,
                float4((x2 + 0.5) / 8.0, (y2 + 0.5) / 8.0, 0, 0)).rgb);
            below += (luma < mid) ? 1.0 : 0.0;
        }
        if (below / 64.0 < 0.05) lo_lo = mid; else lo_hi = mid;
    }
    float p5 = (lo_lo + lo_hi) * 0.5;

    return float4(p95, p5, 0, 1);
}

// ─── Pass 2 — Levels stretch [p5, p95] → [0, TARGET_P95] ─────────────────

float4 PrimaryCorrectionPS(float4 pos : SV_Position,
                           float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2428 && pos.x < 2440 && pos.y > 15 && pos.y < 27)
        return float4(1.0, 1.0, 1.0, 1.0);

    float4 col = tex2D(BackBuffer, uv);

    if (pos.y < 1.0) return col;

    float2 stats = tex2D(ITMSamp, float2(0.5, 0.5)).rg;
    float  p95   = stats.r;
    float  p5    = stats.g;

    float3 c    = col.rgb * float3(WB_R / 100.0, WB_G / 100.0, WB_B / 100.0);
    float  luma = Luma(c);

    float range     = max(p95 - p5, 0.01);
    float new_luma  = saturate((luma - p5) / range * TARGET_P95);
    float scale     = new_luma / max(luma, 0.001);

    return float4(saturate(c * scale), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique PrimaryCorrection
{
    pass ComputeStats
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeStatsPS;
        RenderTarget = ITMTex;
    }
    pass Apply
    {
        VertexShader = PostProcessVS;
        PixelShader  = PrimaryCorrectionPS;
    }
}
