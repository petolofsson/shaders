// creative_color_grade.fx — Mega-pass: all downstream color work in one full-res pass
#include "debug_text.fxh"
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
#define BAND_WIDTH      8
#define MIN_WEIGHT      1.0
#define SAT_THRESHOLD   2
#define GREEN_HUE_COOL  (4.0 / 360.0)
#define BAND_RED        0.083
#define BAND_YELLOW     0.305
#define BAND_GREEN      0.396
#define BAND_CYAN       0.542
#define BAND_BLUE       0.735
#define BAND_MAGENTA    0.913


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

// R46: highlight warm bias EMA (written by corrective.fx WarmBias pass)
texture2D WarmBiasTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D WarmBiasSamp
{
    Texture   = WarmBiasTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// R47: shadow warm bias EMA (written by corrective.fx ShadowBias pass)
texture2D ShadowBiasTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D ShadowBiasSamp
{
    Texture   = ShadowBiasTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// R53: scene-cut signal (written by analysis_frame, read here for R66 gate)
texture2D SceneCutTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D SceneCutSamp
{
    Texture   = SceneCutTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
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

float HueBandWeight(float hue, float center)
{
    float d = abs(hue - center);
    d = min(d, 1.0 - d);
    float t = saturate(1.0 - d / (BAND_WIDTH / 100.0));
    return t * t * (3.0 - 2.0 * t);
}

float PivotedSCurve(float x, float m, float strength)
{
    float t    = x - m;
    float bent = t + strength * t * (1.0 - saturate(abs(t)));
    return saturate(m + bent);
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
    // R81A: eye LCA — blue samples outward, red samples inward (radially from centre)
    float2 lca_off = (uv - 0.5) * LCA_STRENGTH * 0.004;
    float4 col     = tex2D(BackBuffer, uv);
    col.r          = tex2D(BackBuffer, uv - lca_off).r;
    col.b          = tex2D(BackBuffer, uv + lca_off).b;
    if (pos.y < 1.0) return col;  // data highway

    // R54: camera signal floor/ceiling — compress raw pixel into [FILM_FLOOR, FILM_CEILING]
    col.rgb = col.rgb * (FILM_CEILING - FILM_FLOOR) + FILM_FLOOR;

    // R76A: CAT16 chromatic adaptation — normalise scene illuminant toward D65
    {
        const float3x3 M_fwd = float3x3(0.302825, 0.602279, 0.070428,
                                         0.153818, 0.777214, 0.085341,
                                         0.027974, 0.147911, 0.908874);
        const float3x3 M_bwd = float3x3( 5.4459, -4.2155, -0.0242,
                                         -1.0784,  2.1456, -0.1184,
                                          0.0078, -0.2191,  1.1200);
        const float3 lms_d65 = float3(0.9756, 1.0165, 1.0849);
        float3 illum_rgb  = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2.0)).rgb;
        float3 illum_norm = illum_rgb / max(Luma(illum_rgb), 0.001);
        float3 lms_illum  = mul(M_fwd, illum_norm);
        float3 gain      = clamp(lms_d65 / max(lms_illum, 0.001), 0.5, 2.0);
        float3 lms_px    = mul(M_fwd, col.rgb) * gain;
        float3 cat16     = mul(M_bwd, lms_px);
        cat16            = cat16 * (Luma(col.rgb) / max(Luma(cat16), 0.001));
        col.rgb          = lerp(col.rgb, saturate(cat16), 0.60);
    }
    // R76B: CIECAM02 surround compensation
    col.rgb = pow(max(col.rgb, 0.0), VIEWING_SURROUND);

    float4 perc = tex2D(PercSamp, float2(0.5, 0.5));

    // R32: zone global stats — pre-computed in UpdateHistoryPS, stored in ChromaHistoryTex col 6
    float4 zstats      = tex2D(ChromaHistory, float2(6.5 / 8.0, 0.5 / 4.0));
    float zone_log_key = zstats.r;
    float zone_std     = zstats.g;
    float eff_p25      = lerp(perc.r, zstats.b, 0.4);
    float eff_p75      = lerp(perc.b, zstats.a, 0.4);
    float ss_08_25     = smoothstep(0.08, 0.25, zone_std);
    float ss_04_25     = smoothstep(0.04, 0.25, zone_std);
    float spread_scale = lerp(0.7, 1.1, ss_08_25);
    float lum_att      = smoothstep(0.10, 0.40, zone_log_key);
    float zone_str     = lerp(0.26, 0.16, ss_08_25)
                       * lerp(1.10, 0.93, lum_att) * ZONE_STRENGTH;

    // ── 1. CORRECTIVE: EXPOSURE + FilmCurve ──────────────────────────────────
    // Frame-constant FilmCurve coefficients — hoisted out of per-pixel path (R62 OPT-2)
    float fc_knee     = lerp(0.90, 0.80, saturate((eff_p75 - 0.60) / 0.30));
    float fc_width    = 1.0 - fc_knee;
    float fc_stevens  = (1.48 + sqrt(max(zone_log_key, 0.0))) / 2.03;
    float fc_factor   = 0.05 / (fc_width * fc_width) * fc_stevens * spread_scale;
    float fc_knee_toe = lerp(0.15, 0.25, saturate((0.40 - eff_p25) / 0.30));
    float fc_knee_r   = clamp(fc_knee + CURVE_R_KNEE, 0.70, 0.95);
    float fc_knee_b   = clamp(fc_knee + CURVE_B_KNEE, 0.70, 0.95);
    float fc_ktoe_r   = clamp(fc_knee_toe + CURVE_R_TOE, 0.08, 0.35);
    float fc_ktoe_b   = clamp(fc_knee_toe + CURVE_B_TOE, 0.08, 0.35);
    float fc_toe_fac  = 0.03 / (fc_knee_toe * fc_knee_toe);
    float3 lin = FilmCurveApply(pow(max(col.rgb, 0.0), EXPOSURE),
                                fc_knee_r, fc_knee, fc_knee_b,
                                fc_ktoe_r, fc_knee_toe, fc_ktoe_b,
                                fc_factor, fc_toe_fac);
    lin = lerp(col.rgb, lin, CORRECTIVE_STRENGTH / 100.0);

    // ── R51: print stock emulsion — Kodak 2383 characteristic curve approximation ──
    {
        float3 ps      = lin * (1.0 - 0.025) + 0.025;
        float3 toe     = ps * ps * 3.2;
        float3 shoulder = 1.0 - (1.0 - ps) * (1.0 - ps) * 1.8;
        ps = lerp(toe, shoulder, smoothstep(0.0, 0.5, ps));
        float luma_ps = dot(ps, float3(0.2126, 0.7152, 0.0722));
        float desat_w = 0.15 * (1.0 - smoothstep(0.0, 0.3, luma_ps))
                              * (1.0 - smoothstep(0.6, 1.0, luma_ps));
        ps = lerp(ps, luma_ps.xxx, desat_w);
        ps.r += 0.012 * (1.0 - ps.r);
        ps.b -= 0.008 * (1.0 - ps.b);
        lin = lerp(lin, saturate(ps), PRINT_STOCK);
    }

    // ── R50: dye secondary absorption — dominant-channel soft attenuation ─────
    {
        float lin_min   = min(lin.r, min(lin.g, lin.b));
        float sat_proxy = max(lin.r, max(lin.g, lin.b)) - lin_min;
        float ramp      = smoothstep(0.0, 0.25, sat_proxy);
        float3 dom_mask = saturate((lin - lin_min) / max(sat_proxy, 0.001));
        // R81C: Beer-Lambert — exp(−α·c·d) is physically correct at high chroma
        float3 bl_abs = dom_mask * sat_proxy * ramp;
        lin = saturate(lin * exp(-0.065 * bl_abs));
    }

    // ── R19: 3-way color corrector — temp/tint per region, linear light ──────
    {
        float r19_luma = Luma(lin);
        float r19_sh   = saturate(1.0 - r19_luma / 0.35);
        float r19_hl   = saturate((r19_luma - 0.65) / 0.35);
        float r19_mid  = 1.0 - r19_sh - r19_hl;

        // R47: scene-adaptive shadow temperature — gated by zone_std to exclude UI frames
        float shadow_bias  = tex2Dlod(ShadowBiasSamp, float4(0.5, 0.5, 0, 0)).r;
        float r47_gate     = smoothstep(0.06, 0.15, zone_std);
        float sh_temp_auto = clamp(lerp(0.0, -20.0, smoothstep(0.02, 0.12,  shadow_bias))
                                 + lerp(0.0, +15.0, smoothstep(0.02, 0.10, -shadow_bias)),
                                   -22.0, 18.0) * r47_gate;
        float3 r19_sh_delta  = float3(+(SHADOW_TEMP + sh_temp_auto) + SHADOW_TINT * 0.5, -SHADOW_TINT, -(SHADOW_TEMP + sh_temp_auto) + SHADOW_TINT * 0.5) * 0.0003;
        float3 r19_mid_delta = float3(+MID_TEMP       + MID_TINT       * 0.5, -MID_TINT,       -MID_TEMP       + MID_TINT       * 0.5) * 0.0003;
        float3 r19_hl_delta  = float3(+HIGHLIGHT_TEMP + HIGHLIGHT_TINT * 0.5, -HIGHLIGHT_TINT, -HIGHLIGHT_TEMP + HIGHLIGHT_TINT * 0.5) * 0.0003;

        lin = saturate(lin + r19_sh_delta * r19_sh + r19_mid_delta * r19_mid + r19_hl_delta * r19_hl);
    }

    // ── 2. TONAL: Zone contrast + Clarity + Shadow lift ───────────────────────
    float3 lin_pre_tonal = lin;
    float luma        = Luma(lin);
    float4 zone_lvl   = tex2D(ZoneHistorySamp, uv);
    float zone_median = zone_lvl.r;
    float zone_iqr    = zone_lvl.b - zone_lvl.g;
    // R33: CLAHE-inspired clip limit — bounds S-curve slope; tightens when Retinex is engaged
    float clahe_slope = lerp(1.32, 1.12, ss_04_25);
    float iqr_scale   = min(smoothstep(0.0, 0.25, zone_iqr),
                            (clahe_slope - 1.0) / max(zone_str, 0.001));
    float new_luma    = saturate(zone_median + (luma - zone_median) * (1.0 + zone_str * iqr_scale * (1.0 - saturate(abs(luma - zone_median)))));


    // R29: Multi-Scale Retinex — pixel-local illumination/reflectance separation
    float4 lf_mip1  = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1));
    float illum_s0  = max(lf_mip1.a, 0.001);
    float illum_s2  = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).a, 0.001);
    float local_var = abs(illum_s0 - illum_s2);
    float nl_safe   = max(new_luma, 0.001);
    float log_R     = log2(nl_safe / illum_s0);
    float zk_safe   = max(zone_log_key, 0.001);
    new_luma = lerp(new_luma, saturate(nl_safe * zk_safe / illum_s0), 0.75 * ss_04_25);

    float local_range_att = 1.0 - smoothstep(0.20, 0.50, zone_iqr);
    float texture_att     = 1.0 - smoothstep(0.005, 0.030, local_var);
    float detail_protect  = smoothstep(-0.5, 0.0, log_R);
    // R60: temporal context — slow ambient key boosts lift during dark transitions, suppresses on re-entry
    float slow_key     = max(tex2Dlod(ChromaHistory, float4(7.5 / 8.0, 0.5 / 4.0, 0, 0)).r, 0.001);
    float context_lift = exp2(log2(slow_key / zk_safe) * 0.4);
    float shadow_lift_str = lerp(1.50, 0.45, smoothstep(0.03, 0.22, perc.r));
    float shadow_lift     = shadow_lift_str * (0.149169 / (illum_s0 * illum_s0 + 0.003)) * local_range_att * texture_att * detail_protect * context_lift;
    float lift_w      = new_luma * smoothstep(0.30, 0.0, new_luma);
    new_luma          = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w);
    // R62 Finding 3: chroma-stable tonal — apply luma ratio in Oklab L to prevent zone S-curve from shifting chroma
    float3 lab_t  = RGBtoOklab(saturate(lin));
    float r_tonal = new_luma / max(luma, 0.001);
    lab_t.x = saturate(lab_t.x * exp2(log2(max(r_tonal, 1e-10)) * (1.0 / 3.0)));
    // R65: couple a/b to L — maintains C/L (Oklab saturation) during shadow lift
    float r65_ab = exp2(log2(max(r_tonal, 1e-5)) * 0.333);
    float r65_sw = smoothstep(0.30, 0.0, lab_t.x);
    lab_t.y = lab_t.y * lerp(1.0, r65_ab, r65_sw);
    lab_t.z = lab_t.z * lerp(1.0, r65_ab, r65_sw);
    // R66: ambient shadow tint — inject scene-ambient hue into achromatic lifted shadows.
    // Normalise illum_s2 RGB to extract hue direction at 18% gray (decouples from local luma).
    {
        float3 illum_s2_rgb = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2.0)).rgb;
        float3 illum_norm   = illum_s2_rgb / max(Luma(illum_s2_rgb), 0.001);
        float3 lab_amb      = RGBtoOklab(illum_norm * 0.18);
        float  scene_cut    = tex2Dlod(SceneCutSamp, float4(0.5, 0.5, 0, 0)).r;
        float  achrom_w     = 1.0 - smoothstep(0.0, 0.05, length(lab_t.yz));
        float  r66_w        = r65_sw * achrom_w * (1.0 - scene_cut) * 0.4;
        lab_t.y = lerp(lab_t.y, lab_amb.y, r66_w);
        lab_t.z = lerp(lab_t.z, lab_amb.z, r66_w);
    }
    lin = saturate(OklabToRGB(lab_t));
    lin = lerp(lin_pre_tonal, lin, TONAL_STRENGTH / 100.0);

    // ── 3. CHROMA: Oklab chroma lift ──────────────────────────────────────────
    float3 lab = RGBtoOklab(lin);
    float  C   = length(lab.yz);
    float  h   = OklabHueNorm(lab.y, lab.z);
    // HELMLAB: 2-harmonic Fourier correction aligns Oklab hue toward perceptual hue.
    // Corrects 8.9× non-uniformity in blue-cyan band (HELMLAB 2026, arxiv 2602.23010).
    float  h_theta = h * 6.28318;
    float  h_perc  = frac(h + (0.008 * sin(h_theta) + 0.004 * sin(2.0 * h_theta)) / 6.28318);

    // ── R52: Purkinje shift — rod-vision blue-green bias in deep shadows ───────
    {
        float scotopic_w = 1.0 - smoothstep(0.0, 0.12, new_luma);
        lab.z -= 0.018 * scotopic_w * C * PURKINJE_STRENGTH;
        C = length(lab.yz);
    }

    // R22: saturation by luminance — baked Munsell calibration (shadow 20%, highlight 45%)
    C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)
                      - 0.45 * saturate((lab.x - 0.75) / 0.25));

    // R21: per-band hue rotation — compute h_out from original h before chroma lift
    float r21_delta = ROT_RED    * HueBandWeight(h_perc, BAND_RED)
                    + ROT_YELLOW * HueBandWeight(h_perc, BAND_YELLOW)
                    + ROT_GREEN  * HueBandWeight(h_perc, BAND_GREEN)
                    + ROT_CYAN   * HueBandWeight(h_perc, BAND_CYAN)
                    + ROT_BLUE   * HueBandWeight(h_perc, BAND_BLUE)
                    + ROT_MAG    * HueBandWeight(h_perc, BAND_MAGENTA);
    // R75: hue-by-luminance — cool shadows, warm highlights (2383 tonal character)
    r21_delta += lerp(-0.003, +0.003, lab.x);
    float h_out = frac(h_perc + r21_delta * 0.10);
    float hw_o0 = HueBandWeight(h_out, BAND_RED);
    float hw_o1 = HueBandWeight(h_out, BAND_YELLOW);
    float hw_o2 = HueBandWeight(h_out, BAND_GREEN);
    float hw_o3 = HueBandWeight(h_out, BAND_CYAN);
    float hw_o4 = HueBandWeight(h_out, BAND_BLUE);
    float hw_o5 = HueBandWeight(h_out, BAND_MAGENTA);

    float la         = max(zone_log_key, 0.001);
    float k          = 1.0 / (5.0 * la + 1.0);
    float k2         = k * k;
    float k4         = k2 * k2;
    float fla        = 5.0 * la;
    float one_mk4    = 1.0 - k4;
    float fl         = k4 * la + 0.1 * one_mk4 * one_mk4 * pow(fla, 1.0 / 3.0);
    float hunt_scale = sqrt(sqrt(max(fl, 1e-6))) / 0.5912;

    // R36: mean_chroma → adaptive chroma and density strengths
    float4 hist_cache[6];
    float cm_t = 0.0, cm_w = 0.0;
    [unroll] for (int bi = 0; bi < 6; bi++)
    {
        hist_cache[bi] = tex2D(ChromaHistory, float2((bi + 0.5) / 8.0, 0.5 / 4.0));
        cm_t += hist_cache[bi].r * hist_cache[bi].b;
        cm_w += hist_cache[bi].b;
    }
    float mean_chroma  = cm_t / max(cm_w, 0.001);
    float chroma_exp  = exp2(-5.006152 * mean_chroma);
    float chroma_mc_t   = smoothstep(0.05, 0.25, mean_chroma);
    float chroma_p50_t  = smoothstep(0.15, 0.55, perc.g);
    float chroma_drive  = saturate(chroma_mc_t + 0.35 * chroma_p50_t);
    float chroma_str    = saturate(0.085 * chroma_exp * hunt_scale * lerp(1.25, 0.60, chroma_drive));
    float density_str = 62.0 - 20.0 * chroma_exp;
    // R68A: spatial chroma modulation — attenuate in textured regions, full in flat.
    chroma_str *= lerp(1.0, 0.65, smoothstep(0.02, 0.08, local_var));

    float new_C = 0.0, total_w = 0.0, green_w = 0.0;
    [unroll] for (int band = 0; band < 6; band++)
    {
        float w = HueBandWeight(h_perc, GetBandCenter(band));
        new_C   += PivotedSCurve(C, hist_cache[band].r, chroma_str) * w;
        total_w += w;
    }
    // max(lifted, C) — lift-only; identity limit at C = 0 by construction
    float lifted_C = (total_w > 0.001) ? new_C / total_w : C;
    // R71: vibrance — attenuate lift delta on already-saturated pixels.
    float vib_mask = saturate(1.0 - C / 0.22);
    float vib_C    = C + max(lifted_C - C, 0.0) * vib_mask;
    // R73: memory color protection — per-band chroma ceiling (sky/foliage/skin).
    // R81B: MacAdam-calibrated ceilings — blue/cyan tightened (smallest discrimination
    // ellipses), yellow relaxed (largest ellipses).
    float C_ceil   = hw_o0 * 0.28 + hw_o1 * 0.24 + hw_o2 * 0.16
                   + hw_o3 * 0.15 + hw_o4 * 0.19 + hw_o5 * 0.22;
    float final_C  = min(vib_C, max(C_ceil, C));
    green_w = hw_o2;

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
                   + hw_o5 * 0.03) * final_C;
    float dtheta = +(GREEN_HUE_COOL * 2.0 * 3.14159265) * green_w * final_C + abney;
    float cos_dt = 1.0 - dtheta * dtheta * 0.5;
    float sin_dt = dtheta;
    float f_oka  = ab_s.x * cos_dt - ab_s.y * sin_dt;
    float f_okb  = ab_s.x * sin_dt + ab_s.y * cos_dt;

    // Hellwig 2022: hue-dependent H-K correction, C^0.587 (R15)
    float sh, ch;
    sincos(h_out * 6.28318, sh, ch);
    float f_hk     = -0.160 * ch + 0.132 * (ch*ch - sh*sh) - 0.405 * sh + 0.080 * (2.0*sh*ch) + 0.792;
    float hk_boost = 1.0 + 0.25 * f_hk * pow(final_C, 0.587);
    float final_L  = saturate(lab.x / lerp(1.0, hk_boost, smoothstep(0.0, 0.35, lab.x)));

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

    // R79: halation dual-PSF + softened gate + warm wing bias
    {
        float3 hal_core_r = lf_mip1.rgb;                                            // red core: mip 1 (hoisted, shared with Retinex)
        float3 hal_core_g = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 0)).rgb;   // green core: mip 0
        float3 hal_wing   = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).rgb;   // extended wing: mip 2
        float  hal_luma   = dot(lin, float3(0.2126, 0.7152, 0.0722));
        float  hal_gate   = smoothstep(0.70, 0.90, hal_luma);  // R79A: softer onset
        float3 hal_delta  = float3(
            max(0.0, lerp(hal_core_r, hal_wing, 0.30).r - lin.r),  // red: core + full wing
            max(0.0, lerp(hal_core_g, hal_wing, 0.20).g - lin.g),  // green: core + less wing (warm bias)
            0.0                                                      // blue: none — anti-halation
        );
        lin = saturate(lin + hal_delta * float3(1.2, 0.45, 0.0) * hal_gate * HAL_STRENGTH);
    }

    // dither: break 8-bit BackBuffer quantization — converts banding to imperceptible noise
    float dither = frac(sin(dot(pos.xy, float2(127.1, 311.7))) * 43758.5453) - 0.5;
    lin += dither * (1.0 / 255.0);

    return DrawLabel(float4(lin, col.a), pos.xy, 270.0, 50.0,
                     54u, 71u, 82u, 65u, float3(0.2, 0.50, 1.0)); // 6GRA
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique OlofssonianColorGrade
{
    pass ColorTransform
    {
        VertexShader = PostProcessVS;
        PixelShader  = ColorTransformPS;
    }
}
