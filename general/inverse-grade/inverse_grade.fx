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

// R186: bilateral spatial Gaussian weights — separable 9-tap approximation at 1/8-res.
// σ_s = 2.0 output texels (≈ ±32 px at 1080p). σ_r = 0.12 (edge-stop at ΔL > ~0.24).
#define BIL_S1 0.8825
#define BIL_S2 0.6065
#define BIL_S3 0.3247
#define BIL_S4 0.1353
#define BIL_RCP_2SR2 34.72

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

// R186: 1/8-res bilateral intermediate (H pass) and final local luma (V pass)
texture2D LocalLumaHTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16F; MipLevels = 1; };
sampler2D LocalLumaHSamp
{
    Texture   = LocalLumaHTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D LocalLumaTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16F; MipLevels = 1; };
sampler2D LocalLumaSamp
{
    Texture   = LocalLumaTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// 9-tap horizontal bilateral at 1/8-res. Taps spaced 8 full-res pixels apart.
float4 LocalLumaDownHPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 step = float2(8.0 / float(BUFFER_WIDTH), 0.0);
    float c  = Luma(tex2D(BackBuffer, uv              ).rgb);
    float l4 = Luma(tex2D(BackBuffer, uv + step * -4.0).rgb);
    float l3 = Luma(tex2D(BackBuffer, uv + step * -3.0).rgb);
    float l2 = Luma(tex2D(BackBuffer, uv + step * -2.0).rgb);
    float l1 = Luma(tex2D(BackBuffer, uv + step * -1.0).rgb);
    float r1 = Luma(tex2D(BackBuffer, uv + step *  1.0).rgb);
    float r2 = Luma(tex2D(BackBuffer, uv + step *  2.0).rgb);
    float r3 = Luma(tex2D(BackBuffer, uv + step *  3.0).rgb);
    float r4 = Luma(tex2D(BackBuffer, uv + step *  4.0).rgb);
    float wl4 = BIL_S4 * exp(-(l4 - c) * (l4 - c) * BIL_RCP_2SR2);
    float wl3 = BIL_S3 * exp(-(l3 - c) * (l3 - c) * BIL_RCP_2SR2);
    float wl2 = BIL_S2 * exp(-(l2 - c) * (l2 - c) * BIL_RCP_2SR2);
    float wl1 = BIL_S1 * exp(-(l1 - c) * (l1 - c) * BIL_RCP_2SR2);
    float wr1 = BIL_S1 * exp(-(r1 - c) * (r1 - c) * BIL_RCP_2SR2);
    float wr2 = BIL_S2 * exp(-(r2 - c) * (r2 - c) * BIL_RCP_2SR2);
    float wr3 = BIL_S3 * exp(-(r3 - c) * (r3 - c) * BIL_RCP_2SR2);
    float wr4 = BIL_S4 * exp(-(r4 - c) * (r4 - c) * BIL_RCP_2SR2);
    float sum_w = 1.0 + wl4 + wl3 + wl2 + wl1 + wr1 + wr2 + wr3 + wr4;
    float result = (c + wl4*l4 + wl3*l3 + wl2*l2 + wl1*l1
                     + wr1*r1 + wr2*r2 + wr3*r3 + wr4*r4) / sum_w;
    return float4(result, 0.0, 0.0, 1.0);
}

