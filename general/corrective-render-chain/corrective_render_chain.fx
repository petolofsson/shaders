// corrective_render_chain.fx — Display transform (game-agnostic)
//
//   Pass 1  CopyToSrc       BackBuffer    → CorrectiveSrcTex  (RGBA16F snapshot)
//   Pass 2  OutputTransform CorrectiveSrc → BackBuffer        Scene-adaptive power curve

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

// ─── Vertex shader ─────────────────────────────────────────────────────────

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ─── Pixel shader ──────────────────────────────────────────────────────────

float4 CopyToSrcPS(float4 pos : SV_Position,
                   float2 uv  : TEXCOORD0) : SV_Target
{
    return tex2D(BackBuffer, uv);
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
}
