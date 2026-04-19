// veil.fx — Veiling glare: global luminance lift
//
// True veiling glare is a global effect — stray light inside the lens
// adds a roughly uniform offset to the entire sensor, proportional to
// scene average luminance. Bright scene = lifted shadows everywhere.
//
// This is physically correct and has no edge bleeding because there is
// no blur. Shadows lift, local contrast compresses, image gains depth.
//
// Two passes:
//   Pass 1: Walk LumHistTex (from frame_analysis) to compute scene
//           average luminance → AvgLumTex (1×1)
//   Pass 2: Add warm-tinted constant lift to every pixel

// ─── Tuning ────────────────────────────────────────────────────────────────

#define VEIL_STRENGTH  0.10    // 0–1; lift intensity (0.05–0.15 is subtle)
#define VEIL_WARMTH    0.5     // 0 = neutral tint, 1 = warm tint on lift

// ─── Internal constants ────────────────────────────────────────────────────

#define HIST_BINS  64

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

// ─── Average luminance result — 1×1 ───────────────────────────────────────

texture2D AvgLumTex { Width = 1; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D AvgLum
{
    Texture   = AvgLumTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
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

// ─── Pass 1 — Compute scene average luminance ──────────────────────────────

float4 ComputeAvgLumPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float weighted = 0.0;
    float total    = 0.0;

    [loop]
    for (int i = 0; i < HIST_BINS; i++)
    {
        float luma  = (i + 0.5) / float(HIST_BINS);
        float count = tex2Dlod(LumHist, float4((i + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r;
        weighted   += luma * count;
        total      += count;
    }

    float avg = (total > 0.001) ? weighted / total : 0.0;
    return float4(avg, 0, 0, 1);
}

// ─── Pass 2 — Apply global lift ────────────────────────────────────────────

float4 ApplyPS(float4 pos : SV_Position,
               float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2533 && pos.x < 2545 && pos.y > 15 && pos.y < 27)
        return float4(0.4, 0.6, 1.0, 1.0);

    float4 col     = tex2D(BackBuffer, uv);
    float  avg_lum = tex2D(AvgLum, float2(0.5, 0.5)).r;

    // Warm tint on the lift — slightly amber, like real lens scatter
    float3 tint = lerp(float3(1.0, 1.0, 1.0), float3(1.04, 1.00, 0.88), VEIL_WARMTH);
    float3 lift = avg_lum * VEIL_STRENGTH * tint;

    // Additive lift — shadows rise, highlights barely affected (already bright)
    float3 result = col.rgb + lift;

    return float4(saturate(result), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique Veil
{
    pass ComputeAvgLum
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeAvgLumPS;
        RenderTarget = AvgLumTex;
    }
    pass Apply
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyPS;
    }
}
