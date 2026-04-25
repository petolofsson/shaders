// alpha_chroma_lift.fx — Proportional saturation range recovery
//
// Boosts all non-grey pixel saturation by a fixed multiplier, with the
// multiplier scaling up for desaturated scenes. Proportional scaling
// preserves relative saturation relationships.
//
// Stats are derived from the BackBuffer this shader receives, ensuring
// mean/p10 reflect the post-primary_correction signal.
//
// Two passes:
//   Pass 1 — ComputeSatStats: sample BackBuffer in 8×8 grid → mean
//             saturation + binary-search p10 (grey gate) → SatStatsTex.
//   Pass 2 — ApplyChromaLift: proportional saturation boost, gated.

#define CURVE_STRENGTH  15     // 0–100; saturation boost. 15 = technical baseline.

// ─── Scene saturation stats — 1×1 RGBA16F ─────────────────────────────────
// .r = mean saturation, .g = p10 (grey gate)
texture2D SatStatsTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D SatStatsSamp
{
    Texture   = SatStatsTex;
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

// ─── Helpers ───────────────────────────────────────────────────────────────
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

// ─── Pass 1 — Compute scene saturation stats ──────────────────────────────
// Samples BackBuffer in 8×8 grid. Computes mean saturation and binary-
// searches for p10 (grey gate). Reads post-correction signal.

float4 ComputeSatStatsPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    // Mean saturation
    float sum = 0.0;
    [loop]
    for (int y = 0; y < 8; y++)
    [loop]
    for (int x = 0; x < 8; x++)
    {
        float3 rgb = tex2Dlod(BackBuffer, float4((x + 0.5) / 8.0, (y + 0.5) / 8.0, 0, 0)).rgb;
        sum += RGBtoHSV(rgb).y;
    }
    float mean_sat = sum / 64.0;

    // Binary search for p10 (grey gate)
    float lo = 0.0, hi = 1.0;
    [loop]
    for (int i = 0; i < 6; i++)
    {
        float mid = (lo + hi) * 0.5;
        float below = 0.0;
        [loop]
        for (int y2 = 0; y2 < 8; y2++)
        [loop]
        for (int x2 = 0; x2 < 8; x2++)
        {
            float3 rgb = tex2Dlod(BackBuffer, float4((x2 + 0.5) / 8.0, (y2 + 0.5) / 8.0, 0, 0)).rgb;
            below += (RGBtoHSV(rgb).y < mid) ? 1.0 : 0.0;
        }
        if (below / 64.0 < 0.10) lo = mid; else hi = mid;
    }
    float p10 = (lo + hi) * 0.5;

    return float4(mean_sat, p10, 0, 1);
}

// ─── Pass 2 — Apply proportional saturation boost ─────────────────────────

float4 ApplyChromaLiftPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2488 && pos.x < 2500 && pos.y > 15 && pos.y < 27)
        return float4(0.9, 0.3, 0.1, 1.0);

    float4 col = tex2D(BackBuffer, uv);

    if (pos.y < 1.0) return col;
    float3 hsv = RGBtoHSV(col.rgb);

    float2 stats    = tex2D(SatStatsSamp, float2(0.5, 0.5)).rg;
    float mean_sat  = stats.r;
    float gate_sat  = max(stats.g, 0.005);

    float gate = smoothstep(gate_sat * 0.5, gate_sat * 2.0, hsv.y);
    if (gate < 0.001) return col;

    float deficit  = max(0.0, 0.22 - mean_sat);
    float boost    = 1.0 + (CURVE_STRENGTH / 100.0) * (deficit / 0.22);
    float new_sat  = min(hsv.y * boost, 1.0);

    float3 result = HSVtoRGB(float3(hsv.x, lerp(hsv.y, new_sat, gate), hsv.z));
    return float4(saturate(result), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique AlphaChromaLift
{
    pass ComputeSatStats
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeSatStatsPS;
        RenderTarget = SatStatsTex;
    }
    pass ApplyChromaLift
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyChromaLiftPS;
    }
}
