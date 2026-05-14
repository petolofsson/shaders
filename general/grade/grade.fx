// creative_color_grade.fx — Mega-pass: all downstream color work in one full-res pass
#include "../highway.fxh"
#include "../hue_bands.fxh"
#include "../common.fxh"
//
// Eliminates 3 inter-pass VRAM read-write cycles by running in registers:
//   1. EXPOSURE gamma + scene-adaptive FilmCurve (per-channel knee/toe from creative_values)
//   2. Zone contrast S-curve (auto) + Clarity + Shadow lift
//   3. Oklab chroma lift + H-K + Abney + density + gamut compress + R21/R22
//
// Reads from CorrectiveSrcTex (snapshot by corrective_render_chain CopyToSrc).
// All history textures (ZoneHistoryTex, ChromaHistoryTex, PercTex, CreativeLowFreqTex)
// are computed by earlier passes in the chain before this runs.

#include "creative_values.fx"

uniform float FRAME_TIMER < source = "timer"; >;        // ms since app start

// ─── Chroma lift constants ─────────────────────────────────────────────────
#define MIN_WEIGHT      1.0
#define GREEN_HUE_COOL  (4.0 / 360.0)


// ─── Textures ──────────────────────────────────────────────────────────────

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Scene percentiles — r=p25, g=p50, b=p75, a=iqr
texture2D PercTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D PercSamp
{
    Texture   = PercTex;
    MinFilter = POINT;
    MagFilter = POINT;
};

