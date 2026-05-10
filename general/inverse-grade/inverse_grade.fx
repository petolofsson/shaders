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
    float3 lab = RGBtoOklab(col.rgb);
    float  C   = length(lab.yz);

    // R143: highlight reconstruction — chroma rolloff near SDR clip ceiling.
    // Always-on: physically correct defect correction, not a stylistic choice.
    // Wide near-clip zone (0.88→0.995): 8-bit has only 3–4 linear levels near clip.
    // C gate (0.18→0.08): skip intentionally saturated colored lights.
    // Mid-ch gate (0.95→0.80): skip near-white content (sun, sky) where the second-
    //   highest channel is also near clip — those are warm-whites, not clipping artifacts.
    //   False cast: R=1.0, G≈0.78 → mid=0.78 → fires. Sun: R=1.0, G≈0.97 → protected.
    // Desaturates only — never shifts hue, never adds energy.
    float max_ch  = max(max(col.r, col.g), col.b);
    float min_ch  = min(min(col.r, col.g), col.b);
    float mid_ch  = col.r + col.g + col.b - max_ch - min_ch;
    float recon_w = smoothstep(0.88, 0.995, max_ch)
                  * smoothstep(0.18, 0.08, C)
                  * smoothstep(0.95, 0.80, mid_ch);
    lab.yz *= (1.0 - recon_w);
    C       = length(lab.yz);

    if (INVERSE_STRENGTH <= 0.0) { col.rgb = saturate(OklabToRGB(lab)); return col; }

    // R90: adaptive chroma expansion
    if (INVERSE_STRENGTH > 0.0) {
        float slope_enc  = ReadHWY(HWY_SLOPE);
        float slope      = max(slope_enc * 1.5 + 1.0, 1.15);  // R116: clamp below valid min; uninit highway decodes as 1.0
        float mid_weight = lab.x * (1.0 - lab.x) * 4.0;
        float c_weight   = saturate((C - 0.10) / 0.15);
        float mean_C     = tex2Dlod(MeanChromaSamp, float4(0.5, 0.5, 0, 0)).r;
        float factor     = lerp(1.0, slope, float(INVERSE_STRENGTH) * mid_weight * c_weight);
        float2 dir       = lab.yz / max(C, 1e-5);
        float  new_C     = mean_C + (C - mean_C) * factor;
        // Per-hue ceiling — prevents expansion from overshooting natural gamut.
        // Preserves incoming C if already above ceiling (no reduction), but blocks
        // inverse grade from pushing further. Mirrors R73 ceilings in grade.fx.
        float hue = frac(atan2(lab.z, lab.y) / 6.28318530);
        new_C     = min(new_C, max(HueCeil(hue), C));
        lab.yz    = dir * max(new_C, 0.0);
    }

    col.rgb = saturate(OklabToRGB(lab));
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
