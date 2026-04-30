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
#define BAND_WIDTH      14
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

float3 FilmCurve(float3 x, float p25, float p50, float p75, float spread,
                 float r_knee_off, float b_knee_off, float r_toe_off, float b_toe_off)
{
    float knee     = lerp(0.90, 0.80, saturate((p75 - 0.60) / 0.30));
    float width    = 1.0 - knee;
    float stevens  = (1.48 + sqrt(max(p50, 0.0))) / 2.03;
    float factor   = 0.05 / (width * width) * stevens * spread;
    float knee_toe = lerp(0.15, 0.25, saturate((0.40 - p25) / 0.30));

    float knee_r = clamp(knee + r_knee_off, 0.70, 0.95);
    float knee_g = knee;
    float knee_b = clamp(knee + b_knee_off, 0.70, 0.95);
    float ktoe_r = clamp(knee_toe + r_toe_off, 0.08, 0.35);
    float ktoe_g = knee_toe;
    float ktoe_b = clamp(knee_toe + b_toe_off, 0.08, 0.35);

    float3 above = max(x - float3(knee_r, knee_g, knee_b), 0.0);
    float3 below = max(float3(ktoe_r, ktoe_g, ktoe_b) - x, 0.0);
    return x - factor * above * above
               + (0.03 / (knee_toe * knee_toe)) * below * below;
}