// Zone medians (from creative_render_chain SmoothZoneLevels)
texture2D ZoneHistoryTex { Width = 4; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D ZoneHistorySamp
{
    Texture   = ZoneHistoryTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Per-zone 32-bin luma histogram (shared from corrective.fx ComputeZoneHistogram)
texture2D CreativeZoneHistTex { Width = 32; Height = 16; Format = R16F; MipLevels = 1; };
sampler2D CreativeZoneHistSamp
{
    Texture   = CreativeZoneHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// 1/8-res low-freq base (from creative_render_chain ComputeLowFreq, luma in .a)
texture2D CreativeLowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; MipLevels = 1; };
sampler2D CreativeLowFreqSamp
{
    Texture   = CreativeLowFreqTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Per-band chroma stats (from olofssonian_chroma_lift UpdateHistory)
texture2D ChromaHistoryTex { Width = 8; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D ChromaHistory
{
    Texture   = ChromaHistoryTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// 1/16-res LF scale 1 — populated by LFDownscale1PS within this technique (vkBasalt cross-technique mips are zero)
texture2D LowFreqMip1Tex { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F; MipLevels = 1; };
sampler2D LowFreqMip1Samp
{
    Texture   = LowFreqMip1Tex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// 1/32-res LF scale 2 — populated by LFDownscale2PS within this technique
texture2D LowFreqMip2Tex { Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F; MipLevels = 1; };
sampler2D LowFreqMip2Samp
{
    Texture   = LowFreqMip2Tex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Neutral-pixel-weighted illuminant estimate — 1×1, written by NeutralIllumPS each frame
texture2D NeutralIllumTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D NeutralIllumSamp
{
    Texture   = NeutralIllumTex;
    MinFilter = POINT;
    MagFilter = POINT;
};


// R190 guided filter base layer — replaces R189 bilateral H/V passes.
// Self-guided, log10-luma space. Adaptive ε (Hu et al. 2023): a_k = var/(（1+ε)·var + η).
// r=3 texels at 1/8-res → 7×7 = 49 taps. No range kernel, no exp() per tap.
#define GF_R    3                           // box radius in texels at 1/8-res (24 px physical)
#define GF_EPS  0.05                        // ε scale — a_k ceiling = 1/(1+GF_EPS) ≈ 0.952
#define GF_ETA  1e-8                        // η bias — pivot at var = GF_ETA/GF_EPS = 2e-7
#define GF_N    ((2 * GF_R + 1) * (2 * GF_R + 1))   // window sample count (49)

texture2D GuidedCoeffTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RG16F; MipLevels = 1; };
sampler2D GuidedCoeffSamp
{
    Texture   = GuidedCoeffTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};
texture2D BilateralLogTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16F; MipLevels = 1; };
sampler2D BilateralLogSamp
{
    Texture   = BilateralLogTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Diffusion blur chain — 1/4-res. DiffusionTex: downsample target + final V-blur output.
// DiffusionHorizTex: H-blur intermediate. Both MipLevels=1; no mips needed after Gaussian.
texture2D DiffusionTex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; MipLevels = 1; };
sampler2D DiffusionSamp
{
    Texture   = DiffusionTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D DiffusionHorizTex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; MipLevels = 1; };
sampler2D DiffusionHorizSamp
{
    Texture   = DiffusionHorizTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};



// ─── Helpers ───────────────────────────────────────────────────────────────

float3 FilmCurveApply(float3 x,
                      float knee_r, float knee_g, float knee_b,
                      float ktoe_r, float ktoe_g, float ktoe_b)
{
    float3 knee_rgb  = float3(knee_r, knee_g, knee_b);
    float3 ktoe_rgb  = max(float3(ktoe_r, ktoe_g, ktoe_b), 0.001);
    float3 above     = max(x - knee_rgb, 0.0);
    float3 below     = max(ktoe_rgb - x, 0.0);
    float3 headroom  = max(1.0 - knee_rgb, 0.001);
    // Upper-mid lift only: midrange-weighted one-sided S (zero at x≤0.5 and x=1, peak ~+1.2% at x≈0.72)
    // body_s clamped to [0,1] input — formula produces runaway positive values for x>1.
    float3 xs        = saturate(x);
    float3 xw        = xs * (1.0 - xs);
    float3 body_s    = max(0.0, xw * xw * (2.0 * xs - 1.0)) * 0.65;
    // Rational shoulder: C1 at knee, asymptotes to 1.0 (SDR ceiling by construction).
    float3 sh_comp   = above * above / (headroom + above);
    // Rational toe: C1 at ktoe, scaled to match prior quadratic toe depth at x=0.
    float3 tc_comp   = (0.06 / ktoe_rgb) * below * below / (ktoe_rgb + below);
    return x + body_s - sh_comp + tc_comp;
}

float LiftChroma(float C, float pivot, float strength)
{
    float t = saturate(1.0 - C / max(pivot, 0.001));
    return C * (1.0 + strength * t * t);
}

// ─── Stage helpers ─────────────────────────────────────────────────────────

float3 ApplyDyeMatrix(float3 lin)
{
    float lin_min   = min(lin.r, min(lin.g, lin.b));
    float sat_proxy = max(lin.r, max(lin.g, lin.b)) - lin_min;
    float ramp      = smoothstep(0.0, 0.25, sat_proxy);
    float3 dom_mask = saturate((lin - lin_min) / max(sat_proxy, 0.001));
    float3 dye      = dom_mask * sat_proxy * ramp * 0.065;
    float3 bl_x;
    bl_x.r = dye.r * 1.00 + dye.g * 0.15 + dye.b * 0.01;
    bl_x.g = dye.r * 0.14 + dye.g * 1.00 + dye.b * 0.06;
    bl_x.b = dye.r * 0.09 + dye.g * 0.09 + dye.b * 1.00;
    return saturate(lin * (1.0 - bl_x + bl_x * bl_x * 0.5));
}

float3 ApplyMaskingCoupler(float3 lin, float print_stock)
{
    float mc_luma = dot(lin, float3(0.2126, 0.7152, 0.0722));
    float mc_w    = saturate(1.0 - mc_luma / 0.75);
    mc_w         *= mc_w;
    float mc_str  = print_stock * 0.008 * mc_w;
    lin.r = saturate(lin.r + mc_str);
    lin.b = saturate(lin.b - mc_str * 0.65);
    return lin;
}

float3 ApplyBleachBypass(float3 lin, float bleach_bypass)
{
    float3 lab_bb   = RGBtoOklab(lin);
    float  bb_dark  = 1.0 - smoothstep(0.0, 0.65, lab_bb.x);
    float  bb_desat = bleach_bypass * lerp(0.05, 0.72, bb_dark);
    lab_bb.y *= (1.0 - bb_desat);
    lab_bb.z *= (1.0 - bb_desat);
    float  bb_mid  = lab_bb.x * (1.0 - lab_bb.x) * 4.0;
    lab_bb.x = saturate(lab_bb.x - bleach_bypass * 0.055 * bb_mid);
    return saturate(OklabToRGB(lab_bb));
}

float3 ApplyPrintStock(float3 lin, float fc_knee_toe, float fc_knee, float print_stock)
{
    float3 ps = lin;
    // 2383 S-curve — two-piece, no gates:
    // Power toe: compresses the full range, strongest in darks (each dye layer has its own
    // H&D curve — power 1.15 darkens 0.10→0.071, 0.30→0.250 at full strength).
    // Reinhard shoulder: rolls off highlights above 0.60.
    ps = pow(max(ps, 1e-6), 1.15);
    float3 d = max(0.0, ps - 0.60);
    ps = ps - d + d / (1.0 + d * 1.5);
    // Midtone desaturation: ~15% chroma loss (2383 dye-layer bleach).
    float luma_ps = dot(ps, float3(0.2126, 0.7152, 0.0722));
    float desat_w = 0.15 * (1.0 - smoothstep(0.0, fc_knee_toe, luma_ps))
                          * (1.0 - smoothstep(fc_knee, 1.0, luma_ps));
    ps = lerp(ps, luma_ps.xxx, desat_w);
    return lerp(lin, saturate(ps), saturate(print_stock));
}

float3 ApplyHalation(float3 lin, float2 uv, float3 lf_mip2, float hal_strength, float hal_gamma,
                     float illum_warm)
{
    // R168: three physical improvements:
    // 1) Exponential PSF: two-scale DoG (tight 1/16−sharp, broad 1/32−1/16) approximates
    //    diffusion-equation base scatter better than single Gaussian.
    // 2) AH layer (2383 rem-jet): attenuates tight direct back-reflection ~40%;
    //    broad scattered component partially bypasses AH → full color weights.
    // 3) Color: red dominant (deepest dye, reaches base), blue near-zero (yellow filter).
    // Illuminant-adaptive rem-jet: incident spectral content shifts halo G weight.
    // Warm scene (illum_warm > 0.39) → more R energy reaches base → relatively less G scatter.
    // Scale 0.25: emulsion stack pre-filtering removes most short-wavelength variation;
    // residual G modulation ~20-30% of a G-component already ~1/10 of R (SPD analysis).
    float3 lf_mip1    = tex2D(LowFreqMip1Samp, uv).rgb;
    float3 ring_tight = max(float3(0,0,0), lf_mip1 - lin);
    float3 ring_broad = max(float3(0,0,0), lf_mip2 - lf_mip1);
    float  tight_luma = dot(ring_tight, float3(0.2126, 0.7152, 0.0722));
    float  hal_lore   = tight_luma / (tight_luma + hal_gamma + 1e-6);
    float  lore_g     = lerp(0.78, 0.94, hal_lore);
    float  lore_b     = lerp(0.22, 0.38, hal_lore);
    float  g_mod      = 1.0 - (illum_warm - 0.39) * 0.25;
    // G weights calibrated to emulsion-physics R:G:B ≈ 30:3:1 (pixls.us spectral model).
    // Previous 0.27/0.45 gave G/R ≈ 0.43 — ~4× too high. 0.07/0.11 → G/R ≈ 0.10.
    float3 col_tight  = float3(0.63, 0.07 * lore_g * g_mod, 0.02 * lore_b);
    float3 col_broad  = float3(1.05, 0.11 * lore_g * g_mod, 0.03 * lore_b);
    return saturate(lin + (ring_tight * col_tight + ring_broad * col_broad) * hal_strength);
}

float3 Apply3WayCC(float3 lin,
                   float shadow_temp, float shadow_tint,
                   float mid_temp,    float mid_tint,
                   float hl_temp,     float hl_tint)
{
    float r19_g   = sqrt(dot(lin, float3(0.2126, 0.7152, 0.0722)));
    float r19_sh  = saturate(1.0 - r19_g / 0.35);
    float r19_hl  = saturate((r19_g - 0.65) / 0.35);
    float r19_mid = 1.0 - r19_sh - r19_hl;
    float3 sh_d  = float3(+shadow_temp + shadow_tint * 0.5, -shadow_tint, -shadow_temp + shadow_tint * 0.5) * 0.0003;
    float3 mid_d = float3(+mid_temp    + mid_tint    * 0.5, -mid_tint,    -mid_temp    + mid_tint    * 0.5) * 0.0003;
    float3 hl_d  = float3(+hl_temp     + hl_tint     * 0.5, -hl_tint,     -hl_temp     + hl_tint     * 0.5) * 0.0003;
    return saturate(lin + sh_d * r19_sh + mid_d * r19_mid + hl_d * r19_hl);
}

float3 ApplyAmbientTint(float3 lab_t, float3 lf_mip2, float r65_sw, float scene_cut)
{
    float3 illum_norm = lf_mip2 / max(dot(lf_mip2, float3(0.2126, 0.7152, 0.0722)), 0.001);
    float3 lab_amb    = RGBtoOklab(illum_norm * 0.18);
    float  lab_t_C    = length(lab_t.yz);
    float  achrom_w   = 1.0 - smoothstep(0.0, 0.05, lab_t_C);
    float  c_gate     = saturate(1.0 - lab_t_C / 0.10);
    float  r66_w      = r65_sw * achrom_w * c_gate * (1.0 - scene_cut) * 0.20;
    lab_t.y = lerp(lab_t.y, lab_amb.y, r66_w);
    lab_t.z = lerp(lab_t.z, lab_amb.z, r66_w);
    return lab_t;
}

float2 ApplyChromaticInduction(float2 ab, float3 lf_mip2, float final_C)
{
    float3 surr     = lf_mip2;
    float3 surr_lab = RGBtoOklab(surr / max(dot(surr, float3(0.2126, 0.7152, 0.0722)), 0.001) * 0.18);
    float  ind_mask = saturate(1.0 - final_C / 0.06);
    ab.x -= surr_lab.y * 0.12 * ind_mask;
    ab.y -= surr_lab.z * 0.12 * ind_mask;
    return ab;
}

// ─── ColorTransformPS stage structs and helpers ────────────────────────────

struct SceneCtx {
    float3 lms_illum_norm;
    float3 cfilm_floor;
    float4 perc;
    float  eff_p25, eff_p75;
    float  zone_log_key, zone_std, zone_str;
    float  ss_08_25, ss_04_25;
    float  scene_cut;
    float  slow_key;
    float  fc_knee,     fc_knee_r,  fc_knee_b;
    float  fc_knee_toe, fc_ktoe_r,  fc_ktoe_b;
    float  shadow_lift_str;
    float  chroma_str_base;
    float  bowley;
    float  scene_mode;
    float  specular_contrast;
    float  illum_warm;   // CAT16 L/M − S/M + 0.5; D65≈0.39, warm>0.39, cool<0.39
    float  median_C;     // scene median Oklab C (highway HWY_MEDIAN_C) [0, 0.30]
};

struct TonalOut { float3 lin; float new_luma; float local_var; };

SceneCtx BuildSceneCtx()
{
    SceneCtx ctx;
    // Illuminant normalization — CAT16 pixel correction removed (R127): game content is
    // display-referred (sRGB→D65); warm lighting is art direction, not a calibration error.
    const float3x3 M_fwd = float3x3(0.302825, 0.602279, 0.070428,
                                     0.153818, 0.777214, 0.085341,
                                     0.027974, 0.147911, 0.908874);
    float3 illum_rgb       = tex2Dlod(NeutralIllumSamp, float4(0.5, 0.5, 0, 0)).rgb;
    float3 illum_norm      = illum_rgb / max(Luma(illum_rgb), 0.001);
    float3 lms_illum       = mul(M_fwd, illum_norm);
    ctx.lms_illum_norm     = lms_illum / max(lms_illum.g, 0.001);
    ctx.illum_warm         = saturate(ctx.lms_illum_norm.r - ctx.lms_illum_norm.b + 0.5);
    ctx.median_C           = clamp(ReadHWY(HWY_MEDIAN_C), 0.0, 0.30);
    ctx.cfilm_floor        = BLACKS * (ctx.lms_illum_norm * float3(1.02, 1.00, 0.97));
    ctx.perc               = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));
    ctx.scene_cut          = ReadHWY(HWY_SCENE_CUT);
    float4 zstats          = tex2Dlod(ChromaHistory, float4(6.5 / 8.0, 0.5 / 4.0, 0, 0));
    ctx.zone_log_key       = zstats.r;
    ctx.zone_std           = zstats.g;
    ctx.eff_p25            = ctx.perc.r;
    ctx.eff_p75            = ctx.perc.b;
    ctx.ss_08_25           = smoothstep(0.06, 0.16, ctx.zone_std);
    ctx.ss_04_25           = smoothstep(0.03, 0.16, ctx.zone_std);
    float lum_att          = smoothstep(0.10, 0.40, ctx.zone_log_key);
    // CONTRAST scale: 1.0 = calibrated default, 0 = off, 2.0 = aggressive.
    ctx.zone_str           = lerp(0.26, 0.16, ctx.ss_08_25)
                           * lerp(1.10, 0.93, lum_att) * (CONTRAST * 0.30);
    ctx.fc_knee            = lerp(0.90, 0.80, saturate((ctx.eff_p75 - 0.60) / 0.30));
    // R147: Bowley skewness — right-skewed (dark dominant, bright tail) → lower knee
    // to catch sparse bright tail that p75-based formula misses when p75 is low.
    ctx.bowley             = (ctx.perc.b + ctx.perc.r - 2.0 * ctx.perc.g)
                           / max(ctx.perc.b - ctx.perc.r, 0.01);
    ctx.fc_knee            = saturate(ctx.fc_knee - saturate(ctx.bowley) * 0.06);
    ctx.fc_knee_toe        = lerp(0.15, 0.25, saturate((0.40 - ctx.eff_p25) / 0.30));
    // R147: mode anchor — when toe sits well above peak dark density, pull it down.
    float mode             = ReadHWY(HWY_MODE);
    float toe_gap          = saturate((ctx.fc_knee_toe - mode - 0.05) / 0.10);
    ctx.fc_knee_toe        = lerp(ctx.fc_knee_toe, mode + 0.05, toe_gap * 0.4);
    ctx.fc_knee_r          = clamp(ctx.fc_knee     * exp2(CURVE_R_KNEE), 0.70, 0.95);
    ctx.fc_knee_b          = clamp(ctx.fc_knee     * exp2(CURVE_B_KNEE), 0.70, 0.95);
    ctx.fc_ktoe_r          = clamp(ctx.fc_knee_toe * exp2(CURVE_R_TOE),  0.08, 0.35);
    ctx.fc_ktoe_b          = clamp(ctx.fc_knee_toe * exp2(CURVE_B_TOE),  0.08, 0.35);
    float _sls_t              = saturate(((ctx.perc.r + ctx.scene_mode) * 0.5 - 0.025) / 0.175);
    float _std_suppress       = smoothstep(0.05, 0.13, ReadHWY(HWY_ZONE_STD));
    ctx.shadow_lift_str       = lerp(1.50, 0.45, _sls_t*_sls_t*_sls_t*(_sls_t*(_sls_t*6.0-15.0)+10.0))
                              * (1.0 - _std_suppress);
    // R162: specular contrast — p90−p50 gap measures isolated bright sources vs scene median.
    ctx.specular_contrast     = saturate((ReadHWY(HWY_P90) - ctx.perc.g) / 0.40);
    ctx.slow_key           = max(tex2Dlod(ChromaHistory, float4(7.5 / 8.0, 0.5 / 4.0, 0, 0)).r, 0.001);
    ctx.scene_mode         = ReadHWY(HWY_MODE);
    ctx.chroma_str_base    = VIBRANCE * 0.04;
    return ctx;
}

float3 ApplyCorrective(float3 lin, float2 uv, float4 lf_mip2_tex, SceneCtx ctx)
{
    float3 lin_p = max(lin, 0.0);
    float  E     = pow(2.0, EXPOSURE);
    float  lum   = Luma(lin_p);
    float  gain  = lerp(E, 1.0, smoothstep(0.55, 0.85, lum));
    float3 lin_e = lin_p * gain;
    // R104: DIR couplers — developer-inhibitor-release cross-channel masking
    {
        float3 log_e = log2(lin_e + 1e-5);
        float3 act   = lin_e * lin_e / (lin_e * lin_e + 0.09);
        float3 cpl   = float3(act.g * 0.12 + act.b * 0.06,
                              act.r * 0.10 + act.b * 0.04,
                              act.r * 0.06 + act.g * 0.08);
        lin_e = saturate(exp2(log_e - cpl * 0.3));
    }
    // ── R105: halation — pre-curve (physical: camera negative, before any processing) ──
    // lf_mip1/lf_mip2 are pre-corrective; lin_e is pre-curve — signals match.
    // R151: p90−p50 gap measures isolated bright sources against scene median.
    float eff_hal_str = HAL_STRENGTH * lerp(1.0, 1.4, ctx.specular_contrast);
    lin_e = ApplyHalation(lin_e, uv, lf_mip2_tex.rgb, eff_hal_str, HAL_GAMMA, ctx.illum_warm);
    // R194: ACES luma inverse — undoes ACES midtone boost below the fixed point (L≈0.728).
    // scale_delta is negative below L≈0.728 (ACES was brightening → inverse darkens back).
    // Above L≈0.728 ACES was compressing — that expansion requires headroom > 1.0 which SDR
    // cannot provide. min() gates to darkening only: no highlight blowup, no tonal disconnect.
    // scale_delta tapers smoothly to zero as L→0.728, so the transition is seamless.
    if (INVERSE_LUMA > 0.0) {
        float  L_disp      = Luma(tex2D(BackBuffer, uv).rgb);
        float  shadow_w    = smoothstep(0.005, 0.04, L_disp);
        const float A = 2.51, B = 0.03, C = 2.43, D = 0.59, E = 0.14;
        float  disc        = ((D*D - 4.0*C*E)*L_disp + 4.0*A*E - 2.0*B*D)*L_disp + B*B;
        float  L_scene     = 0.5*(D*L_disp - B + sqrt(max(disc, 0.0))) / max(A - C*L_disp, 1e-4);
        float  scale_delta = min((L_scene / max(L_disp, 1e-5) - 1.0) * shadow_w, 0.0);
        lin_e *= 1.0 + scale_delta * float(INVERSE_LUMA);
    }
    float3 out_lin = FilmCurveApply(lin_e,
                                    ctx.fc_knee_r, ctx.fc_knee, ctx.fc_knee_b,
                                    ctx.fc_ktoe_r, ctx.fc_knee_toe, ctx.fc_ktoe_b);
    // ── R19: 3-way CC — primary grade before print emulation ──────────────────
    out_lin = Apply3WayCC(out_lin,
                          SHADOW_TEMP, SHADOW_TINT,
                          MID_TEMP, MID_TINT,
                          HIGHLIGHT_TEMP, HIGHLIGHT_TINT);
    return out_lin;
}

TonalOut ApplyTonal(float3 lin, float col_luma, float2 uv, float4 lf_mip2_tex, SceneCtx ctx)
{
    float luma        = Luma(lin);
    // R189 bilateral tonemapper + clarity.
    // BS term: purely from pre-corrective base — no film curve contamination.
    // CS term: full-res post-corrective luma vs pre-corrective base — captures actual
    //          per-pixel detail the 1/8-res source cannot resolve.
    // No-op at BS=CS=0. Independent — either or both can be active.
    {
        float log_base   = tex2D(BilateralLogSamp, uv).r;
        float log_key    = log10(max(ReadHWY(HWY_ZONE_KEY), 1e-3));
        float log_pixel  = log10(max(luma, 1e-3));
        float log_detail = log_pixel - log_base;
        // LOCAL_TONE: lift-only. Gate on max(log_base, log_pixel) — a bright pixel in a
        // locally-dark area (e.g. lamp against dark wall) has low log_base but high log_pixel;
        // gating on base alone would lift the highlight. Using the higher of the two ensures
        // only pixels that are themselves below the global key receive lift.
        float bil_ratio  = pow(10.0, float(LOCAL_TONE)       * 0.025 * max(log_key - max(log_base, log_pixel), 0.0)
                                   + float(CLARITY_STRENGTH) * 0.025 * log_detail);
        bil_ratio        = clamp(bil_ratio, 0.5, 2.0);
        float3 lin_b     = lin * bil_ratio;
        lin              = lin_b / max(max(lin_b.r, max(lin_b.g, lin_b.b)), 1.0);
        luma             = Luma(lin);
    }
    // R29: Multi-Scale Retinex — spatial illuminant normalisation fires before zone S-curve
    // so the S-curve shapes the spatially-equalised signal, not the raw uneven one.
    float illum_s0  = max(tex2D(LowFreqMip1Samp, uv).a, 0.001);
    float illum_s2  = max(lf_mip2_tex.a, 0.001);
    float local_var = abs(illum_s0 - illum_s2);
    float nl_safe   = max(luma, 0.001);
    float log_R     = log2(nl_safe / illum_s0);
    float zk_safe   = max(ctx.zone_log_key, 0.001);
    luma = lerp(luma, saturate(luma * zk_safe / illum_s0), 0.75 * ctx.ss_04_25);

    float4 zone_lvl   = tex2Dlod(ZoneHistorySamp, float4(uv, 0, 0));
    float zone_median = zone_lvl.r;
    float zone_iqr    = zone_lvl.b - zone_lvl.g;
    // R33: CLAHE-inspired clip limit — bounds S-curve slope; tightens when Retinex is engaged
    float clahe_slope = lerp(1.32, 1.12, ctx.ss_04_25);
    float iqr_scale   = min(smoothstep(0.0, 0.25, zone_iqr),
                            (clahe_slope - 1.0) / max(ctx.zone_str, 0.001));
    float delta    = luma - zone_median;
    float zone_adj = ctx.zone_str * iqr_scale * delta * (1.0 - abs(delta));
    float above_w  = smoothstep(-0.05, 0.10, delta);
    float new_luma = saturate(luma + zone_adj * above_w);

    float texture_att     = 1.0 - smoothstep(0.005, 0.030, local_var);
    float detail_protect  = smoothstep(-2.0, -0.5, log_R);
    // R119: fine-texture gate — 4 diagonal bilinear taps give a cheap 3×3 neighbourhood avg.
    // Detects sub-16px texture (fabric, skin grain) invisible to 1/16-res illuminant maps.
    float2 fine_px         = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float  luma_nb         = Luma(0.25 * (
        tex2D(BackBuffer, uv + float2(-0.5, -0.5) * fine_px).rgb +
        tex2D(BackBuffer, uv + float2( 0.5, -0.5) * fine_px).rgb +
        tex2D(BackBuffer, uv + float2(-0.5,  0.5) * fine_px).rgb +
        tex2D(BackBuffer, uv + float2( 0.5,  0.5) * fine_px).rgb));
    float  fine_var        = abs(col_luma - luma_nb);
    float  fine_texture_att = 1.0 - saturate((fine_var - 0.004) / 0.008);
    // R60: temporal context — slow ambient key boosts lift during dark transitions, suppresses on re-entry
    float context_lift   = exp2(log2(ctx.slow_key / zk_safe) * 0.4);
    // R162: suppress shadow lift when isolated bright sources dominate (high specular contrast).
    // High p90−p50 gap = sun/lamp in frame — lifting shadows flattens depth against the source.
    float specular_att   = 1.0 - smoothstep(0.50, 0.90, ctx.specular_contrast) * 0.35;
    float shadow_lift    = ctx.shadow_lift_str * (0.149169 / (illum_s0 * illum_s0 + 0.003))
                         * texture_att * fine_texture_att * detail_protect * context_lift * specular_att;
    float lift_w         = new_luma * smoothstep(0.23, 0.0, new_luma);
    new_luma = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w * SHADOWS);
    // Highlights — soft luma push/pull above L≈0.55. +1.0 brightens, -1.0 recovers.
    new_luma = saturate(new_luma + HIGHLIGHTS * 0.20 * smoothstep(0.55, 0.85, new_luma));
    // R62 Finding 3: chroma-stable tonal — apply luma ratio in Oklab L to prevent zone S-curve from shifting chroma
    float3 lab_t  = RGBtoOklab(saturate(lin));
    float r_tonal = new_luma / max(luma, 0.001);
    float cbrt_r  = exp2(log2(max(r_tonal, 1e-10)) * (1.0 / 3.0));
    lab_t.x = saturate(lab_t.x * cbrt_r);
    // R65: CAM16 Hunt exponent 0.25 — colorfulness ∝ L^0.25 (Hunt 2004, CIECAM02 eq.14-16)
    float r65_scale = exp2(log2(max(r_tonal, 1e-10)) * 0.25);
    float r65_sw    = smoothstep(0.25, 0.0, lab_t.x);
    lab_t.y = lab_t.y * lerp(1.0, r65_scale, r65_sw);
    lab_t.z = lab_t.z * lerp(1.0, r65_scale, r65_sw);
    // R66: ambient shadow tint — inject scene-ambient hue into achromatic lifted shadows.
    lab_t = ApplyAmbientTint(lab_t, lf_mip2_tex.rgb, r65_sw, ctx.scene_cut);

    TonalOut result;
    result.lin       = saturate(OklabToRGB(lab_t));
    result.new_luma  = new_luma;
    result.local_var = local_var;
    return result;
}

float3 ApplyChroma(float3 lin, float new_luma, float local_var,
                   float4 lf_mip2_tex, SceneCtx ctx)
{
    float3 lab    = RGBtoOklab(lin);
    // R183: pre-flash warm shadow cast — fixed warm additive in deep shadows, zero at mid-gray.
    // Models Deakins' practice of fogging negatives with warm colored light. Amber direction.
    lab.y += SHADOW_CAST * 0.020 * (1.0 - smoothstep(0.0, 0.25, lab.x));
    lab.z += SHADOW_CAST * 0.012 * (1.0 - smoothstep(0.0, 0.25, lab.x));
    float  C      = length(lab.yz);
    float  C_stim = C;
    float  h      = OklabHueNorm(lab.y, lab.z);
    // HELMLAB: 2-harmonic Fourier correction aligns Oklab hue toward perceptual hue.
    // Corrects 8.9× non-uniformity in blue-cyan band (HELMLAB 2026, arxiv 2602.23010).
    float  h_theta = h * 6.28318;
    float  sh_h, ch_h;
    sincos(h_theta, sh_h, ch_h);
    float  dh     = sh_h * (0.008 + 0.008 * ch_h);
    float  h_perc = frac(h + dh / 6.28318);

    // ── R52: Purkinje shift — rod-vision blue-green bias in deep shadows ───────
    {
        // R150: dark-dominant scenes (low mode) are physically dim — scotopic vision
        // more active; scale Purkinje up toward the genuine mesopic threshold.
        float eff_purkinje = PURKINJE_STRENGTH
                           * lerp(1.0, 1.3, saturate((0.15 - ctx.scene_mode) / 0.15));
        float scotopic_w = 1.0 - smoothstep(0.0, 0.30, new_luma);  // R117: widened from 0.12; mesopic transition spans full scotopic-photopic range
        lab.y -= 0.006 * scotopic_w * C * eff_purkinje;  // rod peak 507nm is blue-green: shift both a* (green) and b* (blue)
        lab.z -= 0.018 * scotopic_w * C * eff_purkinje;
        lab.yz *= 1.0 - 0.12 * scotopic_w * eff_purkinje;  // rods are achromatic: scotopic desaturation
        C = length(lab.yz);
    }

    // R22: saturation by luminance — shadow desaturation 20% (baked Munsell calibration)
    // + midtone expansion bell from cinema SDR mastering data (Žaganeli et al. 2026)
    // Highlight arm removed — R133 HueBandRollN() owns highlight desaturation.
    float mid_C_boost = 0.08 * smoothstep(0.22, 0.40, lab.x)
                             * (1.0 - smoothstep(0.55, 0.70, lab.x));
    C *= (1.0 + mid_C_boost
             - 0.20 * saturate(1.0 - lab.x / 0.25));
    // R133: Munsell per-hue highlight chroma rolloff (replaces R74 linear ramp).
    // f = (4(1-L))^n: 1 at L≤0.75, 0 at L=1.0. n from HueBandRollN — yellow 0.22,
    // yellow-green 0.27, orange 0.81 (Munsell Renotation V=8→9→10 ratios).
    // Hardcoded — calibration from measured data, not a creative choice.
    float r133_roll = saturate(pow(max(0.0, 4.0 * (1.0 - lab.x)), HueBandRollN(h_perc)));
    C *= r133_roll;

    // R21: per-band hue rotation — compute h_out from original h before chroma lift
    float r21_delta = ROT_RED    * HueBandWeight(h_perc, HB_BAND_RED)
                    + ROT_YELLOW * HueBandWeight(h_perc, HB_BAND_YELLOW)
                    + ROT_GREEN  * HueBandWeight(h_perc, HB_BAND_GREEN)
                    + ROT_CYAN   * HueBandWeight(h_perc, HB_BAND_CYAN)
                    + ROT_BLUE   * HueBandWeight(h_perc, HB_BAND_BLUE)
                    + ROT_MAG    * HueBandWeight(h_perc, HB_BAND_MAGENTA);
    // R125/R126: Bezold-Brücke — anchored at Oklab invariant hues (h=0.25 yellow, h=0.75 blue)
    // ch_h zeros at h=0.25/0.75 by construction. sh2/ch3 via double/triple-angle (7 MAD total).
    // Asymmetry: teal lobe (0.61) ~1.6× orange lobe (0.38) — matches Kurtenbach 1994 data.
    float sh2_h   = 2.0 * sh_h * ch_h;
    float ch3_h   = ch_h * (4.0 * ch_h * ch_h - 3.0);
    r21_delta    += (lab.x - 0.50) * 0.015 * (0.10 * ch_h + 0.50 * sh2_h + 0.30 * ch3_h);
    float h_out  = frac(h_perc + r21_delta * 0.10);
    float hw_o0  = HueBandWeight(h_out, HB_BAND_RED);
    float hw_org = HueBandWeight(h_out, HB_BAND_ORANGE);
    float hw_amb = HueBandWeight(h_out, HB_BAND_AMBER);
    float hw_o1  = HueBandWeight(h_out, HB_BAND_YELLOW);
    float hw_o2  = HueBandWeight(h_out, HB_BAND_GREEN);
    float hw_tel = HueBandWeight(h_out, HB_BAND_TEAL);
    float hw_o3  = HueBandWeight(h_out, HB_BAND_CYAN);
    float hw_azr = HueBandWeight(h_out, HB_BAND_AZURE);
    float hw_o4  = HueBandWeight(h_out, HB_BAND_BLUE);
    float hw_vio = HueBandWeight(h_out, HB_BAND_VIOLET);
    float hw_o5  = HueBandWeight(h_out, HB_BAND_MAGENTA);
    float hw_ros = HueBandWeight(h_out, HB_BAND_ROSE);

    float chroma_str = ctx.chroma_str_base;
    chroma_str *= lerp(1.0, 0.65, smoothstep(0.02, 0.08, local_var));  // R68A: attenuate in textured regions
    float density_str = 50.0;

    // R179: widen pivot weight to 0.14 (was HB_BAND_WIDTH=0.08) so tertiary hues
    // (orange, amber, teal, azure, violet, rose) interpolate between tracked primaries
    // instead of falling in zero-weight dead zones and receiving no lift.
    float new_C = 0.0, total_w = 0.0;
    [unroll] for (int band = 0; band < 6; band++)
    {
        float pivot  = tex2Dlod(ChromaHistory, float4((band + 0.5) / 8.0, 0.5 / 4.0, 0, 0)).r;
        float d_h    = abs(h_perc - GetBandCenter(band));
        d_h          = min(d_h, 1.0 - d_h);
        float wt     = saturate(1.0 - d_h / 0.14);
        float w      = wt * wt * (3.0 - 2.0 * wt);
        new_C       += LiftChroma(C, pivot, chroma_str) * w;
        total_w     += w;
    }
    // max(lifted, C) — lift-only; identity limit at C = 0 by construction
    float lifted_C = (total_w > 0.001) ? new_C / total_w : C;
    // R117D: memory color chroma attraction — gentle boost in canonical luminance range.
    // Complements R73 ceilings: where ceilings prevent over-saturation, this nudges up
    // under-saturation in canonical hue+luminance zones. C gate: achromatic pixels are excluded.
    // Ceiling below still bounds the total — attraction cannot exceed the R73 limit.
    {
        float mem_sky = saturate(hw_o3 * 0.6 + hw_o4 * 0.4) * smoothstep(0.42, 0.65, lab.x);
        float mem_fol = hw_o2 * smoothstep(0.35, 0.58, lab.x) * (1.0 - smoothstep(0.62, 0.75, lab.x));
        float mem_skn = saturate(hw_o0 * 0.5 + hw_o1 * 0.5) * smoothstep(0.30, 0.52, lab.x);
        lifted_C += (0.008 * mem_sky + 0.006 * mem_fol + 0.006 * mem_skn) * C;
    }
    // R73: memory color protection — per-band chroma ceiling (sky/foliage/skin).
    // R81B/R118: full 12-hue wheel. Ceilings defined in hue_bands.fxh (shared with
    // inverse_grade.fx). Ceiling applied before vibrance — R116.
    float C_ceil      = HueCeil(h_out);
    float lifted_C_c  = min(lifted_C, max(C_ceil, C));
    // R71: vibrance — attenuate lift delta on already-saturated pixels.
    float vib_mask = saturate(1.0 - C / 0.22);
    float vib_C    = C + max(lifted_C_c - C, 0.0) * vib_mask;
    float final_C  = vib_C;

    // Per-band saturation — ±1.0 → ±80% chroma scale per hue band.
    float sat_delta = SAT_RED    * HueBandWeight(h_perc, HB_BAND_RED)
                    + SAT_YELLOW * HueBandWeight(h_perc, HB_BAND_YELLOW)
                    + SAT_GREEN  * HueBandWeight(h_perc, HB_BAND_GREEN)
                    + SAT_CYAN   * HueBandWeight(h_perc, HB_BAND_CYAN)
                    + SAT_BLUE   * HueBandWeight(h_perc, HB_BAND_BLUE)
                    + SAT_MAG    * HueBandWeight(h_perc, HB_BAND_MAGENTA);
    final_C = max(0.0, final_C * (1.0 + sat_delta * 0.80));
    // Global saturation — -1.0 = greyscale, 0 = passthrough, +1.0 = 2× chroma.
    final_C = max(0.0, final_C * (1.0 + SATURATION));


    // Vector-space (a,b) reconstruction — rotate original direction by R21 delta
    float r21_cos, r21_sin;
    sincos(r21_delta * (0.10 * 6.28318), r21_sin, r21_cos);
    float2 ab_in  = float2(lab.y * r21_cos - lab.z * r21_sin,
                           lab.y * r21_sin + lab.z * r21_cos);
    float  C_safe = max(C, 1e-6);
    float2 ab_s   = ab_in * (final_C / C_safe);

    // Abney scene-chroma scale: chromatic adaptation amplifies hue shifts in vivid scenes.
    // median_C [0,0.30] → scale [1.0, 1.075] — inert in near-achromatic, +7.5% max in vivid.
    // 0.25 calibrated from surround-chroma induction literature (Kirschmann, Pridmore 2007).
    float abney_scale = 1.0 + ctx.median_C * 0.25;
    float abney  = (+hw_o0 * 0.06    // RED     — shifts toward yellow
                   - hw_o1 * 0.01    // YELLOW  — near null (Pridmore 2007: smallest Abney shift)
                   + hw_o2 * 0.02    // GREEN   — shifts toward yellow-green (R69)
                   - hw_o3 * 0.08    // CYAN    — shifts toward yellow-green (Pridmore: largest)
                   + hw_o4 * 0.04    // BLUE    — shifts toward purple
                   + hw_o5 * 0.03) * C_stim * abney_scale;
    float dtheta = +(GREEN_HUE_COOL * 2.0 * 3.14159265) * hw_o2 * final_C + abney;
    float cos_dt = 1.0 - dtheta * dtheta * 0.5;
    float sin_dt = dtheta;
    float f_oka  = ab_s.x * cos_dt - ab_s.y * sin_dt;
    float f_okb  = ab_s.x * sin_dt + ab_s.y * cos_dt;

    // Hellwig 2022: hue-dependent H-K correction, C^0.587 (R15)
    // OPT-1: derive sh/ch from HELMLAB+R21 results — eliminates one quarter-rate sincos.
    // Small-angle for dh (max |dh|=0.016 rad, error <= dh²/2 = 1.28e-4); R21 is exact.
    float sh_p = sh_h + ch_h * dh;
    float ch_p = ch_h - sh_h * dh;
    float sh   = sh_p * r21_cos + ch_p * r21_sin;
    float ch   = ch_p * r21_cos - sh_p * r21_sin;
    float f_hk     = -0.160 * ch + 0.132 * (ch*ch - sh*sh) - 0.405 * sh + 0.080 * (2.0*sh*ch) + 0.792;
    float hk_exp   = lerp(0.52, 0.64, saturate(ctx.zone_log_key / 0.50));
    // Hellwig 2022 + Nayatani: H-K effect is STRONGER at low adapting luminance (mesopic) and
    // weakens toward bright photopic — lerp goes high→low with scene key (inverted from prior).
    // Gate inverted: H-K strongest in darks/mids, fades above L=0.55 (highlights need less
    // correction — consistent with f₁J = 1.52 − 0.013J from laser-display calibration study).
    float hk_coeff = lerp(0.32, 0.18, saturate(ctx.zone_log_key / 0.50));
    float hk_boost = 1.0 + hk_coeff * f_hk * pow(max(final_C, 0.0), hk_exp);
    float final_L  = saturate(lab.x / lerp(1.0, hk_boost, 1.0 - smoothstep(0.55, 0.90, lab.x)));

    // R117C: chromatic induction — broad surround hue nudges near-achromatic pixels toward complement.
    // Simultaneous contrast: a grey patch in a coloured surround takes on a slight opposite hue tinge.
    // Uses LowFreqMip2 (1/32-res, already read by R66 + halation) as the spatial surround estimate.
    float2 ab_ind = ApplyChromaticInduction(float2(f_oka, f_okb), lf_mip2_tex.rgb, final_C);
    f_oka = ab_ind.x; f_okb = ab_ind.y;

    // Gamut-distance density: headroom limits darkening near the sRGB boundary
    float3 rgb_probe  = OklabToRGB(float3(final_L, f_oka, f_okb));
    float  headroom   = saturate(1.0 - max(rgb_probe.r, max(rgb_probe.g, rgb_probe.b)));
    float  delta_C    = max(final_C - C, 0.0);
    float  density_L  = saturate(final_L - delta_C * headroom * (density_str / 100.0));
    // R68B: gamut pre-knee — Reinhard soft chroma rolloff in last 12% of headroom.
    float ck_near = max(0.0, 0.12 - headroom) / 0.12;
    float ck_fac  = 1.0 - 0.18 * ck_near / (1.0 + ck_near);
    f_oka *= ck_fac;
    f_okb *= ck_fac;
    // R78: constant-hue gamut projection — gclip applied in Oklab ab space, not RGB.
    // rmax_probe from existing rgb_probe; conservative (slightly over-compresses).
    float  rmax_probe = max(rgb_probe.r, max(rgb_probe.g, rgb_probe.b));
    float  L_grey     = density_L * density_L * density_L;
    float  gclip_ok   = saturate((1.0 - L_grey) / max(rmax_probe - L_grey, 0.001));
    float3 chroma_rgb = OklabToRGB(float3(density_L, f_oka * gclip_ok, f_okb * gclip_ok));
    return saturate(chroma_rgb);
}

// ─── Look Modification Transform — post-grade print emulation ──────────────

float3 ApplyLook(float3 lin, SceneCtx ctx)
{
    float3 out_lin = lin;
    // ── R51: print stock + R110: masking coupler + R130: dye matrix + bleach ──
    // Fires after all tonal and chroma work — LMT position per ACES convention.
    out_lin = ApplyPrintStock(out_lin, ctx.fc_knee_toe, ctx.fc_knee, PRINT_STOCK);
    out_lin = ApplyMaskingCoupler(out_lin, PRINT_STOCK);
    out_lin = ApplyDyeMatrix(out_lin);
    out_lin = ApplyBleachBypass(out_lin, BLEACH_BYPASS);
    // R192: printer lights — per-channel contact-printer exposure after all emulsion work.
    // 25 = neutral, 1 point = 1/12 stop. Mirrors film lab RGB printer head notation.
    out_lin *= pow(2.0, float3(PRINTER_R - 25, PRINTER_G - 25, PRINTER_B - 25) / 12.0);
    return saturate(out_lin);
}

// ─── ColorTransform pixel shader ───────────────────────────────────────────

float4 ColorTransformPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col      = tex2D(BackBuffer, uv);
    SceneCtx ctx       = BuildSceneCtx();
    float4 lf_mip2_tex = tex2D(LowFreqMip2Samp, uv);

    float  col_luma = Luma(col.rgb);
    float3 lin      = col.rgb * (WHITES - ctx.cfilm_floor) + ctx.cfilm_floor;
    lin = lerp(lin, ApplyCorrective(lin, uv, lf_mip2_tex, ctx), CORRECTIVE_STRENGTH * 0.01);

    TonalOut tonal      = ApplyTonal(lin, col_luma, uv, lf_mip2_tex, ctx);
    float    tonal_gate = TONAL_STRENGTH * 0.01;
    tonal.lin       = lerp(lin,       tonal.lin,       tonal_gate);
    tonal.new_luma  = lerp(Luma(lin), tonal.new_luma,  tonal_gate);
    tonal.local_var = tonal.local_var * tonal_gate;

    float3 result  = lerp(tonal.lin, ApplyChroma(tonal.lin, tonal.new_luma, tonal.local_var, lf_mip2_tex, ctx), CHROMA_STRENGTH * 0.01);
    result = lerp(result, ApplyLook(result, ctx), LOOK_STRENGTH * 0.01);

    // dither: break 8-bit BackBuffer quantization — converts banding to imperceptible noise
    // R89: IGN blue-noise dither (Jimenez 2016) — pushes quantization error to high freq
    float dither = frac(52.9829189 * frac(dot(pos.xy, float2(0.06711056, 0.00583715)))) - 0.5;
    result = saturate(result + dither * (1.0 / 255.0));

    return float4(result, col.a);
}

// ─── LF downscale passes — build mip1 and mip2 within this technique ──────────────

float4 LFDownscale1PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // 2× box filter: 4 taps at ±half-texel in mip0 space (mip0 texel = 8/BUFFER px)
    float2 s = float2(4.0 / BUFFER_WIDTH, 4.0 / BUFFER_HEIGHT);
    return (tex2D(CreativeLowFreqSamp, uv + float2( s.x,  s.y))
          + tex2D(CreativeLowFreqSamp, uv + float2(-s.x,  s.y))
          + tex2D(CreativeLowFreqSamp, uv + float2( s.x, -s.y))
          + tex2D(CreativeLowFreqSamp, uv + float2(-s.x, -s.y))) * 0.25;
}

