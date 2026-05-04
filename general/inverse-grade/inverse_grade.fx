// inverse_grade.fx — R90 Adaptive inverse tone mapping
//
// Game-agnostic. Measures display IQR from p25/p75 (data highway, analysis_frame)
// and expands chroma by the compression ratio vs. the ACES-derived 2.5-stop
// reference. Oklab chroma expansion — luma unchanged, hue preserved.
// C-gated relative to D65 neutral: near-neutral pixels (warm whites, greys)
// are excluded; only clearly coloured pixels see expansion.
// slope=1.0 for uncompressed content (no-op). No confidence gate.

#include "creative_values.fx"

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

#define PERC_X_SLOPE  197

float3 RGBToOklab(float3 rgb)
{
    float l = dot(rgb, float3(0.4122214708, 0.5363325363, 0.0514459929));
    float m = dot(rgb, float3(0.2119034982, 0.6806995451, 0.1073969566));
    float s = dot(rgb, float3(0.0883024619, 0.2817188376, 0.6299787005));
    float3 lms = exp2(log2(max(float3(l, m, s), 1e-10)) * (1.0 / 3.0));
    return float3(
        dot(lms, float3( 0.2104542553,  0.7936177850, -0.0040720468)),
        dot(lms, float3( 1.9779984951, -2.4285922050,  0.4505937099)),
        dot(lms, float3( 0.0259040371,  0.7827717662, -0.8086757660))
    );
}

float3 OklabToRGB(float3 lab)
{
    float l = lab.x + 0.3963377774*lab.y + 0.2158037573*lab.z;
    float m = lab.x - 0.1055613458*lab.y - 0.0638541728*lab.z;
    float s = lab.x - 0.0894841775*lab.y - 1.2914855480*lab.z;
    l = l*l*l; m = m*m*m; s = s*s*s;
    return float3(
        +4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
        -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
        -0.0041960863*l - 0.7034186147*m + 1.7076147010*s
    );
}

float4 InverseGradePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;
    if (INVERSE_STRENGTH <= 0.0) return col;

    float slope_enc = tex2D(BackBuffer, float2((PERC_X_SLOPE + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT)).r;
    float slope     = slope_enc * 1.5 + 1.0;

    float3 lab       = RGBToOklab(col.rgb);
    float mid_weight = lab.x * (1.0 - lab.x) * 4.0;
    float C          = length(lab.yz);
    float c_weight   = saturate((C - 0.10) / 0.15);

    lab.yz  *= lerp(1.0, slope, float(INVERSE_STRENGTH) * mid_weight * c_weight);
    col.rgb  = saturate(OklabToRGB(lab));
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
