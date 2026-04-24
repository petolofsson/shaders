// primary_correction.fx — Input normalization + auto-exposure + adaptive highlight recovery
//
// Step 1 of the pipeline: white balance, auto-exposure, and adaptive inverse
// tone mapping to recover highlights compressed by the game's tone mapper.
//
// Auto-exposure:
//   Computes scene mean luminance from LumHistTex each frame. Scales the
//   image so the mean maps to TARGET_LUMA. Clamped to ±1.5 stops so extreme
//   scenes don't blow out or crush. Chain-length independent — no manual
//   re-calibration needed when shaders are added/removed.
//
// Inverse tone mapping:
//   Reads LumHistTex to find scene p95. If highlights are compressed,
//   a power curve expands them proportionally. Fully adaptive — zero
//   effect on uncompressed scenes.
//
// Two passes:
//   Pass 1 — ComputeExpansion: walk LumHistTex → scene mean, p95,
//             ITM power → ITMTex (1×1 RGBA16F)
//   Pass 2 — Apply: WB + auto-exposure + luma-gated highlight expansion

#define WB_R         100    // 0–200; 100 = neutral, >100 warmer, <100 cooler
#define WB_G         100
#define WB_B         100
#define TARGET_LUMA  0.18   // 0–1; scene mean luminance target (0.18 = 18% grey card)
#define ITM_STRENGTH 50     // 0–100; how aggressively to undo highlight compression

// ─── Internal constants ────────────────────────────────────────────────────

#define HIST_BINS  64

// ─── Shared histogram texture — previous frame, from frame_analysis ────────

texture2D LumHistTex { Width = HIST_BINS; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumHist
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Scene stats — 1×1 RGBA16F ────────────────────────────────────────────
// .r = ITM power, .g = p95, .b = scene mean luma

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

// ─── Pass 1 — Compute scene stats ─────────────────────────────────────────
// Loop 1: total count + weighted mean.
// Loop 2: cumulative for p95.

float4 ComputeExpansionPS(float4 pos : SV_Position,
                          float2 uv  : TEXCOORD0) : SV_Target
{
    float total = 0.0, weighted = 0.0;
    [loop]
    for (int i = 0; i < HIST_BINS; i++)
    {
        float luma  = (i + 0.5) / float(HIST_BINS);
        float count = tex2Dlod(LumHist, float4(luma, 0.5, 0, 0)).r;
        total    += count;
        weighted += luma * count;
    }

    if (total < 0.001) return float4(1.0, 1.0, TARGET_LUMA, 1);

    float scene_mean = weighted / total;

    float cumulative = 0.0;
    float p95        = 1.0;
    [loop]
    for (int j = 0; j < HIST_BINS; j++)
    {
        cumulative += tex2Dlod(LumHist, float4((j + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r / total;
        if (cumulative >= 0.95) { p95 = (j + 0.5) / float(HIST_BINS); break; }
    }

    float compression = saturate(1.0 - p95);
    float power       = 1.0 - compression * (ITM_STRENGTH / 100.0);

    return float4(power, p95, scene_mean, 1);
}

// ─── Pass 2 — Apply WB, auto-exposure, and adaptive highlight expansion ────

float4 PrimaryCorrectionPS(float4 pos : SV_Position,
                           float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2428 && pos.x < 2440 && pos.y > 15 && pos.y < 27)
        return float4(1.0, 1.0, 1.0, 1.0);

    float4 col = tex2D(BackBuffer, uv);

    float3 itm       = tex2D(ITMSamp, float2(0.5, 0.5)).rgb;
    float  power     = itm.r;
    float  p95       = itm.g;
    float  scene_mean = itm.b;

    // Auto-exposure: scale to hit TARGET_LUMA, clamped to ±1.5 stops
    float ae = clamp(TARGET_LUMA / max(scene_mean, 0.001), 0.35, 2.83);

    float3 c = col.rgb * float3(WB_R / 100.0, WB_G / 100.0, WB_B / 100.0) * ae;

    // Adaptive highlight expansion
    float luma_in = Luma(c);
    if (luma_in > 0.001 && power < 0.999)
    {
        float luma_out = pow(luma_in, power);
        float gate     = smoothstep(0.5, max(p95, 0.51), luma_in);
        float new_luma = lerp(luma_in, luma_out, gate);
        c *= new_luma / luma_in;
    }

    return float4(saturate(c), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique PrimaryCorrection
{
    pass ComputeExpansion
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeExpansionPS;
        RenderTarget = ITMTex;
    }
    pass Apply
    {
        VertexShader = PostProcessVS;
        PixelShader  = PrimaryCorrectionPS;
    }
}