float4 LFDownscale2PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // 2× box filter: 4 taps at ±half-texel in mip1 space (mip1 texel = 16/BUFFER px)
    float2 s = float2(8.0 / BUFFER_WIDTH, 8.0 / BUFFER_HEIGHT);
    return (tex2D(LowFreqMip1Samp, uv + float2( s.x,  s.y))
          + tex2D(LowFreqMip1Samp, uv + float2(-s.x,  s.y))
          + tex2D(LowFreqMip1Samp, uv + float2( s.x, -s.y))
          + tex2D(LowFreqMip1Samp, uv + float2(-s.x, -s.y))) * 0.25;
}

// ─── R189 bilateral log-luma passes ──────────────────────────────────────────
// H-pass: sample CreativeLowFreqSamp (1/8-res), convert to log10 luma, bilateral filter.
// R190 guided filter — Pass 1: compute local linear model coefficients (a_k, b_k).
// Self-guided in log10-luma space. Adaptive ε (Hu 2023): a_k = var/((1+ε)·var + η).
// Reads CreativeLowFreqSamp (pre-corrective 1/8-res RGBA16F). Writes GuidedCoeffTex (RG16F).
float2 GuidedCoeffPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float px = 8.0 / BUFFER_WIDTH;
    float py = 8.0 / BUFFER_HEIGHT;
    float sum_I = 0.0, sum_II = 0.0;
    [unroll] for (int dy = -GF_R; dy <= GF_R; dy++)
    [unroll] for (int dx = -GF_R; dx <= GF_R; dx++)
    {
        float I = log10(max(Luma(tex2D(CreativeLowFreqSamp, uv + float2(dx * px, dy * py)).rgb), 1e-3));
        sum_I  += I;
        sum_II += I * I;
    }
    float mean_I  = sum_I  / GF_N;
    float mean_II = sum_II / GF_N;
    float var_I   = max(mean_II - mean_I * mean_I, 0.0);
    float a_k     = var_I / ((1.0 + GF_EPS) * var_I + GF_ETA);
    float b_k     = (1.0 - a_k) * mean_I;
    return float2(a_k, b_k);
}

