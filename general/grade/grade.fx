// creative_color_grade.fx — Mega-pass: all downstream color work in one full-res pass
#include "../highway.fxh"
#include "../hue_bands.fxh"
#include "../common.fxh"
//
// Eliminates 3 inter-pass VRAM read-write cycles by running in registers:
//   1. EXPOSURE gamma + scene-adaptive FilmCurve (per-channel knee/toe from creative_values)
//   2. Zone contrast S-curve (auto) + hue-selective luma contrast + Shadow lift
//   3. Oklab chroma lift + gamut compress + R21/R22
//
// Reads from BackBuffer (post-corrective). ZoneHistoryTex, chroma stats, and scene
// percentiles arrive via TexHwyTex (ReadTexHwyChroma / ReadTexHwyPerc / ReadHWY).

#ifndef SHADER_PIPELINE_COMBINED
#include "creative_values.fx"
#endif

// Optional game-specific color-design controls default to neutral when omitted from a profile.
#ifndef LUMA_CONTRAST_RED
#define LUMA_CONTRAST_RED 0.0
#define LUMA_CONTRAST_YELLOW 0.0
#define LUMA_CONTRAST_GREEN 0.0
#define LUMA_CONTRAST_CYAN 0.0
#define LUMA_CONTRAST_BLUE 0.0
#define LUMA_CONTRAST_MAG 0.0
#define HUE_RED 0.0
#define HUE_YELLOW 0.0
#define HUE_GREEN 0.0
#define HUE_CYAN 0.0
#define HUE_BLUE 0.0
#define HUE_MAG 0.0
#define VIBRANCE 0.0
#define SAT_RED 0.0
#define SAT_YELLOW 0.0
#define SAT_GREEN 0.0
#define SAT_CYAN 0.0
#define SAT_BLUE 0.0
#define SAT_MAG 0.0
#endif

#ifndef SATURATION
#define SATURATION 0.0
#endif

#ifndef RETINEX_STRENGTH
#define RETINEX_STRENGTH 1.0
#endif
#ifndef ZONE_CONTRAST_STRENGTH
#define ZONE_CONTRAST_STRENGTH 1.0
#endif
#ifndef SHADOW_LIFT_STRENGTH
#define SHADOW_LIFT_STRENGTH 1.0
#endif

#ifndef SHADER_PIPELINE_COMBINED
uniform float FRAME_TIMER < source = "timer"; >;        // ms since app start
#endif
uniform float GRADE_FRAME_TIME < source = "frametime"; >; // ms per frame

// ─── Chroma lift constants ─────────────────────────────────────────────────
#define GREEN_HUE_COOL  (4.0 / 360.0)


// ─── Textures ──────────────────────────────────────────────────────────────

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

// Scene percentiles read from TexHwyTex via ReadTexHwyPerc() (common.fxh).

// Zone medians (from corrective.fx SmoothZoneLevels)
#ifndef SHADER_PIPELINE_COMBINED
texture2D ZoneHistoryTex { Width = 4; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D ZoneHistorySamp
{
    Texture   = ZoneHistoryTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};
#endif

// 1/8-res low-freq base: TexHwyTex spatial lane (written by analysis_frame, luma in .a).
// Use TexHwySamp (declared in common.fxh) with UV V scaled by TEX_HWY_SPATIAL_H/TEX_HWY_TOTAL_H.
// ChromaHistory reads via ReadTexHwyChroma() (common.fxh).

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

// Scene-adaptive controls are persisted separately so gradual lighting changes
// do not pump the grade. ColorTransform reads the previous frame; the final
// history pass writes the current smoothed values.
texture2D AdaptiveHistoryTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D AdaptiveHistorySamp
{
    Texture   = AdaptiveHistoryTex;
    MinFilter = POINT;
    MagFilter = POINT;
};

// R190 guided filter base layer — replaces R189 bilateral H/V passes.
// Self-guided, log2-luma space. Local variance chooses ε: stronger smoothing in flat fields,
// lower damping around structured edges.
// r=3 texels at 1/8-res → 7×7 = 49 taps. No range kernel, no exp() per tap.
#define GF_R        3                       // box radius in texels at 1/8-res (24 px physical)
#define GF_EPS_MIN  0.025                   // high-variance/detail ceiling: a_k <= 0.976
#define GF_EPS_MAX  0.100                   // low-variance/flat-field ceiling: a_k <= 0.909
#define GF_ETA      1e-8                    // η bias for near-zero variance stability
#define GF_N        ((2 * GF_R + 1) * (2 * GF_R + 1))   // window sample count (49)

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


// ─── Helpers ───────────────────────────────────────────────────────────────

float3 FilmCurveApply(float3 x, float knee)
{
    float  y         = max(Luma(max(x, 0.0)), 0.0);
    knee             = saturate(knee);
    float  above     = max(y - knee, 0.0);
    float  headroom  = max(1.0 - knee, 0.001);
    // Monotonic rational shoulder: identity through the knee, then smooth
    // compression with a nonzero slope that asymptotically approaches 1.0.
    float  shoulder  = above * above / (headroom + above);
    float  ratio     = 1.0 - shoulder / max(y, 1e-10);
    return x * ratio;
}

float LiftChroma(float C, float pivot, float strength)
{
    float t = saturate(1.0 - C / max(pivot, 0.001));
    return C * (1.0 + strength * t * t);
}

// ─── Stage helpers ─────────────────────────────────────────────────────────

float3 ApplyDyeMatrix(float3 lin, float print_stock)
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
    float3 result = saturate(lin * (1.0 - bl_x + bl_x * bl_x * 0.5));
    return lerp(lin, result, saturate(print_stock));
}

float3 ApplyMaskingCoupler(float3 lin, float print_stock)
{
    float mc_luma  = Luma(lin);
    float mc_w     = saturate(1.0 - mc_luma / 0.75);
    // Preserve true black: the masking coupler must not add colored energy
    // to the pedestal. Fade its additive density correction in above black.
    mc_w          *= smoothstep(0.002, 0.05, mc_luma);
    mc_w          *= mc_w;
    float mc_str   = 0.008 * mc_w;
    float3 warmed  = lin;
    warmed.r = saturate(lin.r + mc_str);
    warmed.b = saturate(lin.b - mc_str * 0.65);
    return lerp(lin, warmed, saturate(print_stock));
}

