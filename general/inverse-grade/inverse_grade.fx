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

// ─── Bilateral local luma ──────────────────────────────────────────────────
// Two 1/8-res passes build an edge-preserving Oklab L estimate.
// σ_s = 2.0 output texels (≈16 px at 1080p); σ_r = 0.08 Oklab L (edge-stop).
// Zone weights in InverseGradePS: shadow ×0.40 → mid ×1.0 → highlight ×0.45.
// Set BILATERAL_ZONE_DEBUG 1 in creative_values.fx to overlay the zone map.
#define BIL_W0  1.000000
#define BIL_W1  0.882497
#define BIL_W2  0.606531
#define BIL_W3  0.324652
#define BIL_W4  0.135335
#define BIL_SR2 0.012800   // 2 * 0.08^2

texture2D LocalLumaHTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16F; MipLevels = 1; };
sampler2D LocalLumaHSamp
{
    Texture   = LocalLumaHTex;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
};
texture2D LocalLumaTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16F; MipLevels = 1; };
sampler2D LocalLumaSamp
{
    Texture   = LocalLumaTex;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
};

float LocalLumaDownHPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float px = 8.0 / BUFFER_WIDTH;
    float L0 = RGBtoOklab(tex2D(BackBuffer, uv).rgb).x;
    float sum = BIL_W0 * L0, wsum = BIL_W0;
    float Li, dL, rw;

    Li = RGBtoOklab(tex2D(BackBuffer, float2(uv.x - 1.0*px, uv.y)).rgb).x;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W1*rw*Li; wsum += BIL_W1*rw;
    Li = RGBtoOklab(tex2D(BackBuffer, float2(uv.x + 1.0*px, uv.y)).rgb).x;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W1*rw*Li; wsum += BIL_W1*rw;
    Li = RGBtoOklab(tex2D(BackBuffer, float2(uv.x - 2.0*px, uv.y)).rgb).x;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W2*rw*Li; wsum += BIL_W2*rw;
    Li = RGBtoOklab(tex2D(BackBuffer, float2(uv.x + 2.0*px, uv.y)).rgb).x;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W2*rw*Li; wsum += BIL_W2*rw;
    Li = RGBtoOklab(tex2D(BackBuffer, float2(uv.x - 3.0*px, uv.y)).rgb).x;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W3*rw*Li; wsum += BIL_W3*rw;
    Li = RGBtoOklab(tex2D(BackBuffer, float2(uv.x + 3.0*px, uv.y)).rgb).x;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W3*rw*Li; wsum += BIL_W3*rw;
    Li = RGBtoOklab(tex2D(BackBuffer, float2(uv.x - 4.0*px, uv.y)).rgb).x;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W4*rw*Li; wsum += BIL_W4*rw;
    Li = RGBtoOklab(tex2D(BackBuffer, float2(uv.x + 4.0*px, uv.y)).rgb).x;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W4*rw*Li; wsum += BIL_W4*rw;

    return sum / wsum;
}

float LocalLumaDownVPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float py = 8.0 / BUFFER_HEIGHT;
    float L0 = tex2D(LocalLumaHSamp, uv).r;
    float sum = BIL_W0 * L0, wsum = BIL_W0;
    float Li, dL, rw;

    Li = tex2D(LocalLumaHSamp, float2(uv.x, uv.y - 1.0*py)).r;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W1*rw*Li; wsum += BIL_W1*rw;
    Li = tex2D(LocalLumaHSamp, float2(uv.x, uv.y + 1.0*py)).r;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W1*rw*Li; wsum += BIL_W1*rw;
    Li = tex2D(LocalLumaHSamp, float2(uv.x, uv.y - 2.0*py)).r;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W2*rw*Li; wsum += BIL_W2*rw;
    Li = tex2D(LocalLumaHSamp, float2(uv.x, uv.y + 2.0*py)).r;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W2*rw*Li; wsum += BIL_W2*rw;
    Li = tex2D(LocalLumaHSamp, float2(uv.x, uv.y - 3.0*py)).r;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W3*rw*Li; wsum += BIL_W3*rw;
    Li = tex2D(LocalLumaHSamp, float2(uv.x, uv.y + 3.0*py)).r;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W3*rw*Li; wsum += BIL_W3*rw;
    Li = tex2D(LocalLumaHSamp, float2(uv.x, uv.y - 4.0*py)).r;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W4*rw*Li; wsum += BIL_W4*rw;
    Li = tex2D(LocalLumaHSamp, float2(uv.x, uv.y + 4.0*py)).r;
    dL = Li - L0; rw = exp(-dL*dL/BIL_SR2); sum += BIL_W4*rw*Li; wsum += BIL_W4*rw;

    return sum / wsum;
}

float4 InverseGradePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col    = tex2D(BackBuffer, uv);
    float  L_local = tex2D(LocalLumaSamp, uv).r;

#if BILATERAL_ZONE_DEBUG
    float  s_w = 1.0 - smoothstep(0.28, 0.46, L_local);
    float  h_w = smoothstep(0.80, 0.88, L_local);
    float  m_w = saturate(1.0 - s_w - h_w);
    col.rgb = lerp(col.rgb,
                   s_w * float3(0.20, 0.40, 1.00)
                 + m_w * float3(0.20, 1.00, 0.20)
                 + h_w * float3(1.00, 0.35, 0.10), 0.60);
    return col;
#else
    if (INVERSE_STRENGTH <= 0.0) return col;
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
    // Bilateral zone weight: shadow×0.40, mid×1.0, highlight×0.45.
    // Smoothstep ramps at 0.28–0.46 (shadow→mid) and 0.80–0.88 (mid→highlight).
    // L_local is spatially-filtered so a dark pixel in a bright scene is weighted
    // by its neighbourhood, not its own value alone.
    float  zone_w  = lerp(0.40, 1.0,  smoothstep(0.28, 0.46, L_local))
                   * lerp(1.0,  0.45, smoothstep(0.80, 0.88, L_local));
    float  lerp_t  = saturate(float(INVERSE_STRENGTH) * zone_w * c_weight * dir_scale);
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
#endif
}

technique OlofssonianInverseGrade
{
    pass LocalLumaDownH
    {
        VertexShader = PostProcessVS;
        PixelShader  = LocalLumaDownHPS;
        RenderTarget = LocalLumaHTex;
    }
    pass LocalLumaDownV
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