// R190 guided filter — Pass 2: average coefficients over window, reconstruct base layer.
// Reads GuidedCoeffSamp (RG16F) + center pixel from CreativeLowFreqSamp.
// Writes BilateralLogTex (R16F) — same slot as R189, ApplyTonal unchanged.
float GuidedBasePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float px = 8.0 / BUFFER_WIDTH;
    float py = 8.0 / BUFFER_HEIGHT;
    float sum_a = 0.0, sum_b = 0.0;
    [unroll] for (int dy = -GF_R; dy <= GF_R; dy++)
    [unroll] for (int dx = -GF_R; dx <= GF_R; dx++)
    {
        float2 ab = tex2D(GuidedCoeffSamp, uv + float2(dx * px, dy * py)).rg;
        sum_a += ab.r;
        sum_b += ab.g;
    }
    float mean_a = sum_a / GF_N;
    float mean_b = sum_b / GF_N;
    float I_c    = log10(max(Luma(tex2D(CreativeLowFreqSamp, uv).rgb), 1e-3));
    return mean_a * I_c + mean_b;
}

// ─── Diffusion passes (merged from pro_mist.fx — saves one inter-effect overhead) ──

float4 DiffusionDownsamplePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 d = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float3 c  = tex2D(BackBuffer, uv + float2(-d.x, -d.y)).rgb;
           c += tex2D(BackBuffer, uv + float2(+d.x, -d.y)).rgb;
           c += tex2D(BackBuffer, uv + float2(-d.x, +d.y)).rgb;
           c += tex2D(BackBuffer, uv + float2(+d.x, +d.y)).rgb;
    return float4(c * 0.25, 1.0);
}

