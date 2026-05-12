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

// Shared with grade.fx NeutralIllumPS — one-frame delay, acceptable
texture2D NeutralIllumTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D NeutralIllumSamp { Texture = NeutralIllumTex; MinFilter = POINT; MagFilter = POINT; };

float4 InverseGradePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;
    if (INVERSE_STRENGTH <= 0.0) return col;
    float slope_enc   = ReadHWY(HWY_SLOPE);
    float slope       = clamp(slope_enc * 1.5 + 1.0, 1.15, 2.2);
    float3 lab        = RGBtoOklab(col.rgb);
    float  C          = length(lab.yz);
    float  hue        = frac(atan2(lab.z, lab.y) / 6.28318530);
    // R157: in highly achromatic scenes the remaining colored pixels are genuine
    // signal — lower the chroma gate so they see full expansion.
    float  achrom_frac = ReadHWY(HWY_ACHROM_FRAC);
    float  c_gate      = lerp(0.10, 0.06, smoothstep(0.60, 0.85, achrom_frac));
    float  c_weight    = saturate((C - c_gate) / 0.15);
    // R156: warm hues (red, orange) are compressed more by ACES-style tonemappers;
    // cool hues (teal, cyan) less. Scale slope per hue before applying expansion.
    // R165: in warm-lit scenes, warm-hue saturation is the illuminant — not a tonemapper
    // artifact. Back off positive bias proportionally. One-frame delay acceptable.
    float3 ni_rgb      = tex2Dlod(NeutralIllumSamp, float4(0.5, 0.5, 0, 0)).rgb;
    float3 ni_norm     = ni_rgb / max(Luma(ni_rgb), 0.001);
    const float3x3 Mf = float3x3(0.302825, 0.602279, 0.070428,
                                   0.153818, 0.777214, 0.085341,
                                   0.027974, 0.147911, 0.908874);
    float3 ni_lms      = mul(Mf, ni_norm);
    float3 ni_lmsn     = ni_lms / max(ni_lms.g, 0.001);
    float  illum_warm  = saturate(ni_lmsn.r - ni_lmsn.b + 0.5);
    float  warm_scene  = saturate((illum_warm - 0.45) / 0.35);
    float  bias        = HueSlopeBias(hue);
    float  bias_adj    = max(bias, 0.0) * (1.0 - warm_scene * 0.50) + min(bias, 0.0);
    float  slope_eff   = clamp(slope * (1.0 + bias_adj), 1.0, 2.2);
    float2 dir         = lab.yz / max(C, 1e-5);
    // R163: dominant-hue aware expansion — complementary pixels are under-represented
    // and deserve slightly more expansion; aligned pixels are already plentiful.
    // CHROMA_ANGLE encodes mean chroma direction (atan2 of scene ab centroid).
    float  scene_ang   = ReadHWY(HWY_CHROMA_ANGLE) * 6.28318 - 3.14159;
    float2 scene_dir;
    sincos(scene_ang, scene_dir.y, scene_dir.x);
    float  alignment   = dot(dir, scene_dir);
    float  dir_scale   = 1.0 - alignment * 0.15;
    // R187: (1 - L) continuous luma weight — full expansion at L=0, zero at L=1.
    // Matches ACES toe_inv (zero-anchored): C * factor — proportional expansion,
    // no contraction possible. Replaces bilateral zone system + mean_C anchor.
    float  lerp_t  = saturate(float(INVERSE_STRENGTH) * (1.0 - lab.x) * c_weight * dir_scale);
    float  factor  = lerp(1.0, slope_eff, lerp_t);
    float  new_C   = C * factor;
    // Per-hue ceiling — prevents expansion from overshooting natural gamut.
    // Preserves incoming C if already above ceiling (no reduction), but blocks
    // inverse grade from pushing further. Mirrors R73 ceilings in grade.fx.
    new_C           = min(new_C, max(HueCeil(hue), C));
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
