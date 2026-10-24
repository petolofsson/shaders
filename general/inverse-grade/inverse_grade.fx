// inverse_grade.fx — R90 Adaptive inverse tone mapping
//
// Game-agnostic. Measures display IQR from p25/p75 (data highway, analysis_frame)
// and expands chroma by the compression ratio vs. the ACES-derived 2.5-stop
// reference. Oklab chroma expansion — luma unchanged, hue preserved.
// C-gated relative to D65 neutral: near-neutral pixels (warm whites, greys)
// are excluded; only clearly coloured pixels see expansion.
// slope=1.0 for uncompressed content (no-op). No confidence gate.

#ifndef SHADER_PIPELINE_COMBINED
#include "creative_values.fx"
#endif
#include "../highway.fxh"
#include "../hue_bands.fxh"
#include "../common.fxh"

#ifndef SHADER_PIPELINE_COMBINED
texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    SRGBTexture = false;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};
#endif

// NeutralIllum RGB: read from TexHwyTex data row 0 pixel 4 (grade writes each frame, one-frame delay).

float4 InverseGradePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col    = tex2D(BackBuffer, uv);
    if (INVERSE_STRENGTH <= 0.0) return col;
    col.rgb = SRGBToLinear(col.rgb);

    float slope_enc   = ReadHWY(HWY_CHROMA_SLOPE);
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
    float3 ni_rgb     = ReadTexHwyIlluminant().rgb;
    float  illum_warm = IllumWarm(ni_rgb);
    float  warm_scene  = saturate((illum_warm - 0.45) / 0.35);
    // R196-J: per-pixel illumination gate — high-luma pixels are illumination-dominated.
    // Retinex: log(pixel) = log(reflectance) + log(illumination). Bright pixels carry
    // more illumination energy; chroma expansion risks neonizing warm practicals and emissives.
    // In warm scenes bright pixels are especially likely to be practicals, not compressed reflectance.
    float  illum_luma_w = smoothstep(0.35, 0.75, lab.x);
    float  illum_gate   = illum_luma_w * lerp(0.65, 1.0, warm_scene);
    float  near_clip    = ReadHWY(HWY_NEAR_CLIP);
    float  clip_scene_w = smoothstep(0.01, 0.12, near_clip);
    float  clip_pixel_w = smoothstep(0.65, 0.92, lab.x);
    // A small saturated emitter can clip one channel without moving the global
    // luminance histogram. Protect that local signal independently of area.
    float  clip_local_w = smoothstep(0.85, 0.99, max(col.r, max(col.g, col.b)));
    float  clip_guard   = 1.0 - 0.75 * max(clip_local_w, clip_scene_w * clip_pixel_w);
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
    // Midtone bell: peaks at L=0.5, zero at black/white. Validated for game content:
    // cinema mastering data (arxiv 2604.06276) shows midtone expansion is correct;
    // shadow desaturation and highlight convergence do not need expansion.
    float  zone_w  = 4.0 * lab.x * (1.0 - lab.x);
    // R193: ACES 2.0 toe_inv rational function replaces lerp-with-saturate ceiling.
    // c1 scales linearly with INVERSE_STRENGTH — no saturate() on the strength path.
    // Near-neutral C expands most; C near HueCeil asymptotes to ceiling, never clips.
    // toe_inv(x, ceil, c1, k2) = (x² + k1·x) / (k3·(x+k2))
    float  ceil_C  = max(HueCeil(hue), C + 0.001);
    // IS drives expansion magnitude. slope_frac adapts ±30%: vivid scenes get 70% of IS,
    // achromatic scenes get 100%. Range [0.7, 1.0] — slope is a scene modifier, not the gate.
    float  slope_frac = lerp(0.7, 1.0, saturate((slope_eff - 1.0) / 0.8));
    float  c1      = float(INVERSE_STRENGTH) * slope_frac * zone_w * c_weight * dir_scale
                   * (1.0 - illum_gate) * clip_guard;
    float  k2      = 0.01;
    float  k1      = sqrt(c1 * c1 + k2 * k2);
    float  k3      = (ceil_C + k1) / (ceil_C + k2);
    float  new_C   = (C * C + k1 * C) / (k3 * (C + k2));
    new_C          = max(new_C, C);
    lab.yz          = dir * max(new_C, 0.0);
    col.rgb         = LinearToSRGB(OklabToSDR(lab));
    return col;
}

#ifndef SHADER_PIPELINE_COMBINED
technique OlofssonianInverseGrade
{
    pass InverseGradePass
    {
        VertexShader = PostProcessVS;
        PixelShader  = InverseGradePS;
        SRGBWriteEnable = false;
    }
}
#endif
