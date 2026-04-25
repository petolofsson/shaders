// corrective_render_chain.fx — Display transform (game-agnostic)
//
//   Pass 1  CopyToSrc       BackBuffer    → CorrectiveSrcTex  (RGBA16F snapshot)
//   Pass 2  OutputTransform CorrectiveSrc → BackBuffer        Gamut compress + exposure normalize

#define OT_SAT_MAX   85
#define OT_SAT_BLEND 15

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

texture2D CorrectiveSrcTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 1; };
sampler2D CorrectiveSrc
{
    Texture   = CorrectiveSrcTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D PercTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D PercSamp
{
    Texture   = PercTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
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

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ═══ Pixel shaders ════════════════════════════════════════════════════════════

// Pass 1 — Snapshot BackBuffer into RGBA16F
float4 CopyToSrcPS(float4 pos : SV_Position,
                   float2 uv  : TEXCOORD0) : SV_Target
{
    return tex2D(BackBuffer, uv);
}

// Pass 2 — Gamut compress + exposure normalize
float4 OutputTransformPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;

    float3 rgb_out = col.rgb;

    // Percentile fetch — p50 from shared 1×1 cache (written by frame_analysis)
    float lum_p50 = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0)).g;

    // Gamut compression — clean up out-of-gamut from inverse_grade
    float luma_gc = Luma(rgb_out);
    float under   = saturate(-min(rgb_out.r, min(rgb_out.g, rgb_out.b)) * 10.0);
    rgb_out       = lerp(rgb_out, float3(luma_gc, luma_gc, luma_gc), under);

    float gc_max = max(rgb_out.r, max(rgb_out.g, rgb_out.b));
    float gc_min = min(rgb_out.r, min(rgb_out.g, rgb_out.b));
    float sat_gc = (gc_max > 0.001) ? (gc_max - gc_min) / gc_max : 0.0;
    float excess = max(0.0, sat_gc - OT_SAT_MAX / 100.0) / (1.0 - OT_SAT_MAX / 100.0);
    float gc_amt = excess * excess * (OT_SAT_BLEND / 100.0);
    rgb_out      = rgb_out + (gc_max - rgb_out) * gc_amt;

    // Exposure normalization — bring scene median to perceptual midgrey
    float exposure = clamp(0.40 / max(lum_p50, 0.001), 0.85, 1.5);
    rgb_out *= exposure;

    // Debug indicator — green (slot 2)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 50) && pos.x < float(BUFFER_WIDTH - 38))
        return float4(0.1, 0.90, 0.1, 1.0);
    return saturate(float4(rgb_out, col.a));
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique OlofssonianRenderChain
{
    pass CopyToSrc
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyToSrcPS;
        RenderTarget = CorrectiveSrcTex;
    }
    pass OutputTransform
    {
        VertexShader = PostProcessVS;
        PixelShader  = OutputTransformPS;
    }
}