float3 ApplyPrintStock(float3 lin, float fc_knee_toe, float fc_knee, float print_stock)
{
    float3 ps = lin;
    // 2383 S-curve — two-piece, no gates:
    // Power toe: compresses the full range, strongest in darks (each dye layer has its own
    // H&D curve — power 1.15 darkens 0.10→0.071, 0.30→0.250 at full strength).
    // Reinhard shoulder: rolls off highlights above 0.60.
    ps = pow(max(ps, 0.0), 1.15);
    float3 d = max(0.0, ps - 0.60);
    ps = ps - d + d / (1.0 + d * 1.5);
    // Midtone desaturation: ~15% chroma loss (2383 dye-layer bleach).
    float luma_ps = Luma(ps);
    float desat_w = 0.15 * smoothstep(0.0, fc_knee_toe, luma_ps)
                          * (1.0 - smoothstep(fc_knee, 1.0, luma_ps));
    ps = lerp(ps, luma_ps.xxx, desat_w);
    return lerp(lin, saturate(ps), saturate(print_stock));
}

float3 Apply3WayCC(float3 lin,
                   float shadow_temp, float shadow_tint,
                   float mid_temp,    float mid_tint,
                   float hl_temp,     float hl_tint,
                   float key_L)
{
    // Oklab a/b shift: temp → b-axis (warm=positive, cool=negative),
    // tint → a-axis (magenta=positive, green=negative). Orthogonal by construction.
    // Zones adapt to scene key via ZoneShadowW/ZoneHighlightW (common.fxh).
    float3 lab   = RGBtoOklabLinear(lin);
    float  L     = lab.x;
    float  sh_w  = ZoneShadowW(L, key_L);
    float  hl_w  = ZoneHighlightW(L, key_L);
    float  mid_w = ZoneMidW(L, key_L);
    float black_gate = smoothstep(0.0, 0.15, L);
    lab.y += (shadow_tint * sh_w + mid_tint * mid_w + hl_tint * hl_w) * 0.06 * black_gate;
    lab.z += (shadow_temp * sh_w + mid_temp * mid_w + hl_temp * hl_w) * 0.06 * black_gate;
    return OklabToRGB(lab);
}

float3 ApplyAmbientTint(float3 lab_t, float3 lf_mip2, float r65_sw, float scene_cut)
{
    float3 illum_norm = lf_mip2 / max(Luma(lf_mip2), 0.001);
    float3 lab_amb    = RGBtoOklab(illum_norm * 0.18);
    float  lab_t_C    = length(lab_t.yz);
    float  achrom_w   = 1.0 - smoothstep(0.0, 0.05, lab_t_C);
    float  c_gate     = saturate(1.0 - lab_t_C / 0.10);
    float  r66_w      = r65_sw * achrom_w * c_gate * (1.0 - scene_cut) * 0.20;
    r66_w *= smoothstep(0.0, 0.15, lab_t.x);
    lab_t.y = lerp(lab_t.y, lab_amb.y, r66_w);
    lab_t.z = lerp(lab_t.z, lab_amb.z, r66_w);
    return lab_t;
}

float AdaptiveStep(float previous, float current, float scene_cut)
{
    float rising = step(previous, current);
    // Equivalent to the previous 0.06/0.30 coefficients at 60 Hz, independent
    // of refresh rate. Scene cuts reset to the new measured target.
    float half_life_ms = lerp(186.7, 32.4, rising);
    float alpha = 1.0 - exp2(-max(GRADE_FRAME_TIME, 0.0) / half_life_ms);
    return lerp(alpha, 1.0, saturate(scene_cut));
}

// ─── ColorTransformPS stage structs and helpers ────────────────────────────

struct SceneCtx {
    float4 perc;
    float  zone_log_key, zone_std, zone_str;
    float  ss_08_25, ss_04_25;
    float  scene_cut;
    float  slow_key;
    float  fc_knee;
    float  fc_knee_toe;
    float  film_curve_strength;
    float  shadow_lift_str;
    float  shadow_floor;
    float  adaptation_gate;
    float  print_stock_strength;
    float  gamut_strength;
    float  chroma_scene_scale;
    float  chroma_str_base;
    float  scene_mode;
    float  specular_contrast;
    float  illum_warm;   // CAT16 L/M − S/M + 0.5; D65≈0.39, warm>0.39, cool<0.39
    float  median_C;     // scene median Oklab C (highway HWY_MEDIAN_C) [0, 0.30]
    float  key_L;        // cbrt(slow_key), clamped [0.30,0.80] — Oklab L pivot for zone gates
};

struct TonalOut { float3 lin; float new_luma; float local_var; };

