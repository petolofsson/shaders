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

// Piecewise exact inverse of FilmCurveApply (grade.fx).
// Shoulder and toe have closed-form inverses; midrange body_s (≤1.2%) is neglected.
// R198: pre-compensates for the forward FilmCurve that grade.fx will apply,
// so chroma expansion operates in the post-curve tonal domain.
float FilmCurveInvCh(float y, float knee, float ktoe)
{
    float h  = 1.0 - knee;
    float A  = 0.06 / ktoe;
    float qa = 1.0 - A;

    // Shoulder: x = knee + s·h/(h−s), s = y−knee
    float s    = y - knee;
    float x_sh = knee + s * h / max(h - s, 1e-5);

    // Toe: quadratic b² term, b = ktoe−x
    float disc = y*y + 4.0*qa*(ktoe - y)*ktoe;
    float b    = (-y + sqrt(max(disc, 0.0))) / max(2.0*qa, 1e-5);
    float x_to = ktoe - b;

    float w_sh = step(knee, y);   // 1 if y >= knee
    float w_to = step(y, ktoe);   // 1 if y <= ktoe
    return lerp(lerp(y, x_to, w_to), x_sh, w_sh);
}

float4 InverseGradePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col    = tex2D(BackBuffer, uv);
    if (INVERSE_STRENGTH <= 0.0) return col;

    // R198: apply FilmCurve inverse so chroma expansion sees the post-curve domain.
    // Reconstruct fc_knee / fc_knee_toe from highway (one-frame delay — same precedent
    // as NeutralIllumTex). Per-channel offsets from creative_values knobs.
    {
        float p25  = ReadHWY(HWY_P25);
        float p50  = ReadHWY(HWY_P50);
        float p75  = ReadHWY(HWY_P75);
        float mode = ReadHWY(HWY_MODE);
        float bowley     = (p75 + p25 - 2.0*p50) / max(p75 - p25, 0.01);
        float fc_knee    = saturate(lerp(0.90, 0.80, saturate((p75 - 0.60) / 0.30))
                         - saturate(bowley) * 0.06);
        float fc_ktoe    = lerp(0.15, 0.25, saturate((0.40 - p25) / 0.30));
        float toe_gap    = saturate((fc_ktoe - mode - 0.05) / 0.10);
        fc_ktoe          = lerp(fc_ktoe, mode + 0.05, toe_gap * 0.4);
        float3 knee = float3(clamp(fc_knee * exp2(float(CURVE_R_KNEE) * 0.10), 0.70, 0.95),
                             fc_knee,
                             clamp(fc_knee * exp2(float(CURVE_B_KNEE) * 0.10), 0.70, 0.95));
        float3 ktoe = float3(clamp(fc_ktoe * exp2(float(CURVE_R_TOE)  * 0.10), 0.08, 0.35),
                             fc_ktoe,
                             clamp(fc_ktoe * exp2(float(CURVE_B_TOE)  * 0.10), 0.08, 0.35));
        col.r = FilmCurveInvCh(col.r, knee.r, ktoe.r);
        col.g = FilmCurveInvCh(col.g, knee.g, ktoe.g);
        col.b = FilmCurveInvCh(col.b, knee.b, ktoe.b);
    }

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
    float3 ni_rgb      = tex2Dlod(NeutralIllumSamp, float4(0.5, 0.5, 0, 0)).rgb;
    float3 ni_norm     = ni_rgb / max(Luma(ni_rgb), 0.001);
    const float3x3 Mf = float3x3(0.302825, 0.602279, 0.070428,
                                   0.153818, 0.777214, 0.085341,
                                   0.027974, 0.147911, 0.908874);
    float3 ni_lms      = mul(Mf, ni_norm);
    float3 ni_lmsn     = ni_lms / max(ni_lms.g, 0.001);
    float  illum_warm  = saturate(ni_lmsn.r - ni_lmsn.b + 0.5);
    float  warm_scene  = saturate((illum_warm - 0.45) / 0.35);
    // R196-J: per-pixel illumination gate — high-luma pixels are illumination-dominated.
    // Retinex: log(pixel) = log(reflectance) + log(illumination). Bright pixels carry
    // more illumination energy; chroma expansion risks neonizing warm practicals and emissives.
    // In warm scenes bright pixels are especially likely to be practicals, not compressed reflectance.
    float  illum_luma_w = smoothstep(0.35, 0.75, lab.x);
    float  illum_gate   = illum_luma_w * lerp(0.65, 1.0, warm_scene);
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
                   * (1.0 - illum_gate);
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
