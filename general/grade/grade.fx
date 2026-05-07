// creative_color_grade.fx — Mega-pass: all downstream color work in one full-res pass
#include "debug_text.fxh"
#include "../highway.fxh"
#include "../hue_bands.fxh"
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

// ─── Chroma lift constants ─────────────────────────────────────────────────
#define BAND_WIDTH      8       // kept for GetBandCenter only
#define MIN_WEIGHT      1.0
#define SAT_THRESHOLD   2
#define GREEN_HUE_COOL  (4.0 / 360.0)
// Band center aliases — canonical values live in hue_bands.fxh
#define BAND_RED     HB_BAND_RED
#define BAND_ORANGE  HB_BAND_ORANGE
#define BAND_AMBER   HB_BAND_AMBER
#define BAND_YELLOW  HB_BAND_YELLOW
#define BAND_GREEN   HB_BAND_GREEN
#define BAND_TEAL    HB_BAND_TEAL
#define BAND_CYAN    HB_BAND_CYAN
#define BAND_AZURE   HB_BAND_AZURE
#define BAND_BLUE    HB_BAND_BLUE
#define BAND_VIOLET  HB_BAND_VIOLET
#define BAND_MAGENTA HB_BAND_MAGENTA
#define BAND_ROSE    HB_BAND_ROSE


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
texture2D CreativeLowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; MipLevels = 3; };
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

// Pro-Mist downsample target — 1/8-res, 3 mips; mip1=1/16-res, mip2=1/32-res (vkBasalt auto-generates within-technique)
texture2D MistDiffuseTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; MipLevels = 3; };
sampler2D MistDiffuseSamp
{
    Texture   = MistDiffuseTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = LINEAR;
};



// ─── Vertex shader ─────────────────────────────────────────────────────────

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ─── Helpers ───────────────────────────────────────────────────────────────

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float3 FilmCurveApply(float3 x,
                      float knee_r, float knee_g, float knee_b,
                      float ktoe_r, float ktoe_g, float ktoe_b,
                      float factor, float toe_fac)
{
    float3 above      = max(x - float3(knee_r, knee_g, knee_b), 0.0);
    float3 below      = max(float3(ktoe_r, ktoe_g, ktoe_b) - x, 0.0);
    float3 shoulder_w = float3(0.91, 1.00, 1.06);
    float3 toe_w      = float3(0.95, 1.00, 1.04);
    return x - factor * shoulder_w * above * above
               + toe_fac * toe_w * below * below;
}

float3 RGBtoOklab(float3 rgb)
{
    float l = dot(rgb, float3(0.4122214708, 0.5363325363, 0.0514459929));
    float m = dot(rgb, float3(0.2119034982, 0.6806995451, 0.1073969566));
    float s = dot(rgb, float3(0.0883024619, 0.2817188376, 0.6299787005));
    float3 lms_cbrt = exp2(log2(max(float3(l, m, s), 1e-10)) * (1.0 / 3.0));
    l = lms_cbrt.x; m = lms_cbrt.y; s = lms_cbrt.z;
    return float3(
        dot(float3(l, m, s), float3( 0.2104542553,  0.7936177850, -0.0040720468)),
        dot(float3(l, m, s), float3( 1.9779984951, -2.4285922050,  0.4505937099)),
        dot(float3(l, m, s), float3( 0.0259040371,  0.7827717662, -0.8086757660))
    );
}

float3 OklabToRGB(float3 lab)
{
    float l = dot(lab, float3(1.0,  0.3963377774,  0.2158037573));
    float m = dot(lab, float3(1.0, -0.1055613458, -0.0638541728));
    float s = dot(lab, float3(1.0, -0.0894841775, -1.2914855480));
    l = l * l * l;
    m = m * m * m;
    s = s * s * s;
    return float3(
        dot(float3(l, m, s), float3( 4.0767416621, -3.3077115913,  0.2309699292)),
        dot(float3(l, m, s), float3(-1.2684380046,  2.6097574011, -0.3413193965)),
        dot(float3(l, m, s), float3(-0.0041960863, -0.7034186147,  1.7076147010))
    );
}