SceneCtx BuildSceneCtx()
{
    SceneCtx ctx;
    // Illuminant normalization — CAT16 pixel correction removed (R127): game content is
    // display-referred (sRGB→D65); warm lighting is art direction, not a calibration error.
    float3 illum_rgb  = tex2Dlod(NeutralIllumSamp, float4(0.5, 0.5, 0, 0)).rgb;
    ctx.illum_warm    = IllumWarm(illum_rgb);
    ctx.median_C           = clamp(ReadHWY(HWY_MEDIAN_C), 0.0, 0.30);
    ctx.perc               = ReadTexHwyPerc();
    ctx.scene_cut          = ReadHWY(HWY_SCENE_CUT);
    ctx.shadow_floor       = ReadHWY(HWY_P10);
    // Scene cuts temporarily suppress adaptive look changes, allowing the new
    // scene to settle before temporal statistics drive the grade.
    ctx.adaptation_gate    = 1.0 - smoothstep(0.05, 0.75, ctx.scene_cut);
    float4 zstats          = ReadTexHwyChroma(0, 6);
    ctx.zone_log_key       = zstats.r;
    ctx.zone_std           = zstats.g;
    ctx.ss_08_25           = smoothstep(0.06, 0.16, ctx.zone_std);
    ctx.ss_04_25           = smoothstep(0.03, 0.16, ctx.zone_std);
    float lum_att          = smoothstep(0.10, 0.40, ctx.zone_log_key);
    // CONTRAST scale: 1.0 = calibrated default, 0 = off, 2.0 = aggressive.
    ctx.zone_str           = lerp(0.26, 0.16, ctx.ss_08_25)
                           * lerp(1.10, 0.93, lum_att) * (CONTRAST * 1.00);
    // R195: H_norm attenuation — high-entropy scenes already have rich tonal gradation;
    // attenuating zone stretch avoids processing well-distributed material.
    // Gate at 0.55: fires only above typical "good" scene entropy. Max 25% attenuation.
    float scene_entropy    = ReadHWY(HWY_H_NORM);
    ctx.zone_str          *= lerp(1.0, 0.75, saturate((scene_entropy - 0.55) / 0.30));
    ctx.fc_knee            = lerp(0.75, 0.60, saturate((ctx.perc.b - 0.60) / 0.30));
    // R147: Bowley skewness — right-skewed (dark dominant, bright tail) → lower knee
    // to catch sparse bright tail that p75-based formula misses when p75 is low.
    float  bowley          = (ctx.perc.b + ctx.perc.r - 2.0 * ctx.perc.g)
                           / max(ctx.perc.b - ctx.perc.r, 0.01);
    ctx.fc_knee            = saturate(ctx.fc_knee - saturate(bowley) * 0.06);
    ctx.fc_knee_toe        = lerp(0.15, 0.25, saturate((0.40 - ctx.perc.r) / 0.30));
    // R147: mode anchor — when toe sits well above peak dark density, pull it down.
    ctx.scene_mode         = ReadHWY(HWY_MODE);
    float toe_gap          = saturate((ctx.fc_knee_toe - ctx.scene_mode - 0.05) / 0.10);
    ctx.fc_knee_toe        = lerp(ctx.fc_knee_toe, ctx.scene_mode + 0.05, toe_gap * 0.4);
    // Adaptive film-curve strength: preserve a wide, sparse highlight tail, but
    // back off when the frame has little highlight separation or tonal variety.
    float highlight_tail = saturate((ReadHWY(HWY_P90) - ctx.perc.b) / 0.25);
    float highlight_presence = smoothstep(0.45, 0.85, ReadHWY(HWY_P90));
    float entropy_gate = smoothstep(0.30, 0.70, ReadHWY(HWY_H_NORM));
    float film_auto = lerp(0.65, 1.0, highlight_tail * highlight_presence);
    film_auto *= lerp(0.80, 1.0, entropy_gate);
    ctx.film_curve_strength = saturate(float(FILM_CURVE)) * film_auto;
    float _sls_t              = saturate(((ctx.perc.r + ctx.scene_mode) * 0.5 - 0.025) / 0.175);
    float _std_suppress       = smoothstep(0.05, 0.13, ctx.zone_std);
    ctx.shadow_lift_str       = lerp(1.50, 0.45, _sls_t*_sls_t*_sls_t*(_sls_t*(_sls_t*6.0-15.0)+10.0))
                              * (1.0 - _std_suppress);
    // p10 gate: lift shadows when the floor is genuinely dark; avoid milky blacks
    // when the scene already contains substantial low-end signal.
    float shadow_floor_gate = 1.0 - smoothstep(0.04, 0.22, ctx.shadow_floor);
    ctx.shadow_lift_str *= lerp(0.65, 1.0, shadow_floor_gate);
    // R162: specular contrast — p90−p50 gap measures isolated bright sources vs scene median.
    ctx.specular_contrast     = saturate((ReadHWY(HWY_P90) - ctx.perc.g) / 0.40);
    ctx.slow_key           = max(ReadTexHwyChroma(0, 7).r, 0.001);
    ctx.key_L              = clamp(exp2(log2(ctx.slow_key) * (1.0 / 3.0)), 0.30, 0.80);
    float chromatic_scene = smoothstep(0.20, 0.75, 1.0 - ReadHWY(HWY_ACHROM_FRAC));
    float vivid_scene     = smoothstep(0.04, 0.16, ctx.median_C);
    float chroma_conf     = chromatic_scene * vivid_scene;
    ctx.chroma_scene_scale = lerp(1.0, 0.92, chroma_conf * ctx.adaptation_gate);
    ctx.gamut_strength     = lerp(0.75, 1.0, chroma_conf);
    // Print emulation is softened in dark, flat, low-chroma, or already-wide scenes.
    // PRINT_STOCK remains the manual ceiling for the automated result.
    float print_key_gate   = smoothstep(0.08, 0.35, ctx.zone_log_key);
    float print_iqr_gate   = 1.0 - smoothstep(0.50, 0.80, ctx.perc.b - ctx.perc.r);
    float print_chroma_gate = lerp(0.85, 1.0, smoothstep(0.03, 0.14, ctx.median_C));
    float print_auto        = 0.70 + 0.30 * print_key_gate * print_iqr_gate * print_chroma_gate;
    ctx.print_stock_strength = saturate(float(PRINT_STOCK)) * print_auto;
    // R176: median_C-driven chroma lift — low-chroma scenes get +25% boost, vivid scenes
    // back off 15%. Orthogonal to zone_log_key (luma). Zero new highway reads.
    float chroma_adapt     = lerp(1.25, 0.85, smoothstep(0.04, 0.18, ctx.median_C));
    ctx.chroma_str_base    = VIBRANCE * 0.40 * chroma_adapt;

    float4 adaptive_prev = tex2Dlod(AdaptiveHistorySamp, float4(0.5, 0.5, 0, 0));
    float4 adaptive_raw  = float4(ctx.film_curve_strength,
                                  ctx.shadow_lift_str,
                                  ctx.print_stock_strength,
                                  ctx.gamut_strength);
    float  seeded        = step(0.001, adaptive_prev.r + adaptive_prev.g
                                      + adaptive_prev.b + adaptive_prev.a);
    float4 adaptive_next = float4(
        lerp(adaptive_prev.r, adaptive_raw.r,
             AdaptiveStep(adaptive_prev.r, adaptive_raw.r, ctx.scene_cut)),
        lerp(adaptive_prev.g, adaptive_raw.g,
             AdaptiveStep(adaptive_prev.g, adaptive_raw.g, ctx.scene_cut)),
        lerp(adaptive_prev.b, adaptive_raw.b,
             AdaptiveStep(adaptive_prev.b, adaptive_raw.b, ctx.scene_cut)),
        lerp(adaptive_prev.a, adaptive_raw.a,
             AdaptiveStep(adaptive_prev.a, adaptive_raw.a, ctx.scene_cut)));
    ctx.film_curve_strength = lerp(adaptive_raw.r, adaptive_next.r, seeded);
    ctx.shadow_lift_str     = lerp(adaptive_raw.g, adaptive_next.g, seeded);
    ctx.print_stock_strength = lerp(adaptive_raw.b, adaptive_next.b, seeded);
    ctx.gamut_strength       = lerp(adaptive_raw.a, adaptive_next.a, seeded);
    return ctx;
}

