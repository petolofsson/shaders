// corrective_render_chain.fx — Display transform (game-agnostic)
//
//   Pass 1  CopyToSrc       BackBuffer    → CorrectiveSrcTex  (RGBA16F snapshot)
//   Pass 2  OutputTransform CorrectiveSrc → BackBuffer        Scene-adaptive power curve

#include "creative_values.fx"

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

// Scene percentiles from analysis_frame_analysis (r=p25, g=p50, b=p75, a=iqr)
texture2D PercTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D PercSamp
{
    Texture   = PercTex;
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

// Scene-adaptive film S-curve. Shoulder knee driven by p75 (hot scenes compress more).
// Toe knee driven by p25 (dark scenes lift more). White→0.95, black→0.03. Maps [0,1]→[0,1].
float3 FilmCurve(float3 x, float p25, float p75)
{
    // Shoulder knee: 0.90 at p75=0.60 → 0.80 at p75=0.90 (hot scenes compress more)
    float knee   = lerp(0.90, 0.80, saturate((p75 - 0.60) / 0.30));
    float width  = 1.0 - knee;
    float factor = 0.05 / (width * width); // white always → 0.95

    // Toe knee: 0.15 at p25=0.40 → 0.25 at p25=0.10 (dark scenes lift more)
    float knee_toe = lerp(0.15, 0.25, saturate((0.40 - p25) / 0.30));

    float3 above = max(x - knee,     0.0);
    float3 below = max(knee_toe - x, 0.0);
    return x - factor * above * above
               + (0.03 / (knee_toe * knee_toe)) * below * below;
}

// ═══ Pixel shaders ════════════════════════════════════════════════════════════

// Pass 1 — Snapshot BackBuffer into RGBA16F
float4 CopyToSrcPS(float4 pos : SV_Position,
                   float2 uv  : TEXCOORD0) : SV_Target
{
    return tex2D(BackBuffer, uv);
}

// Pass 2 — Direct gamma
float4 OutputTransformPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;

    // Direct gamma: 1.0 = passthrough, <1 = brighten, >1 = darken. SDR-safe by construction.
    float4 perc = tex2D(PercSamp, float2(0.5, 0.5));
    float3 rgb_out = FilmCurve(pow(max(col.rgb, 0.0), EXPOSURE), perc.r, perc.b);

    // Debug indicator — green (slot 2)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 78) && pos.x < float(BUFFER_WIDTH - 66))
        return float4(0.1, 0.90, 0.1, 1.0);
    return float4(rgb_out, col.a);
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