// ─── Diffusion Gaussian blur — separable 9-tap, σ=2 output texels (~8 px at 1080p) ──
// Weights (normalized): [0.2824, 0.2200, 0.1039, 0.0298, 0.0052]

float4 DiffusionBlurHPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float dx = 4.0 / BUFFER_WIDTH;
    float3 c  = tex2D(DiffusionSamp, uv).rgb                              * 0.2824;
           c += tex2D(DiffusionSamp, uv + float2(+1.0*dx, 0.0)).rgb      * 0.2200;
           c += tex2D(DiffusionSamp, uv + float2(-1.0*dx, 0.0)).rgb      * 0.2200;
           c += tex2D(DiffusionSamp, uv + float2(+2.0*dx, 0.0)).rgb      * 0.1039;
           c += tex2D(DiffusionSamp, uv + float2(-2.0*dx, 0.0)).rgb      * 0.1039;
           c += tex2D(DiffusionSamp, uv + float2(+3.0*dx, 0.0)).rgb      * 0.0298;
           c += tex2D(DiffusionSamp, uv + float2(-3.0*dx, 0.0)).rgb      * 0.0298;
           c += tex2D(DiffusionSamp, uv + float2(+4.0*dx, 0.0)).rgb      * 0.0052;
           c += tex2D(DiffusionSamp, uv + float2(-4.0*dx, 0.0)).rgb      * 0.0052;
    return float4(c, 1.0);
}