float3 ApplyCorrective(float3 lin, float col_luma, float2 uv, float4 lf_mip2_tex, SceneCtx ctx)
{
    float  E     = exp2(EXPOSURE);
    float3 lin_e = max(lin, 0.0);

    // R194: ACES luma inverse — undoes ACES midtone boost below the fixed point (L≈0.728).
    // Bell weight (Mertens et al. 2007): exp(-0.5*((L-mu)/0.18)²). mu tuning range: 0.05–0.20.
    // Lower mu → correction peaks in near-black zone, glow penumbra untouched (diffusion reach preserved).
    // Higher mu → more correction in smoke/fog zone. Above 0.35 causes blob expansion.
    // Proportional Oklab (L,a,b) scaling: C/L ratio unchanged, no artificial density.
    if (INVERSE_LUMA > 0.0) {
        const float Aa = 2.51, Bb = 0.03, Cc = 2.43, Dd = 0.59, Ee = 0.14;
        float  disc  = ((Dd*Dd - 4.0*Cc*Ee)*col_luma + 4.0*Aa*Ee - 2.0*Bb*Dd)*col_luma + Bb*Bb;
        float  L_sc  = 0.5*(Dd*col_luma - Bb + sqrt(max(disc, 0.0))) / max(Aa - Cc*col_luma, 1e-4);
        float  delta = min(L_sc / max(col_luma, 1e-5) - 1.0, 0.0);
        float  t     = (col_luma - 0.05) / 0.18;
        float  bell  = exp(-0.5 * t * t);
        float3 ok    = RGBtoOklabLinear(lin_e);
        ok          *= 1.0 + delta * float(INVERSE_LUMA) * bell;
        lin_e        = OklabToRGB(ok);
    }
    lin_e *= E;
    // R104: DIR couplers — developer-inhibitor-release cross-channel masking (hardcoded 0.30)
    {
        float3 act   = lin_e * lin_e / (lin_e * lin_e + 0.09);
        float3 cpl   = float3(act.g * 0.12 + act.b * 0.06,
                              act.r * 0.10 + act.b * 0.04,
                              act.r * 0.06 + act.g * 0.08);
        lin_e *= lerp(1.0, exp2(-cpl * 0.3), 0.30);
    }
    // ── R19: 3-way CC — primary grade before print emulation ──────────────────
    lin_e = Apply3WayCC(lin_e,
                          SHADOW_TEMP, SHADOW_TINT,
                          MID_TEMP, MID_TINT,
                          HIGHLIGHT_TEMP, HIGHLIGHT_TINT,
                          ctx.key_L);
    return lin_e;
}

float HueBandWeightW(float hue, float center)
{
    hue = frac(hue);
    float d = abs(hue - center);
    d = min(d, 1.0 - d);
    float t = saturate(1.0 - d / 0.14);
    return t * t * (3.0 - 2.0 * t);
}