float3 RGBtoOklab(float3 rgb)
{
    float l = dot(rgb, float3(0.4122214708, 0.5363325363, 0.0514459929));
    float m = dot(rgb, float3(0.2119034982, 0.6806995451, 0.1073969566));
    float s = dot(rgb, float3(0.0883024619, 0.2817188376, 0.6299787005));
    l = sign(l) * pow(abs(l), 1.0 / 3.0);
    m = sign(m) * pow(abs(m), 1.0 / 3.0);
    s = sign(s) * pow(abs(s), 1.0 / 3.0);
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
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;  // data highway

    float4 perc = tex2D(PercSamp, float2(0.5, 0.5));

    // R32: zone global stats — pre-computed in UpdateHistoryPS, stored in ChromaHistoryTex col 6
    float4 zstats      = tex2D(ChromaHistory, float2(6.5 / 8.0, 0.5 / 4.0));
    float zone_log_key = zstats.r;
    float zone_std     = zstats.g;
    float eff_p25      = lerp(perc.r, zstats.b, 0.4);
    float eff_p75      = lerp(perc.b, zstats.a, 0.4);
    float spread_scale = lerp(0.7, 1.1, smoothstep(0.08, 0.25, zone_std));
    float zone_str     = lerp(0.30, 0.18, smoothstep(0.08, 0.25, zone_std));

    // ── 1. CORRECTIVE: EXPOSURE + FilmCurve ──────────────────────────────────
    float3 lin = FilmCurve(pow(max(col.rgb, 0.0), EXPOSURE), eff_p25, zone_log_key, eff_p75, spread_scale,
                           CURVE_R_KNEE, CURVE_B_KNEE, CURVE_R_TOE, CURVE_B_TOE);
    lin = lerp(col.rgb, lin, CORRECTIVE_STRENGTH / 100.0);

    // ── R19: 3-way color corrector — temp/tint per region, linear light ──────
    {
        float r19_luma = Luma(lin);
        float r19_sh   = saturate(1.0 - r19_luma / 0.35);
        float r19_hl   = saturate((r19_luma - 0.65) / 0.35);
        float r19_mid  = 1.0 - r19_sh - r19_hl;

        float r19_scale = 0.030 / 100.0;

        float3 r19_sh_delta  = float3(+SHADOW_TEMP    + SHADOW_TINT    * 0.5, -SHADOW_TINT,    -SHADOW_TEMP    + SHADOW_TINT    * 0.5) * r19_scale;
        float3 r19_mid_delta = float3(+MID_TEMP       + MID_TINT       * 0.5, -MID_TINT,       -MID_TEMP       + MID_TINT       * 0.5) * r19_scale;
        float3 r19_hl_delta  = float3(+HIGHLIGHT_TEMP + HIGHLIGHT_TINT * 0.5, -HIGHLIGHT_TINT, -HIGHLIGHT_TEMP + HIGHLIGHT_TINT * 0.5) * r19_scale;

        lin = saturate(lin + r19_sh_delta * r19_sh + r19_mid_delta * r19_mid + r19_hl_delta * r19_hl);
    }

    // ── 2. TONAL: Zone contrast + Clarity + Shadow lift ───────────────────────
    float3 lin_pre_tonal = lin;
    float luma        = Luma(lin);
    float4 zone_lvl   = tex2D(ZoneHistorySamp, uv);
    float zone_median = zone_lvl.r;
    float zone_iqr    = zone_lvl.b - zone_lvl.g;
    // R33: CLAHE-inspired clip limit — bounds S-curve slope; tightens when Retinex is engaged
    float clahe_slope = lerp(1.40, 1.15, smoothstep(0.04, 0.25, zone_std));
    float iqr_scale   = min(smoothstep(0.0, 0.25, zone_iqr),
                            (clahe_slope - 1.0) / max(zone_str, 0.001));
    float dt          = luma - zone_median;
    float bent        = dt + zone_str * iqr_scale * dt * (1.0 - saturate(abs(dt)));
    float new_luma    = saturate(zone_median + bent);


    // R29: Multi-Scale Retinex — pixel-local illumination/reflectance separation
    float r18_str  = lerp(10.0, 30.0, smoothstep(0.08, 0.25, zone_std)) / 100.0 * 0.4;
    float illum_s0 = max(tex2D(CreativeLowFreqSamp, uv).a, 0.001);
    float illum_s1 = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).a, 0.001);
    float illum_s2 = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).a, 0.001);
    float luma_s   = max(new_luma, 0.001);
    float log_R    = 0.20 * log(luma_s / illum_s0)
                   + 0.30 * log(luma_s / illum_s1)
                   + 0.50 * log(luma_s / illum_s2);
    float retinex_luma = saturate(exp(log_R + log(max(zone_log_key, 0.001))));
    new_luma = lerp(new_luma, retinex_luma, smoothstep(0.04, 0.25, zone_std));

    float D1              = luma - illum_s0;
    float D2              = illum_s0 - illum_s1;
    float D3              = illum_s1 - illum_s2;
    float detail          = D1 * 0.50 + D2 * 0.30 + D3 * 0.20;
    float clarity_mask    = smoothstep(0.0, 0.2, luma) * (1.0 - smoothstep(0.6, 0.9, luma));
    float bell            = 1.0 / (1.0 + detail * detail / 0.0144);
    new_luma = saturate(new_luma + detail * (CLARITY_STRENGTH / 100.0) * bell * clarity_mask);

    float shadow_lift = lerp(20.0, 5.0, smoothstep(0.04, 0.28, perc.r));
    float lift_w      = new_luma * smoothstep(0.4, 0.0, new_luma);
    new_luma          = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w);
    lin          = saturate(lin * (new_luma / max(luma, 0.001)));
    lin = lerp(lin_pre_tonal, lin, TONAL_STRENGTH / 100.0);

    // ── 3. CHROMA: Oklab chroma lift ──────────────────────────────────────────
    float3 lab = RGBtoOklab(lin);
    float  C   = length(lab.yz);
    float  h   = OklabHueNorm(lab.y, lab.z);

    // R22: saturation by luminance — baked Munsell calibration (shadow 20%, highlight 25%)
    C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)
                      - 0.25 * saturate((lab.x - 0.75) / 0.25));

    // R21: per-band hue rotation — compute h_out from original h before chroma lift
    float r21_delta = ROT_RED    * HueBandWeight(h, BAND_RED)
                    + ROT_YELLOW * HueBandWeight(h, BAND_YELLOW)
                    + ROT_GREEN  * HueBandWeight(h, BAND_GREEN)
                    + ROT_CYAN   * HueBandWeight(h, BAND_CYAN)
                    + ROT_BLUE   * HueBandWeight(h, BAND_BLUE)
                    + ROT_MAG    * HueBandWeight(h, BAND_MAGENTA);
    float h_out = frac(h + r21_delta * 0.10);

    float la         = max(perc.g, 0.001);
    float k          = 1.0 / (5.0 * la + 1.0);
    float k4         = k * k * k * k;
    float fl         = 0.2 * k4 * (5.0 * la) + 0.1 * (1.0 - k4) * (1.0 - k4) * pow(5.0 * la, 0.333);
    float hunt_scale = pow(max(fl, 1e-6), 0.25) / 0.5912;

    // R36: mean_chroma → adaptive chroma and density strengths
    float cm_t = 0.0, cm_w = 0.0;
    [unroll] for (int bi = 0; bi < 6; bi++)
    {
        float4 bs = tex2D(ChromaHistory, float2((bi + 0.5) / 8.0, 0.5 / 4.0));
        cm_t += bs.r * bs.b;
        cm_w += bs.b;
    }
    float mean_chroma  = cm_t / max(cm_w, 0.001);
    float chroma_adapt = smoothstep(0.05, 0.20, mean_chroma);
    float chroma_str   = saturate(lerp(55.0, 30.0, chroma_adapt) / 100.0 * hunt_scale);
    float density_str  = lerp(35.0, 52.0, chroma_adapt);

    float new_C = 0.0, total_w = 0.0, green_w = 0.0;
    [unroll] for (int band = 0; band < 6; band++)
    {
        float w     = HueBandWeight(h, GetBandCenter(band));
        float4 hist = tex2D(ChromaHistory, float2((band + 0.5) / 8.0, 0.5 / 4.0));
        new_C   += PivotedSCurve(C, hist.r, chroma_str) * w;
        total_w += w;
        if (band == 2) green_w = w;
    }
    // max(lifted, C) — lift-only; identity limit at C = 0 by construction
    float lifted_C = (total_w > 0.001) ? new_C / total_w : C;
    float final_C  = max(lifted_C, C) * (1.0 + abs(detail) * (CLARITY_STRENGTH / 100.0) * 0.25);

    // Vector-space (a,b) reconstruction — rotate original direction by R21 delta
    float r21_cos, r21_sin;
    sincos(r21_delta * (0.10 * 6.28318), r21_sin, r21_cos);
    float2 ab_in  = float2(lab.y * r21_cos - lab.z * r21_sin,
                           lab.y * r21_sin + lab.z * r21_cos);
    float  C_safe = max(C, 1e-6);
    float2 ab_s   = ab_in * (final_C / C_safe);

    float abney  = (+HueBandWeight(h_out, BAND_RED)     * 0.06
                   + HueBandWeight(h_out, BAND_YELLOW)  * 0.05
                   - HueBandWeight(h_out, BAND_CYAN)    * 0.08
                   - HueBandWeight(h_out, BAND_BLUE)    * 0.04
                   - HueBandWeight(h_out, BAND_MAGENTA) * 0.03) * final_C;
    float dtheta = -(GREEN_HUE_COOL * 2.0 * 3.14159265) * green_w * final_C + abney;
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
    float  rmax_probe = max(rgb_probe.r, max(rgb_probe.g, rgb_probe.b));
    float  headroom   = saturate(1.0 - rmax_probe);
    float  delta_C    = max(final_C - C, 0.0);
    float  density_L  = saturate(final_L - delta_C * headroom * (density_str / 100.0));

    float3 chroma_rgb = OklabToRGB(float3(density_L, f_oka, f_okb));
    float  rmax       = max(chroma_rgb.r, max(chroma_rgb.g, chroma_rgb.b));
    float  L_grey     = density_L * density_L * density_L;
    float  gclip      = saturate((1.0 - L_grey) / max(rmax - L_grey, 0.001));
    chroma_rgb        = L_grey + gclip * (chroma_rgb - L_grey);
    lin = saturate(chroma_rgb);

    float4 pixel = float4(lin, col.a);
    return DrawLabel(pixel, pos.xy, 270.0, 50.0,
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
