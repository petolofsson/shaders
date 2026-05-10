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

// Identical descriptor to analysis_frame.fx — vkBasalt shares the texture
texture2D MeanChromaTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D MeanChromaSamp
{
    Texture   = MeanChromaTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

float4 InverseGradePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;
    if (INVERSE_STRENGTH <= 0.0) return col;
    float slope_enc  = ReadHWY(HWY_SLOPE);
    float slope      = max(slope_enc * 1.5 + 1.0, 1.15);  // clamp below valid min; uninit highway (slot=0) decodes to 1.0, clamped to 1.15
    float3 lab        = RGBtoOklab(col.rgb);
    float  C          = length(lab.yz);
    float  mid_weight = lab.x * (1.0 - lab.x) * 4.0;
    float  hue        = frac(atan2(lab.z, lab.y) / 6.28318530);
    // R157: in highly achromatic scenes the remaining colored pixels are genuine
    // signal — lower the chroma gate so they see full expansion.
    float  achrom_frac = ReadHWY(HWY_ACHROM_FRAC);
    float  c_gate      = lerp(0.10, 0.06, smoothstep(0.60, 0.85, achrom_frac));
    float  c_weight    = saturate((C - c_gate) / 0.15);
    float  mean_C      = tex2Dlod(MeanChromaSamp, float4(0.5, 0.5, 0, 0)).r;
    // R156: warm hues (red, orange) are compressed more by ACES-style tonemappers;
    // cool hues (teal, cyan) less. Scale slope per hue before applying expansion.
    float  slope_eff   = clamp(slope * (1.0 + HueSlopeBias(hue)), 1.0, 2.2);
    float  factor      = lerp(1.0, slope_eff, float(INVERSE_STRENGTH) * mid_weight * c_weight);
    float2 dir         = lab.yz / max(C, 1e-5);
    float  new_C       = mean_C + (C - mean_C) * factor;
    // Per-hue ceiling — prevents expansion from overshooting natural gamut.
    // Preserves incoming C if already above ceiling (no reduction), but blocks
    // inverse grade from pushing further. Mirrors R73 ceilings in grade.fx.
    new_C   = min(new_C, max(HueCeil(hue), C));
    lab.yz  = dir * max(new_C, 0.0);

    // R144: luma expansion — restore L compressed by the game's tonemapper.
    // Pivot is cbrt(p50_linear): p50 is stored as linear Rec709 luma; Oklab L is
    // perceptual (cube-root), so raw p50_linear as pivot places zero-crossing at
    // Oklab L≈0.50 (linear Y≈0.125, deep shadow). cbrt corrects this to ~0.79.
    // c_weight excluded: tonemapper compressed every pixel's luma, neutrals included.
    float p50_lin     = ReadHWY(HWY_P50);
    float p50_lab     = exp2(log2(max(p50_lin, 1e-10)) * (1.0 / 3.0));
    float luma_factor = lerp(1.0, slope, float(INVERSE_STRENGTH) * mid_weight);
    float new_L       = p50_lab + (lab.x - p50_lab) * luma_factor;
    lab.x = max(new_L, 0.0);

    col.rgb   = saturate(OklabToRGB(lab));
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