TonalOut ApplyTonal(float3 lin, float col_luma, float2 uv, float4 lf_mip2_tex, SceneCtx ctx)
{
    float luma        = Luma(lin);
    float luma_orig   = luma;   // zone S-curve classifies from original scene position
    // R190 guided-filter detail signal, used only by hue-selective luma contrast.
    {
        float log_base   = tex2D(BilateralLogSamp, uv).r;  // log2-luma base layer (1/8-res)
        float log_lf1    = log2(max(Luma(tex2D(LowFreqMip1Samp, uv).rgb), 1e-3));  // 1/16-res
        float log_pixel  = log2(max(luma, 1e-3));
        float log_detail = log_pixel - log_base;
        // Large-scale gradient suppression: preserve fine texture, suppress broad sky/cloud transitions.
        float coarse_grad = max(0.0, log_base - log_lf1);
        float coarse_sup     = 1.0 - saturate(coarse_grad / 0.10);
        float ungated_detail = log_detail * coarse_sup;
        float3 lab_lc        = RGBtoOklabLinear(lin);
        float h_lc           = frac(atan2(lab_lc.z, lab_lc.y) / 6.28318530718);
        float C_lc           = length(lab_lc.yz);
        float chroma_gate    = smoothstep(0.04, 0.10, C_lc);
        float lc_delta       = (LUMA_CONTRAST_RED    * HueBandWeightW(h_lc, HB_BAND_RED)
                             + LUMA_CONTRAST_YELLOW * HueBandWeightW(h_lc, HB_BAND_YELLOW)
                             + LUMA_CONTRAST_GREEN  * HueBandWeightW(h_lc, HB_BAND_GREEN)
                             + LUMA_CONTRAST_CYAN   * HueBandWeightW(h_lc, HB_BAND_CYAN)
                             + LUMA_CONTRAST_BLUE   * HueBandWeightW(h_lc, HB_BAND_BLUE)
                             + LUMA_CONTRAST_MAG    * HueBandWeightW(h_lc, HB_BAND_MAGENTA)) * chroma_gate;
        float bil_ratio      = exp2(lc_delta * ungated_detail * 0.025);
        bil_ratio        = clamp(bil_ratio, 0.5, 2.0);
        lin             *= bil_ratio;
        luma             = Luma(lin);
    }
    float reconstruction_luma = luma;
    // R29: Multi-Scale Retinex — spatial illuminant normalisation fires before zone S-curve
    // so the S-curve shapes the spatially-equalised signal, not the raw uneven one.
    float illum_s0  = max(tex2D(LowFreqMip1Samp, uv).a, 0.001);
    float illum_s2  = max(lf_mip2_tex.a, 0.001);
    float local_var = abs(illum_s0 - illum_s2);
    float nl_safe   = max(luma, 0.001);
    float log_R     = log2(nl_safe / illum_s0);
    float zk_safe   = max(ctx.zone_log_key, 0.001);
    // Retinex uses a bounded log-domain correction. The old raw ratio could
    // overreact when the blurred illuminant approached zero or diverged from
    // the global zone key.
    float illum_delta = clamp(log2(zk_safe) - log2(max(illum_s0, 0.001)), -0.35, 0.35);
    float illum_gain  = exp2(illum_delta);
    // Coarse-scale disagreement reduces confidence in local zone contrast.
    float edge_protect = 1.0 - smoothstep(0.04, 0.16,
                                          abs(log2(max(illum_s0, 0.001))
                                            - log2(max(illum_s2, 0.001))));
    // Global/local confidence budget: local operators are trusted in stable,
    // textured regions and blended back toward the global path near broad
    // illumination edges or while scene statistics are settling.
    float local_confidence = edge_protect * lerp(0.75, 1.0, ctx.ss_04_25)
                           * ctx.adaptation_gate;
    float highlight_protect = 1.0 - smoothstep(0.55, 0.85, luma);
    // Fading Retinex strength at coarse edges outlines otherwise uniform fields.
    // Keep its bounded gain and global confidence consistent across those edges.
    float retinex_strength  = 0.75 * ctx.ss_04_25 * highlight_protect
                            * lerp(0.75, 1.0, ctx.ss_04_25) * ctx.adaptation_gate
                            * saturate(float(RETINEX_STRENGTH));
    luma = lerp(luma, max(luma * illum_gain, 0.0), retinex_strength);

    float4 zone_lvl   = tex2Dlod(ZoneHistorySamp, float4(uv, 0, 0));
    float zone_median = zone_lvl.r;
    float zone_iqr    = zone_lvl.b - zone_lvl.g;
    // R33: CLAHE-inspired clip limit — bounds S-curve slope; tightens when Retinex is engaged
    float clahe_slope = 1.0 + (lerp(1.32, 1.12, ctx.ss_04_25) - 1.0)
                            * max(float(CONTRAST), 0.0);
    float iqr_scale   = min(smoothstep(0.0, 0.25, zone_iqr),
                            (clahe_slope - 1.0) / max(ctx.zone_str, 0.001));
    float delta    = luma_orig - zone_median;   // original position — DEHAZE lift does not inflate delta
    // Signed zone contrast: expand around the local median instead of lifting
    // only the upper side, which flattened bright cloud texture into white.
    float zone_highlight_protect = 1.0 - smoothstep(0.55, 0.85, luma_orig);
    float below_pivot = 1.0 - smoothstep(-0.02, 0.02, delta);
    float shadow_arm  = lerp(1.0, 0.75, below_pivot);
    float zone_adj = ctx.zone_str * iqr_scale * delta * (1.0 - abs(delta))
                   * zone_highlight_protect * shadow_arm
                   * lerp(0.65, 1.0, local_confidence)
                   * saturate(float(ZONE_CONTRAST_STRENGTH));
    // A subtractive shadow arm can flatten positive inputs against zero.
    // Bound its loss relative to available luma, retaining a smooth toe and
    // the positive arm while preserving exact black and a zero-strength bypass.
    float shadow_loss = max(-zone_adj, 0.0);
    float new_luma = luma / (1.0 + shadow_loss / max(luma, 1e-10))
                   + max(zone_adj, 0.0);

    float detail_protect  = smoothstep(-4.0, -0.5, log_R);
    // R60: temporal context — slow ambient key boosts lift during dark transitions, suppresses on re-entry
    float context_lift   = exp2(log2(ctx.slow_key / zk_safe) * 0.4);
    // R162: suppress shadow lift when isolated bright sources dominate (high specular contrast).
    // High p90−p50 gap = sun/lamp in frame — lifting shadows flattens depth against the source.
    float specular_att   = 1.0 - smoothstep(0.50, 0.90, ctx.specular_contrast) * 0.35;
    float shadow_lift    = ctx.shadow_lift_str * detail_protect * context_lift * specular_att;
    float shadow_base_luma = luma;
    float lift_w         = shadow_base_luma * smoothstep(0.35, 0.0, shadow_base_luma);
    new_luma = max(new_luma + shadow_lift * 0.25 * lift_w * SHADOWS
                        * saturate(float(SHADOW_LIFT_STRENGTH)), 0.0);
    // R62 Finding 3: chroma-stable tonal — apply luma ratio in Oklab L to prevent zone S-curve from shifting chroma
    float3 lab_t  = RGBtoOklabLinear(lin);
    float r_tonal = max(1.0 + (new_luma - reconstruction_luma)
                              / max(reconstruction_luma, 1e-10), 0.0);
    float log_r   = log2(max(r_tonal, 1e-10));
    float cbrt_r  = exp2(log_r * (1.0 / 3.0));
    lab_t.x = max(lab_t.x * cbrt_r, 0.0);
    // R65: CAM16 Hunt exponent 0.25 — colorfulness ∝ L^0.25 (Hunt 2004, CIECAM02 eq.14-16)
    float r65_scale = exp2(log_r * 0.25);
    float r65_sw    = smoothstep(0.25, 0.0, lab_t.x);
    lab_t.y = lab_t.y * lerp(1.0, r65_scale, r65_sw);
    lab_t.z = lab_t.z * lerp(1.0, r65_scale, r65_sw);
    // R66: ambient shadow tint — inject scene-ambient hue into achromatic lifted shadows.
    lab_t = ApplyAmbientTint(lab_t, lf_mip2_tex.rgb, r65_sw, ctx.scene_cut);

    TonalOut result;
    result.lin       = OklabToRGB(lab_t);
    result.new_luma  = new_luma;
    result.local_var = local_var;
    return result;
}