float4 DiffusionBlurVPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float dy = 4.0 / BUFFER_HEIGHT;
    float3 c  = tex2D(DiffusionHorizSamp, uv).rgb                         * 0.2824;
           c += tex2D(DiffusionHorizSamp, uv + float2(0.0, +1.0*dy)).rgb * 0.2200;
           c += tex2D(DiffusionHorizSamp, uv + float2(0.0, -1.0*dy)).rgb * 0.2200;
           c += tex2D(DiffusionHorizSamp, uv + float2(0.0, +2.0*dy)).rgb * 0.1039;
           c += tex2D(DiffusionHorizSamp, uv + float2(0.0, -2.0*dy)).rgb * 0.1039;
           c += tex2D(DiffusionHorizSamp, uv + float2(0.0, +3.0*dy)).rgb * 0.0298;
           c += tex2D(DiffusionHorizSamp, uv + float2(0.0, -3.0*dy)).rgb * 0.0298;
           c += tex2D(DiffusionHorizSamp, uv + float2(0.0, +4.0*dy)).rgb * 0.0052;
           c += tex2D(DiffusionHorizSamp, uv + float2(0.0, -4.0*dy)).rgb * 0.0052;
    return float4(c, 1.0);
}

// R132: polydisperse scatter — longer λ (red) diffracts more broadly through filter media.
// R115/R131: A) additive shimmer (blur>sharp only); B) soft midtone overlay (bell-gated).
float3 ApplyDiffusionBloom(float3 base_rgb, float3 diff_blur, float adapt_str, float eff_diff)
{
    float3 ch_scatter = float3(1.15, 1.00, 0.85);
    float3 bloom_raw  = max(0.0, diff_blur - base_rgb);
    float  src_gate   = smoothstep(0.10, 0.40, Luma(diff_blur));
    float3 bloom      = bloom_raw / (bloom_raw + 0.08) * src_gate * ch_scatter;
    float3 result     = saturate(base_rgb + bloom * adapt_str);
    float  luma_r     = Luma(result);
    float  mid_gate   = luma_r * (1.0 - luma_r) * 4.0;
    return saturate(lerp(result, diff_blur, (0.10 + eff_diff * 0.09) * mid_gate * ch_scatter));
}

