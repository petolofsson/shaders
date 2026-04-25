// corrective_bus_out.fx — Exit point for the HDR corrective chain
//
// Copies CorrectiveBuf → BackBuffer after all corrective stages complete.
//
// DEBUG STRIP (y=2–6, always visible regardless of CorrectiveBuf content):
//   x=0–9   passthrough from CorrectiveSamp — MAGENTA if BusIn sentinel survived sharing
//   x=10–19 WHITE — BusOut ran (hardcoded, always visible)
//   x=20–69 CYAN  — CorrectiveBuf has scene content (luma at center > 0.05)
//            RED   — CorrectiveBuf is empty (luma ≈ 0) = sharing broken or BusIn failed

texture2D CorrectiveBuf { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 1; };
sampler2D CorrectiveSamp
{
    Texture   = CorrectiveBuf;
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

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float4 CopyOutPS(float4 pos : SV_Position,
                 float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.y >= 2 && pos.y < 7)
    {
        // x=10–19: hardcoded WHITE — proves BusOut is running regardless of buffer state
        if (pos.x >= 10 && pos.x < 20)
            return float4(1, 1, 1, 1);

        // x=20–69: CYAN if CorrectiveBuf has scene content, RED if empty
        if (pos.x >= 20 && pos.x < 70)
        {
            float luma = Luma(tex2Dlod(CorrectiveSamp, float4(0.5, 0.5, 0, 0)).rgb);
            return (luma > 0.05) ? float4(0, 1, 1, 1) : float4(1, 0, 0, 1);
        }

        // x=0–9: passthrough — magenta if BusIn sentinel survived all the way here
        if (pos.x < 10)
            return tex2D(CorrectiveSamp, uv);
    }

    return tex2D(CorrectiveSamp, uv);
}

technique CorrectiveBusOut
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyOutPS;
    }
}