float3 ApplyChroma(float3 lin, float new_luma, float local_var,
                   float4 lf_mip2_tex, SceneCtx ctx)
{
    float3 lab    = RGBtoOklabLinear(lin);
    float  C      = length(lab.yz);
    float  C_input = C;
    float  h      = OklabHueNorm(lab.y, lab.z);
    float  h_perc = h;


    // R22: saturation by luminance — shadow desaturation 20% (baked Munsell calibration)
    // + midtone expansion bell from cinema SDR mastering data (Žaganeli et al. 2026)
    float mid_C_boost = 0.08 * ctx.chroma_scene_scale * smoothstep(0.22, 0.40, lab.x)
                             * (1.0 - smoothstep(0.55, 0.70, lab.x));
    C *= (1.0 + mid_C_boost
             - 0.20 * saturate(1.0 - lab.x / 0.25));
    // This is the input chroma after the intentional luminance-dependent
    // adjustment. The soft cusp below must not erase color that was already
    // present; final OklabToSDR handles actual display-gamut limits.
    float C_floor = C;
    // R21: per-band hue rotation — wider band (0.14 vs HB_BAND_WIDTH 0.08) covers full wheel
    // with 6 knobs. Calibrated bands use 0.08; creative rotation needs ±50° to avoid dead zones
    // in azure (CYAN↔BLUE gap) and orange/violet (RED↔YELLOW, BLUE↔MAG gaps).
    float r21_delta = HUE_RED    * HueBandWeightW(h_perc, HB_BAND_RED)
                    + HUE_YELLOW * HueBandWeightW(h_perc, HB_BAND_YELLOW)
                    + HUE_GREEN  * HueBandWeightW(h_perc, HB_BAND_GREEN)
                    + HUE_CYAN   * HueBandWeightW(h_perc, HB_BAND_CYAN)
                    + HUE_BLUE   * HueBandWeightW(h_perc, HB_BAND_BLUE)
                    + HUE_MAG    * HueBandWeightW(h_perc, HB_BAND_MAGENTA);
    float h_out  = frac(h_perc + r21_delta * 0.10);
    float hw_o0  = HueBandWeightW(h_out, HB_BAND_RED);
    float hw_o1  = HueBandWeightW(h_out, HB_BAND_YELLOW);
    float hw_o2  = HueBandWeightW(h_out, HB_BAND_GREEN);
    float hw_o3  = HueBandWeightW(h_out, HB_BAND_CYAN);
    float hw_o4  = HueBandWeightW(h_out, HB_BAND_BLUE);
    float hw_o5  = HueBandWeightW(h_out, HB_BAND_MAGENTA);

    float chroma_str = ctx.chroma_str_base;
    chroma_str *= lerp(1.0, 0.65, smoothstep(0.02, 0.08, local_var));  // R68A: attenuate in textured regions
    // Vibrance pivot: 50% of per-hue gamut ceiling — bypasses Kalman cold-start issue.
    // Pixels below 50% saturation get lifted; above 50% are progressively protected.
    float lifted_C = LiftChroma(C, HueCeil(h_out) * 0.5, chroma_str);
    // R117D: memory color chroma attraction — gentle boost in canonical luminance range.
    // Complements R73 ceilings: where ceilings prevent over-saturation, this nudges up
    // under-saturation in canonical hue+luminance zones. C gate: achromatic pixels are excluded.
    // Ceiling below still bounds the total — attraction cannot exceed the R73 limit.
    {
        float mem_sky = saturate(hw_o3 * 0.6 + hw_o4 * 0.4) * smoothstep(0.42, 0.65, lab.x);
        float mem_fol = hw_o2 * smoothstep(0.35, 0.58, lab.x) * (1.0 - smoothstep(0.62, 0.75, lab.x));
        float mem_skn = saturate(hw_o0 * 0.5 + hw_o1 * 0.5) * smoothstep(0.30, 0.52, lab.x);
        lifted_C += (0.008 * mem_sky + 0.006 * mem_fol + 0.006 * mem_skn)
                  * C * ctx.chroma_scene_scale;
    }
    // R73: memory color protection — per-band chroma ceiling (sky/foliage/skin).
    // R81B/R118: full 12-hue wheel. Ceilings defined in hue_bands.fxh (shared with
    // inverse_grade.fx). Ceiling applied before vibrance — R116.
    float C_ceil      = HueCeil(h_out);
    float lifted_C_c  = min(lifted_C, max(C_ceil, C));
    // R71: vibrance — attenuate lift delta on already-saturated pixels.
    float vib_mask = saturate(1.0 - C / max(C_ceil, 0.001));
    float vib_C    = C + max(lifted_C_c - C, 0.0) * vib_mask;
    float final_C  = vib_C;

    // Per-band saturation — ±1.0 → ±80% chroma scale per hue band.
    float sat_delta = SAT_RED    * HueBandWeightW(h_perc, HB_BAND_RED)
                    + SAT_YELLOW * HueBandWeightW(h_perc, HB_BAND_YELLOW)
                    + SAT_GREEN  * HueBandWeightW(h_perc, HB_BAND_GREEN)
                    + SAT_CYAN   * HueBandWeightW(h_perc, HB_BAND_CYAN)
                    + SAT_BLUE   * HueBandWeightW(h_perc, HB_BAND_BLUE)
                    + SAT_MAG    * HueBandWeightW(h_perc, HB_BAND_MAGENTA);
    float saturation_gain = max(0.0, 1.0 + float(SATURATION));
    final_C = max(0.0, final_C * saturation_gain * (1.0 + sat_delta * 0.80));
    C_floor = max(0.0, C_floor * saturation_gain * (1.0 + sat_delta * 0.80));
    // Protect already-vivid pixels by reducing only adaptive chroma added above;
    // natural scene chroma and shadow desaturation remain unchanged.
    float vivid_pixel = smoothstep(0.08, 0.20, C);
    float chroma_guard = (1.0 - ctx.chroma_scene_scale) * vivid_pixel;
    final_C -= max(final_C - C, 0.0) * chroma_guard;
    // R196-E: cusp-relative chroma compression — ACES2 principle, Oklab/HueCeil basis.
    // d_norm = C / HueCeil(hue). Reinhard on excess above 0.85 maps [0.85,∞) → [0.85,1.0).
    // Equal proportional headroom per hue — deep reds and cyans no longer compressed earlier
    // than other hues just because their cusp sits closer to where saturated colours live.
    {
        float d_norm = final_C / max(C_ceil, 0.001);
        float d_over = max(0.0, d_norm - 0.85);
        float cusp_C = (0.85 + d_over / (1.0 + d_over / 0.15)) * C_ceil;
        final_C = max(C_floor, min(final_C, cusp_C));
    }

    // Vector-space (a,b) reconstruction — rotate original direction by R21 delta
    float r21_cos, r21_sin;
    sincos(r21_delta * (0.10 * 6.28318), r21_sin, r21_cos);
    float2 ab_in  = float2(lab.y * r21_cos - lab.z * r21_sin,
                           lab.y * r21_sin + lab.z * r21_cos);
    float  C_safe = max(C_input, 1e-6);
    float2 ab_s   = ab_in * (final_C / C_safe);

    float dtheta = +(GREEN_HUE_COOL * 2.0 * 3.14159265) * hw_o2 * final_C;
    float cos_dt = 1.0 - dtheta * dtheta * 0.5;
    float sin_dt = dtheta;
    float f_oka  = ab_s.x * cos_dt - ab_s.y * sin_dt;
    float f_okb  = ab_s.x * sin_dt + ab_s.y * cos_dt;

    float final_L = lab.x;
    // Gamut headroom is used only for chroma compression and projection.
    float3 rgb_probe  = OklabToRGB(float3(final_L, f_oka, f_okb));
    float  headroom   = saturate(1.0 - max(rgb_probe.r, max(rgb_probe.g, rgb_probe.b)));
    // R68B: gamut pre-knee — Reinhard soft chroma rolloff in last 12% of headroom.
    float ck_near = max(0.0, 0.12 - headroom) / 0.12;
    float ck_fac  = 1.0 - ctx.gamut_strength * 0.18 * ck_near / (1.0 + ck_near);
    float ck_C    = max(C_floor, final_C * ck_fac);
    float ck_scale = ck_C / max(final_C, 1e-6);
    f_oka *= ck_scale;
    f_okb *= ck_scale;
    // The blended chroma result is projected once at the SDR boundary below.
    return OklabToRGB(float3(final_L, f_oka, f_okb));
}

