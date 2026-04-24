// primary_correction.fx — Signal range normalization with shadow-preserving toe
//
// Responsibility: expand the game's output to a full linear range so all
// downstream corrective stages receive a consistent, full-range signal.
//
// Method: p95 normalization with soft toe. The 95th-percentile luma maps to
// TARGET_P95 (0.90) via a per-pixel gain that tapers to 1.0 near the scene's
// black point (p5). Highlights get the full expansion; shadows are left
// progressively more intact, preserving atmospheric depth and dark-scene mood.
//
// Tonal shaping is NOT done here — that is alpha_zone's job.
// Saturation recovery is NOT done here — that is alpha_chroma's job.
//
// White balance (WB_R/G/B): neutral by default. Adjust only for games
// with a known persistent color cast.
//
// Two passes:
//   Pass 1 — ComputeStats: walk LumHistTex → p5 + p95 → ITMTex (1×1 RG16F)
//   Pass 2 — Apply: WB + soft-toe p95 normalization

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

// ─── Scene stats — 1×1 RG16F: .r = p95, .g = p5 ──────────────────────────

texture2D ITMTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
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

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ─── Pass 1 — Compute scene p5 and p95 ────────────────────────────────────

float4 ComputeStatsPS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    float total = 0.0;
    [loop]
    for (int i = 0; i < HIST_BINS; i++)
        total += tex2Dlod(LumHist, float4((i + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r;

    if (total < 0.001) return float4(TARGET_P95, 0.0, 0, 1);

    float cum      = 0.0;
    float p5       = 0.0;
    float p95      = TARGET_P95;
    bool  found_p5 = false;

    [loop]
    for (int j = 0; j < HIST_BINS; j++)
    {
        cum += tex2Dlod(LumHist, float4((j + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r / total;
        if (!found_p5 && cum >= 0.05) { p5  = (j + 0.5) / float(HIST_BINS); found_p5 = true; }
        if (cum >= 0.95)              { p95 = (j + 0.5) / float(HIST_BINS); break; }
    }

    return float4(p95, p5, 0, 1);
}

// ─── Pass 2 — Apply WB and soft-toe p95 normalization ─────────────────────

float4 PrimaryCorrectionPS(float4 pos : SV_Position,
                           float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2428 && pos.x < 2440 && pos.y > 15 && pos.y < 27)
        return float4(1.0, 1.0, 1.0, 1.0);

    float4 col = tex2D(BackBuffer, uv);

    float2 stats = tex2D(ITMSamp, float2(0.5, 0.5)).rg;
    float  p95   = stats.r;
    float  p5    = stats.g;

    float ae = clamp(TARGET_P95 / max(p95, 0.01), 0.35, 2.83);

    float3 c    = col.rgb * float3(WB_R / 100.0, WB_G / 100.0, WB_B / 100.0);
    float  luma = Luma(c);

    // Soft toe: full gain at highlights, tapers to 1.0 at the shadow floor.
    // Transition anchored to scene p5 — no exposed tuning constants.
    float toe_gate     = smoothstep(p5 * 0.5, max(p5 * 2.0, 0.02), luma);
    float effective_ae = lerp(1.0, ae, toe_gate);

    return float4(saturate(c * effective_ae), col.a);
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
