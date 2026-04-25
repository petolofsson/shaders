// corrective_bus_in.fx — Entry point for the HDR corrective chain
//
// Copies BackBuffer → CorrectiveBuf (RGBA16F) before any corrective stage runs.
//
// DEBUG STRIP (y=2–6):
//   x=0–9 MAGENTA  — BusIn ran; this pixel reaches BusOut only if CorrectiveBuf is shared.

texture2D CorrectiveBuf { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 1; };

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float4 CopyInPS(float4 pos : SV_Position,
                float2 uv  : TEXCOORD0) : SV_Target
{
    // BusIn sentinel — magenta block in CorrectiveBuf.
    // Visible in final output only if CorrectiveBuf is shared all the way to BusOut.
    if (pos.y >= 2 && pos.y < 7 && pos.x >= 0 && pos.x < 10)
        return float4(1, 0, 1, 1);

    return tex2D(BackBuffer, uv);
}

technique CorrectiveBusIn
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyInPS;
        RenderTarget = CorrectiveBuf;
    }
}
