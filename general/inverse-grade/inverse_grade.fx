// inverse_grade.fx — R90 Adaptive inverse tone mapping
//
// Game-agnostic. Measures display IQR from p25/p75 (data highway, analysis_frame)
// and expands chroma by the compression ratio vs. the ACES-derived 2.5-stop
// reference. Oklab chroma expansion — luma unchanged, hue preserved.
// C-gated relative to D65 neutral: near-neutral pixels (warm whites, greys)
// are excluded; only clearly coloured pixels see expansion.
// slope=1.0 for uncompressed content (no-op). No confidence gate.

#include "creative_values.fx"
#include "../highway.fxh"
#include "../hue_bands.fxh"
#include "../common.fxh"

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

float4 InverseGradePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col    = tex2D(BackBuffer, uv);
    if (INVERSE_STRENGTH <= 0.0) return col;

    float3 lab    = RGBtoOklab(col.rgb);
    float  C      = length(lab.yz);
    float  hue    = frac(atan2(lab.z, lab.y) / 6.28318530);
    float2 dir    = lab.yz / max(C, 1e-5);
    float  zone_w = 4.0 * lab.x * (1.0 - lab.x);
    // toe_inv(x, ceil, c1, k2) = (x² + k1·x) / (k3·(x+k2))
    float  ceil_C = max(HueCeil(hue), C + 0.001);
    float  c1     = float(INVERSE_STRENGTH) * 0.06 * zone_w;
    float  k2      = 0.01;
    float  k1      = sqrt(c1 * c1 + k2 * k2);
    float  k3      = (ceil_C + k1) / (ceil_C + k2);
    float  new_C   = (C * C + k1 * C) / (k3 * (C + k2));
    new_C          = max(new_C, C);
    lab.yz          = dir * max(new_C, 0.0);
    float3 rgb_test = OklabToRGB(lab);
    float  max_ch   = max(max(rgb_test.r, rgb_test.g), rgb_test.b);
    lab.yz         /= max(max_ch, 1.0);
    col.rgb         = saturate(OklabToRGB(lab));
    return col;
}

technique OlofssonianInverseGrade
{
    pass InverseGradePass
    {
        VertexShader = PostProcessVS;
        PixelShader  = InverseGradePS;
    }
}