// ─── Look Modification Transform — post-grade print emulation ──────────────

float3 ApplyLook(float3 lin, SceneCtx ctx)
{
    float3 out_lin = lin;
    // ── R51: print stock + R110: masking coupler + R130: dye matrix ──
    // Fires after all tonal and chroma work — LMT position per ACES convention.
    out_lin = ApplyPrintStock(out_lin, ctx.fc_knee_toe, ctx.fc_knee, ctx.print_stock_strength);
    out_lin = ApplyMaskingCoupler(out_lin, ctx.print_stock_strength);
    out_lin = ApplyDyeMatrix(out_lin, ctx.print_stock_strength);
    // R192: printer lights — per-channel contact-printer exposure after all emulsion work.
    // 0 = neutral, ±12 = ±1 stop. Mirrors film lab RGB printer head notation.
    out_lin *= exp2(float3(PRINTER_R, PRINTER_G, PRINTER_B) / 12.0);
    return saturate(out_lin);
}

// ─── ColorTransform pixel shader ───────────────────────────────────────────

float4 ColorTransformPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col      = tex2D(BackBuffer, uv);
    col.rgb = SRGBToLinear(col.rgb);
    SceneCtx ctx       = BuildSceneCtx();
    float4 lf_mip2_tex = tex2D(LowFreqMip2Samp, uv);

    float3 lin      = col.rgb * (float(WHITES) - float(BLACKS)) + float(BLACKS);
    float  col_luma = Luma(lin);
    lin = lerp(lin, ApplyCorrective(lin, col_luma, uv, lf_mip2_tex, ctx), CORRECTIVE_STRENGTH * 0.01);

    TonalOut tonal      = ApplyTonal(lin, col_luma, uv, lf_mip2_tex, ctx);
    float    tonal_gate = TONAL_STRENGTH * 0.01;
    tonal.lin       = lerp(lin,       tonal.lin,       tonal_gate);
    tonal.new_luma  = lerp(Luma(lin), tonal.new_luma,  tonal_gate);
    tonal.local_var = tonal.local_var * tonal_gate;

    // Apply the film shoulder after spatial tonal work so cloud texture is not
    // compressed before Retinex and zone shaping have processed the signal.
    float3 fc_out = FilmCurveApply(tonal.lin, ctx.fc_knee);
    tonal.lin = lerp(tonal.lin, fc_out, ctx.film_curve_strength);
    tonal.new_luma = lerp(tonal.new_luma, Luma(tonal.lin), ctx.film_curve_strength);

    float3 result  = lerp(tonal.lin, ApplyChroma(tonal.lin, tonal.new_luma, tonal.local_var, lf_mip2_tex, ctx), CHROMA_STRENGTH * 0.01);
    // Bound the blended signal even when the chroma stage is bypassed.
    result = OklabToSDR(RGBtoOklabLinear(result));
    result = lerp(result, ApplyLook(result, ctx), LOOK_STRENGTH * 0.01);

    // dither: break 8-bit BackBuffer quantization — converts banding to imperceptible noise
    // R89: IGN blue-noise dither (Jimenez 2016) — pushes quantization error to high freq
    float dither = frac(52.9829189 * frac(dot(pos.xy, float2(0.06711056, 0.00583715)))) - 0.5;
    result = DitherSDR(result, dither);

    // 2x2 red activity indicator: visual filter-on confirmation in top-left corner.
    result = lerp(result, float3(1.0, 0.0, 0.0), step(pos.x, 1.5) * step(pos.y, 1.5));

    return float4(LinearToSRGB(result), col.a);
}