float OklabHueNorm(float a, float b)
{
    float ay = abs(b) + 1e-10;
    float r  = (a - sign(a) * ay) / (ay + abs(a));
    float th = 1.5707963 - sign(a) * 0.7853982;
    th += (0.1963 * r * r - 0.9817) * r;
    return frac(sign(b + 1e-10) * th / 6.28318 + 1.0);
}


float LiftChroma(float C, float pivot, float strength)
{
    float t = saturate(1.0 - C / max(pivot, 0.001));
    return C * (1.0 + strength * t * t);
}

float GetBandCenter(int b)
{
    if (b == 0) return BAND_RED;
    if (b == 1) return BAND_YELLOW;
    if (b == 2) return BAND_GREEN;
    if (b == 3) return BAND_CYAN;
    if (b == 4) return BAND_BLUE;
    return BAND_MAGENTA;
}


// ─── ColorTransform pixel shader ───────────────────────────────────────────

float4 ColorTransformPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col      = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;  // data highway
    float  col_luma = Luma(col.rgb);
    // R76A: CAT16 chromatic adaptation — normalise scene illuminant toward D65
    float3 lms_illum_norm;  // lifted for R83 chromatic floor
    {
        const float3x3 M_fwd = float3x3(0.302825, 0.602279, 0.070428,
                                         0.153818, 0.777214, 0.085341,
                                         0.027974, 0.147911, 0.908874);
        const float3x3 M_bwd = float3x3( 5.4459, -4.2155, -0.0242,
                                         -1.0784,  2.1456, -0.1184,
                                          0.0078, -0.2191,  1.1200);
        const float3 lms_d65 = float3(0.9756, 1.0165, 1.0849);
        float3 illum_rgb  = tex2Dlod(NeutralIllumSamp, float4(0.5, 0.5, 0, 0)).rgb;
        float3 illum_norm = illum_rgb / max(Luma(illum_rgb), 0.001);
        float3 lms_illum  = mul(M_fwd, illum_norm);
        lms_illum_norm    = lms_illum / max(lms_illum.g, 0.001);
        float3 gain      = clamp(lms_d65 / max(lms_illum, 0.001), 0.5, 2.0);
        float3 lms_px    = mul(M_fwd, col.rgb) * gain;
        float3 cat16     = mul(M_bwd, lms_px);
        cat16            = cat16 * (Luma(col.rgb) / max(Luma(cat16), 0.001));
        // R116: adaptive blend — near-neutral illuminant reliable (0.80); tinted estimate
        // may be scene-biased, stay safe (0.60). R124A: achromatic confidence gate — few
        // neutral pixels means grey world is unreliable; scale blend down proportionally.
        float illum_dev      = length(lms_illum_norm - float3(1.0, 1.0, 1.0));
        float cat_confidence = smoothstep(0.02, 0.12, ReadHWY(HWY_ACHROM_FRAC));
        float cat_blend      = lerp(0.80, 0.60, smoothstep(0.05, 0.20, illum_dev))
                             * lerp(0.65, 1.0, cat_confidence);
        col.rgb              = lerp(col.rgb, saturate(cat16), cat_blend);
    }
    // R54 + R83: camera signal floor/ceiling — chromatic pedestal from Kodak 2383 D-min + illuminant
    float3 cfilm_floor = FILM_FLOOR * (lms_illum_norm * float3(1.02, 1.00, 0.97));
    col.rgb = col.rgb * (FILM_CEILING - cfilm_floor) + cfilm_floor;

    float4 perc = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));

    // R32: zone global stats — pre-computed in UpdateHistoryPS, stored in ChromaHistoryTex col 6
    float4 zstats      = tex2Dlod(ChromaHistory, float4(6.5 / 8.0, 0.5 / 4.0, 0, 0));
    float zone_log_key = zstats.r;
    float zone_std     = zstats.g;
    float eff_p25      = perc.r;   // R116: pure global p25 — was lerp with zone zmin (incompatible statistics)
    float eff_p75      = perc.b;   // R116: pure global p75 — was lerp with zone zmax
    float ss_08_25     = smoothstep(0.06, 0.16, zone_std);  // R116: intra-zone std peaks ~0.15; old 0.25 never saturated
    float ss_04_25     = smoothstep(0.03, 0.16, zone_std);
    float spread_scale = lerp(0.7, 1.1, ss_08_25);
    float lum_att      = smoothstep(0.10, 0.40, zone_log_key);
    float zone_str     = lerp(0.26, 0.16, ss_08_25)
                       * lerp(1.10, 0.93, lum_att) * ZONE_STRENGTH;

    // ── 1. CORRECTIVE: EXPOSURE + FilmCurve ──────────────────────────────────
    // Frame-constant FilmCurve coefficients — hoisted out of per-pixel path (R62 OPT-2)
    float fc_knee     = lerp(0.90, 0.80, saturate((eff_p75 - 0.60) / 0.30));
    float fc_stevens  = ReadHWY(HWY_STEVENS) * 1.3;
    float fc_factor   = 0.05 / ((1.0 - fc_knee) * (1.0 - fc_knee)) * fc_stevens * spread_scale;
    float fc_knee_toe = lerp(0.15, 0.25, saturate((0.40 - eff_p25) / 0.30));
    // R84: CURVE_* are log-density offsets — exp2 folds to constant at compile time
    float fc_knee_r   = clamp(fc_knee     * exp2(CURVE_R_KNEE), 0.70, 0.95);
    float fc_knee_b   = clamp(fc_knee     * exp2(CURVE_B_KNEE), 0.70, 0.95);
    float fc_ktoe_r   = clamp(fc_knee_toe * exp2(CURVE_R_TOE),  0.08, 0.35);
    float fc_ktoe_b   = clamp(fc_knee_toe * exp2(CURVE_B_TOE),  0.08, 0.35);
    float fc_toe_fac  = 0.03 / (fc_knee_toe * fc_knee_toe);
    float3 lin_e = pow(max(col.rgb, 0.0), EXPOSURE);
    // R104: DIR couplers — developer-inhibitor-release cross-channel masking
    {
        float3 log_e = log2(lin_e + 1e-5);
        float3 act   = lin_e * lin_e / (lin_e * lin_e + 0.09);
        float3 cpl   = float3(act.g * 0.12 + act.b * 0.06,
                              act.r * 0.10 + act.b * 0.04,
                              act.r * 0.06 + act.g * 0.08);
        lin_e = saturate(exp2(log_e - cpl * COUPLER_STRENGTH));
    }
    float3 lin = FilmCurveApply(lin_e,
                                fc_knee_r, fc_knee, fc_knee_b,
                                fc_ktoe_r, fc_knee_toe, fc_ktoe_b,
                                fc_factor, fc_toe_fac);

    // lf_mip2 hoisted: needed by halation (before PRINT_STOCK) and reused by R66, R117C below
    float4 lf_mip2_tex = tex2D(LowFreqMip2Samp, uv);
    float  illum_s2    = max(lf_mip2_tex.a, 0.001);
    float3 lf_mip2     = lf_mip2_tex.rgb;

    // ── R105: halation — negative stock property; fires before print stock (P1, R120) ──
    // Physical order: halation occurs in the camera negative before printing.
    // Print stock then compresses and warm-tints the glow — the correct photochemical chain.
    {
        float3 hal_blur      = tex2D(LowFreqMip1Samp, uv).rgb;
        float3 hal_broad     = lf_mip2;
        float3 hal_ring      = max(0.0, hal_blur - col.rgb);
        float  hal_ring_luma = dot(hal_ring, float3(0.2126, 0.7152, 0.0722));
        float  hal_lore      = hal_ring_luma / (hal_ring_luma + HAL_GAMMA + 1e-6);
        float  hal_r         = hal_ring.r + hal_broad.r * 0.12;
        float  hal_g         = hal_ring.g * lerp(0.78, 0.94, hal_lore);
        float  hal_b         = hal_ring.b * lerp(0.22, 0.38, hal_lore);
        lin = saturate(lin + float3(hal_r, hal_g, hal_b) * float3(1.05, 0.45, 0.03) * HAL_STRENGTH);
    }

    // ── R51: print stock emulsion — Kodak 2383 characteristic curve approximation ──
    {
        float3 ps      = lin * (1.0 - 0.025) + 0.025;
        float3 toe     = ps * ps * 3.2;
        float3 shoulder = 1.0 - (1.0 - ps) * (1.0 - ps) * 1.8;
        ps = lerp(toe, shoulder, smoothstep(0.0, 0.5, ps));
        float luma_ps = dot(ps, float3(0.2126, 0.7152, 0.0722));
        float desat_w = 0.15 * (1.0 - smoothstep(0.0, fc_knee_toe, luma_ps))
                              * (1.0 - smoothstep(fc_knee, 1.0, luma_ps));
        ps = lerp(ps, luma_ps.xxx, desat_w);
        ps.r += 0.010 * (1.0 - ps.r);   // R110 rebalance: uniform reduced, tonal portion in masking coupler block
        ps.b -= 0.007 * (1.0 - ps.b);
        lin = lerp(lin, saturate(ps), PRINT_STOCK);
    }

    // ── R110: masking coupler — shadow warm bias; coupler consumed proportional to dye density ──
    // unexposed print areas retain full coupler → warm; highlights consume coupler → neutral
    {
        float mc_luma = dot(lin, float3(0.2126, 0.7152, 0.0722));
        float mc_w    = saturate(1.0 - mc_luma / 0.75);
        mc_w         *= mc_w;
        float mc_str  = PRINT_STOCK * 0.008 * mc_w;
        lin.r = saturate(lin.r + mc_str);
        lin.b = saturate(lin.b - mc_str * 0.65);
    }

    // ── R50: dye secondary absorption — dominant-channel soft attenuation ─────
    {
        float lin_min   = min(lin.r, min(lin.g, lin.b));
        float sat_proxy = max(lin.r, max(lin.g, lin.b)) - lin_min;
        float ramp      = smoothstep(0.0, 0.25, sat_proxy);
        float3 dom_mask = saturate((lin - lin_min) / max(sat_proxy, 0.001));
        // R81C: Beer-Lambert — exp(−α·c·d) is physically correct at high chroma
        float3 bl_abs = dom_mask * sat_proxy * ramp;
        float3 bl_x   = 0.065 * bl_abs;
        lin = saturate(lin * (1.0 - bl_x + bl_x * bl_x * 0.5));
        // R85: inter-channel dye coupling — Kodak 2383 spectral dye density curves
        // cyan dye (red-record) ~2.0% bleed into green; magenta (green-record) ~2.2% into blue
        float2 dye_cross = float2(dom_mask.r * sat_proxy * ramp * 0.020,
                                  dom_mask.g * sat_proxy * ramp * 0.022);
        lin.g = saturate(lin.g * (1.0 - dye_cross.x));
        lin.b = saturate(lin.b * (1.0 - dye_cross.y));
    }

    // ── BLEACH BYPASS: silver retention in print emulsion (P2, R120) ─────────
    // Skipping the bleach step retains metallic silver alongside color dye.
    // Silver is achromatic — desaturates strongest in shadows (denser unexposed areas).
    // Retained silver adds neutral density, steepening midtone contrast.
    {
        float3 lab_bb  = RGBtoOklab(lin);
        float  bb_dark = 1.0 - smoothstep(0.0, 0.65, lab_bb.x);
        float  bb_desat = BLEACH_BYPASS * lerp(0.35, 0.72, bb_dark);
        lab_bb.y *= (1.0 - bb_desat);
        lab_bb.z *= (1.0 - bb_desat);
        float  bb_mid  = lab_bb.x * (1.0 - lab_bb.x) * 4.0;
        lab_bb.x = saturate(lab_bb.x - BLEACH_BYPASS * 0.055 * bb_mid);
        lin = saturate(OklabToRGB(lab_bb));
    }

    // ── R19: 3-way color corrector — temp/tint per region ────────────────────
    // R117: region masking in sqrt(luma) ≈ gamma-2 space, matching Resolve-style perceptual
    // split. Linear-luma boundaries (0.35/0.65) placed "shadow" over most of the perceptual
    // image in dark games; sqrt gives intuitive half-pixels-per-region coverage.
    {
        float r19_luma = Luma(lin);
        float r19_g    = sqrt(r19_luma);  // gamma-2 approximation of perceptual lightness
        float r19_sh   = saturate(1.0 - r19_g / 0.35);
        float r19_hl   = saturate((r19_g - 0.65) / 0.35);
        float r19_mid  = 1.0 - r19_sh - r19_hl;

        float3 r19_sh_delta  = float3(+SHADOW_TEMP + SHADOW_TINT * 0.5, -SHADOW_TINT, -SHADOW_TEMP + SHADOW_TINT * 0.5) * 0.0003;
        float3 r19_mid_delta = float3(+MID_TEMP       + MID_TINT       * 0.5, -MID_TINT,       -MID_TEMP       + MID_TINT       * 0.5) * 0.0003;
        float3 r19_hl_delta  = float3(+HIGHLIGHT_TEMP + HIGHLIGHT_TINT * 0.5, -HIGHLIGHT_TINT, -HIGHLIGHT_TEMP + HIGHLIGHT_TINT * 0.5) * 0.0003;

        lin = saturate(lin + r19_sh_delta * r19_sh + r19_mid_delta * r19_mid + r19_hl_delta * r19_hl);
    }

    // ── 2. TONAL: Zone contrast + Clarity + Shadow lift ───────────────────────
    float luma        = Luma(lin);
    float4 zone_lvl   = tex2Dlod(ZoneHistorySamp, float4(uv, 0, 0));
    float zone_median = zone_lvl.r;
    float zone_iqr    = zone_lvl.b - zone_lvl.g;
    // R33: CLAHE-inspired clip limit — bounds S-curve slope; tightens when Retinex is engaged
    float clahe_slope = lerp(1.32, 1.12, ss_04_25);
    float iqr_scale   = min(smoothstep(0.0, 0.25, zone_iqr),
                            (clahe_slope - 1.0) / max(zone_str, 0.001));
    float delta    = luma - zone_median;
    float zone_adj = zone_str * iqr_scale * delta * (1.0 - abs(delta));
    float above_w  = smoothstep(-0.05, 0.10, delta);
    float new_luma = saturate(luma + zone_adj * above_w);


    // R29: Multi-Scale Retinex — pixel-local illumination/reflectance separation
    float illum_s0  = max(tex2D(LowFreqMip1Samp, uv).a, 0.001);
    float local_var = abs(illum_s0 - illum_s2);
    float nl_safe   = max(new_luma, 0.001);
    float log_R     = log2(nl_safe / illum_s0);
    float zk_safe   = max(zone_log_key, 0.001);
    new_luma = lerp(new_luma, saturate(nl_safe * zk_safe / illum_s0), 0.75 * ss_04_25);

    float local_range_att = 1.0 - smoothstep(0.20, 0.50, zone_iqr);
    float texture_att     = 1.0 - smoothstep(0.005, 0.030, local_var);
    float detail_protect  = smoothstep(-0.5, 0.0, log_R);
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
    float slow_key     = max(tex2Dlod(ChromaHistory, float4(7.5 / 8.0, 0.5 / 4.0, 0, 0)).r, 0.001);
    float context_lift = exp2(log2(slow_key / zk_safe) * 0.4);
    float _sls_t = saturate((perc.r - 0.025) / 0.175);
    float shadow_lift_str = lerp(1.50, 0.45, _sls_t*_sls_t*_sls_t*(_sls_t*(_sls_t*6.0-15.0)+10.0));
    float shadow_lift     = shadow_lift_str * (0.149169 / (illum_s0 * illum_s0 + 0.003)) * local_range_att * texture_att * fine_texture_att * detail_protect * context_lift;
    float lift_w      = new_luma * smoothstep(0.25, 0.0, new_luma);
    new_luma          = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w * SHADOW_LIFT_STRENGTH);
    // R62 Finding 3: chroma-stable tonal — apply luma ratio in Oklab L to prevent zone S-curve from shifting chroma
    float3 lab_t  = RGBtoOklab(saturate(lin));
    float r_tonal = new_luma / max(luma, 0.001);
    float cbrt_r  = exp2(log2(max(r_tonal, 1e-10)) * (1.0 / 3.0));
    lab_t.x = saturate(lab_t.x * cbrt_r);
    // R65: R119 fix — CAM16 Hunt exponent 0.25. Prior exponent 1.0 (C/L constant) tripled
    // chroma at 3× lift. Correct: colorfulness ∝ L^0.25 (Hunt 2004, CIECAM02 eq.14-16).
    float r65_scale = exp2(log2(max(r_tonal, 1e-10)) * 0.25);
    float r65_sw    = smoothstep(0.25, 0.0, lab_t.x);
    lab_t.y = lab_t.y * lerp(1.0, r65_scale, r65_sw);
    lab_t.z = lab_t.z * lerp(1.0, r65_scale, r65_sw);
    // R66: ambient shadow tint — inject scene-ambient hue into achromatic lifted shadows.
    // Normalise illum_s2 RGB to extract hue direction at 18% gray (decouples from local luma).
    {
        float3 illum_s2_rgb = lf_mip2;
        float3 illum_norm   = illum_s2_rgb / max(Luma(illum_s2_rgb), 0.001);
        float3 lab_amb      = RGBtoOklab(illum_norm * 0.18);
        float  scene_cut    = ReadHWY(HWY_SCENE_CUT);
        float  lab_t_C      = length(lab_t.yz);
        float  achrom_w     = 1.0 - smoothstep(0.0, 0.05, lab_t_C);
        float  c_gate       = saturate(1.0 - lab_t_C / 0.10);  // R119: zero tint for colored objects
        float  r66_w        = r65_sw * achrom_w * c_gate * (1.0 - scene_cut) * 0.20;
        lab_t.y = lerp(lab_t.y, lab_amb.y, r66_w);
        lab_t.z = lerp(lab_t.z, lab_amb.z, r66_w);
    }
    lin = saturate(OklabToRGB(lab_t));

    // ── 3. CHROMA: Oklab chroma lift ──────────────────────────────────────────
    float3 lab = RGBtoOklab(lin);
    float  C   = length(lab.yz);
    float  C_stim = C;
    float  h   = OklabHueNorm(lab.y, lab.z);
    // HELMLAB: 2-harmonic Fourier correction aligns Oklab hue toward perceptual hue.
    // Corrects 8.9× non-uniformity in blue-cyan band (HELMLAB 2026, arxiv 2602.23010).
    float  h_theta = h * 6.28318;
    float  sh_h, ch_h;
    sincos(h_theta, sh_h, ch_h);
    float  dh      = sh_h * (0.008 + 0.008 * ch_h);
    float  h_perc  = frac(h + dh / 6.28318);

    // ── R52: Purkinje shift — rod-vision blue-green bias in deep shadows ───────
    {
        float scotopic_w = 1.0 - smoothstep(0.0, 0.30, new_luma);  // R117: widened from 0.12; mesopic transition spans full scotopic-photopic range
        lab.z -= 0.018 * scotopic_w * C * PURKINJE_STRENGTH;
        C = length(lab.yz);
    }

    // R22: saturation by luminance — baked Munsell calibration (shadow 20%, highlight 45%)
    // + midtone expansion bell from cinema SDR mastering data (Žaganeli et al. 2026)
    float mid_C_boost = 0.08 * smoothstep(0.22, 0.40, lab.x)
                             * (1.0 - smoothstep(0.55, 0.70, lab.x));
    // R74: highlight desaturation — film shoulder rolloff, silvery highlights (Shift analog intermediate)
    float r74_desat = 0.30 * saturate((lab.x - 0.80) / 0.20);
    C *= (1.0 + mid_C_boost
             - 0.20 * saturate(1.0 - lab.x / 0.25)
             - 0.45 * saturate((lab.x - 0.75) / 0.25)
             - r74_desat);

    // R21: per-band hue rotation — compute h_out from original h before chroma lift
    float r21_delta = ROT_RED    * HueBandWeight(h_perc, BAND_RED)
                    + ROT_YELLOW * HueBandWeight(h_perc, BAND_YELLOW)
                    + ROT_GREEN  * HueBandWeight(h_perc, BAND_GREEN)
                    + ROT_CYAN   * HueBandWeight(h_perc, BAND_CYAN)
                    + ROT_BLUE   * HueBandWeight(h_perc, BAND_BLUE)
                    + ROT_MAG    * HueBandWeight(h_perc, BAND_MAGENTA);
    // R125: Bezold-Brücke — anchored at Oklab invariant hues (h=0.25 yellow, h=0.75 blue)
    // ch_h zeros at h=0.25/0.75 by construction; sh2_h adds asymmetry via double-angle (4 MAD)
    float sh2_h    = 2.0 * sh_h * ch_h;
    r21_delta     += (lab.x - 0.50) * 0.015 * (ch_h + 0.9 * sh2_h);
    float h_out = frac(h_perc + r21_delta * 0.10);
    float hw_o0  = HueBandWeight(h_out, BAND_RED);
    float hw_org = HueBandWeight(h_out, BAND_ORANGE);
    float hw_amb = HueBandWeight(h_out, BAND_AMBER);
    float hw_o1  = HueBandWeight(h_out, BAND_YELLOW);
    float hw_o2  = HueBandWeight(h_out, BAND_GREEN);
    float hw_tel = HueBandWeight(h_out, BAND_TEAL);
    float hw_o3  = HueBandWeight(h_out, BAND_CYAN);
    float hw_azr = HueBandWeight(h_out, BAND_AZURE);
    float hw_o4  = HueBandWeight(h_out, BAND_BLUE);
    float hw_vio = HueBandWeight(h_out, BAND_VIOLET);
    float hw_o5  = HueBandWeight(h_out, BAND_MAGENTA);
    float hw_ros = HueBandWeight(h_out, BAND_ROSE);

    float chroma_str = CHROMA_STR * 0.04;
    chroma_str *= lerp(1.0, 0.65, smoothstep(0.02, 0.08, local_var));  // R68A: attenuate in textured regions
    chroma_str *= lerp(0.80, 1.20, smoothstep(0.05, 0.35, zone_log_key));  // R117: Hunt — colorfulness scales with adapting luminance
    float density_str = 50.0;

    float new_C = 0.0, total_w = 0.0;
    [unroll] for (int band = 0; band < 6; band++)
    {
        float pivot = tex2Dlod(ChromaHistory, float4((band + 0.5) / 8.0, 0.5 / 4.0, 0, 0)).r;
        float w = HueBandWeight(h_perc, GetBandCenter(band));
        new_C   += LiftChroma(C, pivot, chroma_str) * w;
        total_w += w;
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

    // Vector-space (a,b) reconstruction — rotate original direction by R21 delta
    float r21_cos, r21_sin;
    sincos(r21_delta * (0.10 * 6.28318), r21_sin, r21_cos);
    float2 ab_in  = float2(lab.y * r21_cos - lab.z * r21_sin,
                           lab.y * r21_sin + lab.z * r21_cos);
    float  C_safe = max(C, 1e-6);
    float2 ab_s   = ab_in * (final_C / C_safe);

    float abney  = (+hw_o0 * 0.06    // RED     — shifts toward yellow
                   - hw_o1 * 0.05    // YELLOW  — shifts toward red
                   + hw_o2 * 0.02    // GREEN   — shifts toward yellow-green (R69)
                   - hw_o3 * 0.08    // CYAN    — shifts toward yellow-green
                   + hw_o4 * 0.04    // BLUE    — shifts toward purple
                   + hw_o5 * 0.03) * C_stim;
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
    float hk_exp   = lerp(0.52, 0.64, saturate(zone_log_key / 0.50));
    float hk_boost = 1.0 + 0.25 * f_hk * pow(max(final_C, 0.0), hk_exp);
    float final_L  = saturate(lab.x / lerp(1.0, hk_boost, smoothstep(0.0, 0.35, lab.x)));

    // R117C: chromatic induction — broad surround hue nudges near-achromatic pixels toward complement.
    // Simultaneous contrast: a grey patch in a coloured surround takes on a slight opposite hue tinge.
    // Uses LowFreqMip2 (1/32-res, already read by R66 + halation) as the spatial surround estimate.
    // Gate: ind_mask → 0 as pixel chroma rises; full effect only on achromatic / low-chroma pixels.
    // Strength 0.12: for a moderately warm surround (Oklab a≈0.04), shift ≈ 0.005 in f_oka — subtle.
    {
        float3 surr     = lf_mip2;
        float3 surr_lab = RGBtoOklab(surr / max(Luma(surr), 0.001) * 0.18);
        float  ind_mask = saturate(1.0 - final_C / 0.06);
        f_oka -= surr_lab.y * 0.12 * ind_mask;
        f_okb -= surr_lab.z * 0.12 * ind_mask;
    }

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
    lin = saturate(chroma_rgb);

    // dither: break 8-bit BackBuffer quantization — converts banding to imperceptible noise
    // R89: IGN blue-noise dither (Jimenez 2016) — pushes quantization error to high freq
    float dither = frac(52.9829189 * frac(dot(pos.xy, float2(0.06711056, 0.00583715)))) - 0.5;
    lin += dither * (1.0 / 255.0);

    return DrawLabel(float4(lin, col.a), pos.xy, 270.0, 50.0,
                     54u, 71u, 82u, 65u, float3(0.2, 0.50, 1.0)); // 6GRA
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

// ─── Pro-Mist passes (merged from pro_mist.fx — saves one inter-effect overhead) ──

float4 MistDownsamplePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    if (pos.y < 1.0) return float4(0.0, 0.0, 0.0, 0.0);
    return float4(tex2D(BackBuffer, uv).rgb, 1.0);
}