// 9-tap vertical bilateral at 1/8-res. Taps spaced 1 LocalLumaHTex texel apart.
float4 LocalLumaDownVPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 step = float2(0.0, 8.0 / float(BUFFER_HEIGHT));
    float c  = tex2D(LocalLumaHSamp, uv              ).r;
    float u4 = tex2D(LocalLumaHSamp, uv + step * -4.0).r;
    float u3 = tex2D(LocalLumaHSamp, uv + step * -3.0).r;
    float u2 = tex2D(LocalLumaHSamp, uv + step * -2.0).r;
    float u1 = tex2D(LocalLumaHSamp, uv + step * -1.0).r;
    float d1 = tex2D(LocalLumaHSamp, uv + step *  1.0).r;
    float d2 = tex2D(LocalLumaHSamp, uv + step *  2.0).r;
    float d3 = tex2D(LocalLumaHSamp, uv + step *  3.0).r;
    float d4 = tex2D(LocalLumaHSamp, uv + step *  4.0).r;
    float wu4 = BIL_S4 * exp(-(u4 - c) * (u4 - c) * BIL_RCP_2SR2);
    float wu3 = BIL_S3 * exp(-(u3 - c) * (u3 - c) * BIL_RCP_2SR2);
    float wu2 = BIL_S2 * exp(-(u2 - c) * (u2 - c) * BIL_RCP_2SR2);
    float wu1 = BIL_S1 * exp(-(u1 - c) * (u1 - c) * BIL_RCP_2SR2);
    float wd1 = BIL_S1 * exp(-(d1 - c) * (d1 - c) * BIL_RCP_2SR2);
    float wd2 = BIL_S2 * exp(-(d2 - c) * (d2 - c) * BIL_RCP_2SR2);
    float wd3 = BIL_S3 * exp(-(d3 - c) * (d3 - c) * BIL_RCP_2SR2);
    float wd4 = BIL_S4 * exp(-(d4 - c) * (d4 - c) * BIL_RCP_2SR2);
    float sum_w = 1.0 + wu4 + wu3 + wu2 + wu1 + wd1 + wd2 + wd3 + wd4;
    float result = (c + wu4*u4 + wu3*u3 + wu2*u2 + wu1*u1
                     + wd1*d1 + wd2*d2 + wd3*d3 + wd4*d4) / sum_w;
    return float4(result, 0.0, 0.0, 1.0);
}

float4 InverseGradePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;
    if (INVERSE_STRENGTH <= 0.0) return col;
    float slope_enc   = ReadHWY(HWY_SLOPE);
    float slope       = clamp(slope_enc * 1.5 + 1.0, 1.15, 2.2);
    float3 lab         = RGBtoOklab(col.rgb);
    float  C           = length(lab.yz);
    float  hue         = frac(atan2(lab.z, lab.y) / 6.28318530);
    // R157: in highly achromatic scenes the remaining colored pixels are genuine
    // signal — lower the chroma gate so they see full expansion.
    float  achrom_frac = ReadHWY(HWY_ACHROM_FRAC);
    float  c_gate      = lerp(0.10, 0.06, smoothstep(0.60, 0.85, achrom_frac));
    float  c_weight    = saturate((C - c_gate) / 0.15);
    float  mean_C      = tex2Dlod(MeanChromaSamp, float4(0.5, 0.5, 0, 0)).r;
    // R156: warm hues (red, orange) are compressed more by ACES-style tonemappers;
    // cool hues (teal, cyan) less. Scale slope per hue before applying expansion.
    // R165: in warm-lit scenes, warm-hue saturation is the illuminant — not a tonemapper
    // artifact. Back off positive bias proportionally. One-frame delay acceptable.
    float  illum_warm  = ReadHWY(HWY_ILLUM_WARM);
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
    // R186: bilateral local luma → three-zone partition replacing per-pixel mid_weight bell.
    // Tonemapper compresses highlights most, shadows least → zone weights are asymmetric.
    float  L_base      = tex2D(LocalLumaSamp, uv).r;
    float  w_shadow    = 1.0 - smoothstep(0.0,  0.25, L_base);
    float  w_highlight = smoothstep(0.60, 0.85, L_base) * (1.0 - smoothstep(0.80, 1.0, L_base));
    float  w_mid       = 1.0 - w_shadow - w_highlight;
    float  zone_weight = w_shadow * 0.4 + w_mid * 1.0 + w_highlight * 1.4;
    float  lerp_t      = saturate(float(INVERSE_STRENGTH) * zone_weight * c_weight * dir_scale);
    float  factor      = lerp(1.0, slope_eff, lerp_t);
    float  new_C       = mean_C + (C - mean_C) * factor;
    // Per-hue ceiling — prevents expansion from overshooting natural gamut.
    // Preserves incoming C if already above ceiling (no reduction), but blocks
    // inverse grade from pushing further. Mirrors R73 ceilings in grade.fx.
    new_C   = min(new_C, max(HueCeil(hue), C));
    lab.yz  = dir * max(new_C, 0.0);
    col.rgb = saturate(OklabToRGB(lab));
    return col;
}

technique OlofssonianInverseGrade
{
    pass LocalLumaDownHPass
    {
        VertexShader = PostProcessVS;
        PixelShader  = LocalLumaDownHPS;
        RenderTarget = LocalLumaHTex;
    }
    pass LocalLumaDownVPass
    {
        VertexShader = PostProcessVS;
        PixelShader  = LocalLumaDownVPS;
        RenderTarget = LocalLumaTex;
    }
    pass InverseGradePass
    {
        VertexShader = PostProcessVS;
        PixelShader  = InverseGradePS;
    }
}
