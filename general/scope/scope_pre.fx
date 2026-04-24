// scope_pre.fx — Pre-correction luma histogram capture
//
// Must run before any corrective shaders. Samples BackBuffer (raw game
// signal) and writes a normalized histogram into ScopeCaptureTex.
// scope.fx reads this texture for its red (pre-correction) panel.

#define SCOPE_BINS 128
#define SCOPE_S    16

texture2D ScopeCaptureTex { Width = 128; Height = 1; Format = R32F; MipLevels = 1; };

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

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float4 ScopeCapturePS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    int   b         = int(pos.x);
    float bucket_lo = float(b)     / float(SCOPE_BINS);
    float bucket_hi = float(b + 1) / float(SCOPE_BINS);

    float count = 0.0;
    [loop]
    for (int sy = 0; sy < SCOPE_S; sy++)
    [loop]
    for (int sx = 0; sx < SCOPE_S; sx++)
    {
        float luma = Luma(tex2Dlod(BackBuffer,
            float4((sx + 0.5) / float(SCOPE_S), (sy + 0.5) / float(SCOPE_S), 0, 0)).rgb);
        count += (luma >= bucket_lo && luma < bucket_hi) ? 1.0 : 0.0;
    }

    return float4(count / float(SCOPE_S * SCOPE_S), 0, 0, 1);
}

technique ScopeCapture
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = ScopeCapturePS;
        RenderTarget = ScopeCaptureTex;
    }
}