float4 ProMistPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 base = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return base;

    // R115: shimmer model — additive bloom only where blur > sharp (highlight→shadow bleed).
    // Dark pixels near bright sources glow; midtones and shadows unaffected.
    // Reinhard knee at 0.08: soft shoulder prevents clipping; adapt_str controls overall scale.
    float3 mist_tight   = tex2Dlod(MistDiffuseSamp, float4(uv, 0, 0)).rgb;
    float3 mist_wide    = tex2Dlod(MistDiffuseSamp, float4(uv, 0, 1)).rgb;
    float3 mist_broader = tex2Dlod(MistDiffuseSamp, float4(uv, 0, 2)).rgb;

    float4 perc           = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));
    float  iqr            = perc.b - perc.r;
    float  adapt_str      = MIST_STRENGTH * 0.15 * lerp(0.8, 1.2, saturate(iqr / 0.5));
    float  zone_log_key   = tex2Dlod(ChromaHistory, float4(6.5 / 8.0, 0.5 / 4.0, 0, 0)).r;
    float  mist_key_scale = lerp(1.20, 0.85, smoothstep(0.05, 0.25, zone_log_key));
    float  mist_ap_scale  = lerp(1.10, 0.90, saturate((EXPOSURE - 0.70) / 0.60));
    adapt_str *= mist_key_scale * mist_ap_scale;

    float  scale_w  = saturate(MIST_STRENGTH * 0.25);
    float  broad_w  = saturate(MIST_STRENGTH * 0.20 - 0.10);
    float3 blurred  = lerp(lerp(mist_tight, mist_wide, scale_w), mist_broader, broad_w);
    float3 bloom_raw = max(0.0, blurred - base.rgb);
    float3 bloom     = bloom_raw / (bloom_raw + 0.08);
    float3 result    = saturate(base.rgb + bloom * adapt_str);

    float dither = frac(52.9829189 * frac(dot(pos.xy, float2(0.06711056, 0.00583715)))) - 0.5;
    result += dither * (1.0 / 255.0);

    float4 out_col = float4(saturate(result), base.a);
    return DrawLabel(out_col, pos.xy, 270.0, 58.0,
                     55u, 80u, 77u, 83u, float3(0.9, 0.1, 0.9)); // 7PMS
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

    for (int iy = 0; iy < 9; iy++)
    for (int ix = 0; ix < 16; ix++)
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
    pass ColorTransform
    {
        VertexShader = PostProcessVS;
        PixelShader  = ColorTransformPS;
    }
    pass MistDownsample
    {
        VertexShader = PostProcessVS;
        PixelShader  = MistDownsamplePS;
        RenderTarget = MistDiffuseTex;
    }
    pass ProMist
    {
        VertexShader = PostProcessVS;
        PixelShader  = ProMistPS;
    }
}
