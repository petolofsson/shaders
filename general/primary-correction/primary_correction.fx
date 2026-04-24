// primary_correction.fx — Signal range normalization
//
// Responsibility: expand the game's output to a full linear range so all
// downstream corrective stages receive a consistent, full-range signal.
//
// Method: p95 normalization. The 95th-percentile luma is mapped to 0.90
// via a single linear scale factor — the entire signal shifts proportionally.
// Clamped to ±1.5 stops to prevent overdriving extreme scenes.
//
// Tonal shaping is NOT done here — that is alpha_zone's job.
// Saturation recovery is NOT done here — that is alpha_chroma's job.
//
// White balance (WB_R/G/B): neutral by default. Adjust only for games
// with a known persistent color cast — not scene-adaptive.
//
// Two passes:
//   Pass 1 — ComputeStats: walk LumHistTex → p95 → ITMTex (1×1 R16F)
//   Pass 2 — Apply: WB + linear scale to TARGET_P95

#define WB_R       100    // 0–200; 100 = neutral
#define WB_G       100
#define WB_B       100
#define TARGET_P95 0.90   // p95 maps here; leaves headroom for output_transform

#define HIST_BINS  64

// ─── Shared histogram texture — written by frame_analysis ──────────────────

texture2D LumHistTex { Width = HIST_BINS; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumHist
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Scene p95 — 1×1 R16F ─────────────────────────────────────────────────

texture2D ITMTex { Width = 1; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D ITMSamp
{
    Texture   = ITMTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Textures ──────────────────────────────────────────────────────────────

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer { Texture = BackBufferTex; };

// ─── Vertex shader ─────────────────────────────────────────────────────────

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ─── Pass 1 — Compute scene p95 ────────────────────────────────────────────

float4 ComputeStatsPS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    float total = 0.0;
    [loop]
    for (int i = 0; i < HIST_BINS; i++)
        total += tex2Dlod(LumHist, float4((i + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r;

    if (total < 0.001) return float4(TARGET_P95, 0, 0, 1);

    float cumulative = 0.0;
    float p95        = TARGET_P95;
    [loop]
    for (int j = 0; j < HIST_BINS; j++)
    {
        cumulative += tex2Dlod(LumHist, float4((j + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r / total;
        if (cumulative >= 0.95) { p95 = (j + 0.5) / float(HIST_BINS); break; }
    }

    return float4(p95, 0, 0, 1);
}

// ─── Pass 2 — Apply WB and p95 normalization ───────────────────────────────

float4 PrimaryCorrectionPS(float4 pos : SV_Position,
                           float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2428 && pos.x < 2440 && pos.y > 15 && pos.y < 27)
        return float4(1.0, 1.0, 1.0, 1.0);

    float4 col = tex2D(BackBuffer, uv);

    float p95 = tex2D(ITMSamp, float2(0.5, 0.5)).r;
    float ae  = clamp(TARGET_P95 / max(p95, 0.01), 0.35, 2.83);

    float3 c = col.rgb * float3(WB_R / 100.0, WB_G / 100.0, WB_B / 100.0) * ae;

    return float4(saturate(c), col.a);
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
