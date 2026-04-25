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

// ─── Vertex shader ─────────────────────────────────────────────────────────

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
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
    float3 rgb_out = pow(max(col.rgb, 0.0), EXPOSURE);

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