// ─── LF downscale passes — build mip1 and mip2 within this technique ──────────────

float4 LFDownscale1PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // 2× box filter from TexHwyTex spatial lane → LowFreqMip1Tex (1/16-res).
    // V scaled to stay inside spatial lane; half-texel offset = 0.5/TEX_HWY_TOTAL_H in V.
    float sy = uv.y * float(TEX_HWY_SPATIAL_H) / float(TEX_HWY_TOTAL_H);
    float sx = uv.x;
    float ox = 4.0 / float(BUFFER_WIDTH);
    float oy = 0.5 / float(TEX_HWY_TOTAL_H);
    return (tex2D(TexHwySamp, ClampSpatialUV(float2(sx + ox, sy + oy)))
          + tex2D(TexHwySamp, ClampSpatialUV(float2(sx - ox, sy + oy)))
          + tex2D(TexHwySamp, ClampSpatialUV(float2(sx + ox, sy - oy)))
          + tex2D(TexHwySamp, ClampSpatialUV(float2(sx - ox, sy - oy)))) * 0.25;
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
// R190 guided filter — Pass 1: compute local linear model coefficients (a_k, b_k).
// Self-guided in log2-luma space. Adaptive ε (Hu 2023): a_k = var/((1+ε)·var + η).
// Reads TexHwySamp spatial lane (1/8-res RGBA16F). Writes GuidedCoeffTex (RG16F).
float2 GuidedCoeffPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // GuidedCoeffTex is BUFFER_WIDTH/8 × BUFFER_HEIGHT/8; uv∈[0,1] maps full spatial lane.
    float px  = 8.0 / float(BUFFER_WIDTH);
    float py  = 1.0 / float(TEX_HWY_TOTAL_H);   // one spatial-lane texel in TexHwyTex V
    float sy  = uv.y * float(TEX_HWY_SPATIAL_H) / float(TEX_HWY_TOTAL_H);
    float sum_I = 0.0, sum_II = 0.0;
    [unroll] for (int dy = -GF_R; dy <= GF_R; dy++)
    [unroll] for (int dx = -GF_R; dx <= GF_R; dx++)
    {
        float I = log2(max(Luma(tex2D(TexHwySamp, ClampSpatialUV(float2(uv.x + dx * px, sy + dy * py))).rgb), 1e-3));
        sum_I  += I;
        sum_II += I * I;
    }
    float mean_I  = sum_I  / GF_N;
    float mean_II = sum_II / GF_N;
    float var_I   = max(mean_II - mean_I * mean_I, 0.0);
    float eps_k   = lerp(GF_EPS_MAX, GF_EPS_MIN, smoothstep(0.0025, 0.0400, var_I));
    float a_k     = var_I / ((1.0 + eps_k) * var_I + GF_ETA);
    float b_k     = (1.0 - a_k) * mean_I;
    return float2(a_k, b_k);
}

// R190 guided filter — Pass 2: average coefficients over window, reconstruct base layer.
// Reads GuidedCoeffSamp (RG16F) + center pixel from TexHwySamp.
// Writes BilateralLogTex (R16F) — log2-luma base layer read by ApplyTonal.
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
    float I_c    = log2(max(Luma(tex2D(TexHwySamp, float2(uv.x, uv.y * float(TEX_HWY_SPATIAL_H) / float(TEX_HWY_TOTAL_H))).rgb), 1e-3));
    return mean_a * I_c + mean_b;
}

// ─── R124B: Neutral-pixel-weighted illuminant estimation ───────────────────
// Samples TexHwySamp spatial lane at 16×9 grid (144 points). Near-grey pixels
// (Oklab C < 0.10) carry illuminant color reliably; saturated pixels are noise.
// Falls back to grey world when fewer than ~8/144 samples are neutral.
float4 NeutralIllumPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 neutral_acc = 0.0;
    float3 grey_acc    = 0.0;
    float  total_w     = 0.0;

    float scale_y = float(TEX_HWY_SPATIAL_H) / float(TEX_HWY_TOTAL_H);
    [unroll] for (int iy = 0; iy < 9; iy++)
    [unroll] for (int ix = 0; ix < 16; ix++)
    {
        float2 suv = float2((ix + 0.5) / 16.0, (iy + 0.5) / 9.0 * scale_y);
        float3 rgb = tex2Dlod(TexHwySamp, float4(suv, 0, 0)).rgb;
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

// ─── TexHwy write — NeutralIllum → data row 0 pixel 4 ──────────────────────
// NeutralIllumTex is written by NeutralIllumPS (current frame) and read by ColorTransformPS
// (current frame via NeutralIllumSamp). Here we also publish it into TexHwyTex so that
// inverse_grade.fx can read it on the NEXT frame (ReadTexHwyIlluminant = one-frame delay).

float4 TexHwyWritePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    int row = int(pos.y);
    int col = int(pos.x);
    if (row >= TEX_HWY_SPATIAL_H && (row - TEX_HWY_SPATIAL_H) == 0 && col == 4)
        return tex2Dlod(NeutralIllumSamp, float4(0.5, 0.5, 0, 0));
    return tex2Dlod(TexHwySamp, float4(uv, 0, 0));
}

float4 AdaptiveHistoryPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    SceneCtx ctx = BuildSceneCtx();
    return float4(ctx.film_curve_strength, ctx.shadow_lift_str,
                  ctx.print_stock_strength, ctx.gamut_strength);
}

// ─── Technique ─────────────────────────────────────────────────────────────

#ifndef SHADER_PIPELINE_COMBINED
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
        SRGBWriteEnable = false;
    }
    pass AdaptiveHistory
    {
        VertexShader = PostProcessVS;
        PixelShader  = AdaptiveHistoryPS;
        RenderTarget = AdaptiveHistoryTex;
    }
    pass TexHwyWrite
    {
        VertexShader = PostProcessVS;
        PixelShader  = TexHwyWritePS;
        RenderTarget = TexHwyTex;
    }
}
#endif