float3 pcg3d_hash(uint3 v)
{
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    return float3(v) * (1.0 / 4294967296.0);
}

float3 GrainValueNoise(float2 p, uint slot)
{
    float2 g = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float3 n00 = pcg3d_hash(uint3(uint(g.x),     uint(g.y),     slot));
    float3 n10 = pcg3d_hash(uint3(uint(g.x) + 1, uint(g.y),     slot));
    float3 n01 = pcg3d_hash(uint3(uint(g.x),     uint(g.y) + 1, slot));
    float3 n11 = pcg3d_hash(uint3(uint(g.x) + 1, uint(g.y) + 1, slot));
    return lerp(lerp(n00, n10, u.x), lerp(n01, n11, u.x), u.y) - 0.5;
}

// R167/R174: Selwyn 2383 film grain. Single 24fps slot snap — no dissolve, no jitter.
// Cross-dissolve (R169/R170) caused rain: smooth temporal change at fixed screen coords
// reads as directed motion during camera movement. Snap transitions are spatially
// uncorrelated between slots so the eye reads them as grain, not streaking.
// Per-channel GrainValueNoise at R167 sizes (R×1.00 / G×0.90 / B×1.15); luma_scale
// lerp(2.5, 1.5, L_g) — 2.5px shadow / 1.5px highlight at 1440p, visually correct for
// monitor viewing distance. R173: silver_boost raises blue-noise weight in shadows.
// Hash calls: 3×GrainValueNoise(4 corners) + 2 blue-noise = 14 total.
float3 ApplyFilmGrain(float3 rgb, float2 pos_xy)
{
    uint   slot       = uint(FRAME_TIMER / 41.667);
    float  res_scale  = BUFFER_HEIGHT / 1440.0;
    float2 p          = pos_xy / res_scale;
    float  L_g        = pow(max(Luma(rgb), 0.0), 1.0 / 2.2);
    float  luma_scale = 2.5;
    float  silver_boost = BLEACH_BYPASS * (1.0 - smoothstep(0.0, 0.65, L_g)) * 0.30;
    float  g_r        = GrainValueNoise(p / (luma_scale * 1.15), slot     ).r;
    float  g_g        = GrainValueNoise(p / (luma_scale * 1.00), slot + 3u).g;
    float  g_b        = GrainValueNoise(p / (luma_scale * 0.85), slot + 5u).b;
    float3 g_coarse   = float3(g_r, g_g, g_b);
    float3 ha         = pcg3d_hash(uint3(uint(p.x),     uint(p.y),     slot + 7u));
    float3 hb         = pcg3d_hash(uint3(uint(p.x) + 1, uint(p.y) + 1, slot + 7u));
    float  fine_w     = 0.30 + silver_boost;
    float3 gnoise     = g_coarse * (1.0 - fine_w) + (ha - hb) * 0.5 * fine_w;
    float  env        = GRAIN_STRENGTH * 0.05 * sqrt(max(0.0, 1.0 - L_g));
    return saturate(rgb + gnoise * env * float3(1.00, 0.80, 1.50));
}

