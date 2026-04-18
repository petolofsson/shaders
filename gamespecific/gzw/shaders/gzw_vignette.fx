// Minimal vignette — no ReShade.fxh dependency
// Adjust STRENGTH and SMOOTHNESS to taste:
//   STRENGTH   0.0 = off  |  0.25 = subtle  |  0.50 = moderate  |  1.0 = heavy
//   INNER      0.0 = starts at center  |  0.20 = clean center zone  |  0.40 = very tight
//   SMOOTHNESS 0.0 = hard edge  |  0.6 = gradual falloff  |  1.0 = very wide

#define STRENGTH   0.22
#define INNER      0.20
#define SMOOTHNESS 0.6

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

float4 VignettePS(float4 pos : SV_Position,
                  float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);

    float2 c = uv - 0.5;
    float  d = dot(c, c);

    float v = 1.0 - smoothstep(INNER, SMOOTHNESS, d * STRENGTH * 4.0);

    col.rgb *= v;
    return col;
}

technique Vignette
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = VignettePS;
    }
}