float4 DiffusionPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 base = tex2D(BackBuffer, uv);

    // Eye shape rotated 90°: points off-screen top/bottom (|dy|=0.70 > screen ±0.50),
    // widest at vertical center = 25% of screen width (±12.5% from center-x).
    // Diffusion = 0 inside eye, builds from eye boundary to screen edge.
    float2 c_diff      = uv - 0.5;
    float  eye_x_bound = 0.125 * sqrt(max(0.0, 1.0 - (c_diff.y / 0.70) * (c_diff.y / 0.70)));
    float  dist_out    = max(0.0, abs(c_diff.x) - eye_x_bound);
    float  r           = saturate(dist_out / 0.375);
    float  diff_radial = 0.0;
    diff_radial = lerp(diff_radial, 0.25, smoothstep(0.15, 0.40, r));
    diff_radial = lerp(diff_radial, 0.75, smoothstep(0.40, 0.70, r));
    diff_radial = lerp(diff_radial, 1.00, smoothstep(0.70, 0.90, r));
    float  eff_diff    = DIFFUSION_STRENGTH * diff_radial;

    float3 diff_blur = tex2Dlod(DiffusionSamp, float4(uv, 0, 0)).rgb;

    float4 perc           = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));
    float  iqr            = perc.b - perc.r;
    float  adapt_str      = eff_diff * 0.22 * lerp(0.8, 1.2, saturate(iqr / 0.5));
    float  zone_log_key   = tex2Dlod(ChromaHistory, float4(6.5 / 8.0, 0.5 / 4.0, 0, 0)).r;
    float  diff_key_scale = lerp(1.20, 0.85, smoothstep(0.05, 0.25, zone_log_key));
    float  diff_ap_scale  = lerp(1.10, 0.90, saturate((EXPOSURE - 0.70) / 0.60));
    float  diff_bowley    = (perc.b + perc.r - 2.0 * perc.g) / max(perc.b - perc.r, 0.01);
    adapt_str *= diff_key_scale * diff_ap_scale * lerp(1.0, 1.3, saturate(diff_bowley));

    float3 result = ApplyDiffusionBloom(base.rgb, diff_blur, adapt_str, eff_diff);

    float dither = frac(52.9829189 * frac(dot(pos.xy, float2(0.06711056, 0.00583715)))) - 0.5;
    result += dither * (1.0 / 255.0);

    result = ApplyFilmGrain(result, pos.xy);

    // 2×2 red activity indicator — top-left corner, pipeline-on check
    result = lerp(result, float3(1.0, 0.0, 0.0), step(pos.x, 1.5) * step(pos.y, 1.5));

    return float4(result, base.a);
}

// ─── R124B: Neutral-pixel-weighted illuminant estimation ───────────────────
// Samples CreativeLowFreqTex at 16×9 grid (144 points). Near-grey pixels
// (Oklab C < 0.10) carry illuminant color reliably; saturated pixels are noise.
// Falls back to grey world when fewer than ~8/144 samples are neutral.
float4 NeutralIllumPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 neutral_acc = 0.0;
    float3 grey_acc    = 0.0;
    float  total_w     = 0.0;

    [unroll] for (int iy = 0; iy < 9; iy++)
    [unroll] for (int ix = 0; ix < 16; ix++)
    {
        float2 suv = float2((ix + 0.5) / 16.0, (iy + 0.5) / 9.0);
        float3 rgb = tex2Dlod(CreativeLowFreqSamp, float4(suv, 0, 0)).rgb;
        float3 lab = RGBtoOklab(rgb);
        float  C   = length(lab.yz);
        float  w   = 1.0 - smoothstep(0.04, 0.10, C);
        neutral_acc += rgb * w;
        grey_acc    += rgb;
        total_w     += w;
    }

    float3 grey_world   = grey_acc * (1.0 / 144.0);
    float3 neutral_mean = neutral_acc / max(total_w, 0.001);
    float  conf         = saturate(total_w / 8.0);
    return float4(lerp(grey_world, neutral_mean, conf), 1.0);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique OlofssonianColorGrade
{
    pass LFDownscale1
    {
        VertexShader = PostProcessVS;
        PixelShader  = LFDownscale1PS;
        RenderTarget = LowFreqMip1Tex;
    }
    pass LFDownscale2
    {
        VertexShader = PostProcessVS;
        PixelShader  = LFDownscale2PS;
        RenderTarget = LowFreqMip2Tex;
    }
    pass NeutralIllum
    {
        VertexShader = PostProcessVS;
        PixelShader  = NeutralIllumPS;
        RenderTarget = NeutralIllumTex;
    }
    pass GuidedCoeff
    {
        VertexShader = PostProcessVS;
        PixelShader  = GuidedCoeffPS;
        RenderTarget = GuidedCoeffTex;
    }
    pass GuidedBase
    {
        VertexShader = PostProcessVS;
        PixelShader  = GuidedBasePS;
        RenderTarget = BilateralLogTex;
    }
    pass ColorTransform
    {
        VertexShader = PostProcessVS;
        PixelShader  = ColorTransformPS;
    }
    pass DiffusionDownsample
    {
        VertexShader = PostProcessVS;
        PixelShader  = DiffusionDownsamplePS;
        RenderTarget = DiffusionTex;
    }
    pass DiffusionBlurH
    {
        VertexShader = PostProcessVS;
        PixelShader  = DiffusionBlurHPS;
        RenderTarget = DiffusionHorizTex;
    }
    pass DiffusionBlurV
    {
        VertexShader = PostProcessVS;
        PixelShader  = DiffusionBlurVPS;
        RenderTarget = DiffusionTex;
    }
    pass Diffusion
    {
        VertexShader = PostProcessVS;
        PixelShader  = DiffusionPS;
    }
}
