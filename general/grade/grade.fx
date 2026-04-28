// creative_color_grade.fx — Mega-pass: all downstream color work in one full-res pass
#include "debug_text.fxh"
//
// Eliminates 3 inter-pass VRAM read-write cycles by running in registers:
//   1. EXPOSURE gamma + scene-adaptive FilmCurve  (was corrective_render_chain P2)
//   2. Zone contrast S-curve + Clarity + Shadow lift  (was creative_render_chain P5)
//   3. Oklab chroma lift + Hunt + Abney + HK + density + gamut compress  (was chroma_lift P2)
//   4. Film stock grade — log matrix + zone tints + sat rolloff
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

// ─── Tinting ranges ────────────────────────────────────────────────────────
#define TOE_RANGE       30
#define SHADOW_RANGE    18
#define HIGHLIGHT_START 65

// ─── Preset values ─────────────────────────────────────────────────────────
#if PRESET == 0
#define WHITE_R          0.993
#define WHITE_G          0.993
#define WHITE_B          0.993
#define FILM_RG          0.0
#define FILM_RB          0.0
#define FILM_GR          0.0
#define FILM_GB          0.0
#define FILM_BR          0.0
#define FILM_BG          0.0
#define TOE_TINT_R       0.0
#define TOE_TINT_G       0.0
#define TOE_TINT_B       0.0
#define BLACK_LIFT_R     0.003
#define BLACK_LIFT_G     0.003
#define BLACK_LIFT_B     0.003
#define SHADOW_TINT_R    0.0
#define SHADOW_TINT_G    0.0
#define SHADOW_TINT_B    0.0
#define HIGHLIGHT_TINT_R 0.0
#define HIGHLIGHT_TINT_G 0.0
#define HIGHLIGHT_TINT_B 0.0
#define GRADE_R          1.0
#define GRADE_G          1.0
#define GRADE_B          1.0
#define SAT_ROLLOFF_FACTOR 6.0
#define SAT_ROLLOFF_MAX    0.25
#define HUE_SHIFT_CENTER   0.5
#define HUE_SHIFT_AMOUNT   0.0
#define HUE_SHIFT_WIDTH    0.1

#elif PRESET == 1
#define WHITE_R          0.99
#define WHITE_G          0.98
#define WHITE_B          0.98
#define FILM_RG          0.018
#define FILM_RB          0.005
#define FILM_GR          0.010
#define FILM_GB          0.015
#define FILM_BR          0.005
#define FILM_BG          0.018
#define TOE_TINT_R      -0.008
#define TOE_TINT_G      -0.004
#define TOE_TINT_B       0.008
#define BLACK_LIFT_R     0.004
#define BLACK_LIFT_G     0.008
#define BLACK_LIFT_B     0.012
#define SHADOW_TINT_R    0.002
#define SHADOW_TINT_G    0.003
#define SHADOW_TINT_B    0.015
#define HIGHLIGHT_TINT_R 0.04
#define HIGHLIGHT_TINT_G 0.02
#define HIGHLIGHT_TINT_B -0.02
#define GRADE_R          1.00
#define GRADE_G          1.00
#define GRADE_B          1.00
#define SAT_ROLLOFF_FACTOR 4.0
#define SAT_ROLLOFF_MAX    0.5
#define HUE_SHIFT_CENTER   0.5
#define HUE_SHIFT_AMOUNT   0.0
#define HUE_SHIFT_WIDTH    0.1

#elif PRESET == 2
#define WHITE_R          0.97
#define WHITE_G          0.95
#define WHITE_B          0.93
#define FILM_RG          0.057
#define FILM_RB          0.013
#define FILM_GR          0.031
#define FILM_GB          0.043
#define FILM_BR          0.013
#define FILM_BG          0.040
#define TOE_TINT_R      -0.028
#define TOE_TINT_G      -0.014
#define TOE_TINT_B       0.020
#define BLACK_LIFT_R     0.008
#define BLACK_LIFT_G     0.025
#define BLACK_LIFT_B     0.035
#define SHADOW_TINT_R    0.005
#define SHADOW_TINT_G    0.008
#define SHADOW_TINT_B    0.050
#define HIGHLIGHT_TINT_R 0.18
#define HIGHLIGHT_TINT_G 0.06
#define HIGHLIGHT_TINT_B -0.08
#define GRADE_R          0.996
#define GRADE_G          1.015
#define GRADE_B          1.00
#define SAT_ROLLOFF_FACTOR 2.0
#define SAT_ROLLOFF_MAX    0.5
#define HUE_SHIFT_CENTER   0.667
#define HUE_SHIFT_AMOUNT  -0.025
#define HUE_SHIFT_WIDTH    0.15

#elif PRESET == 3
#define WHITE_R          0.97
#define WHITE_G          0.96
#define WHITE_B          0.95
#define FILM_RG          0.038
#define FILM_RB          0.009
#define FILM_GR          0.020
#define FILM_GB          0.028
#define FILM_BR          0.009
#define FILM_BG          0.032
#define TOE_TINT_R      -0.015
#define TOE_TINT_G      -0.008
#define TOE_TINT_B       0.015
#define BLACK_LIFT_R     0.005
#define BLACK_LIFT_G     0.015
#define BLACK_LIFT_B     0.022
#define SHADOW_TINT_R    0.003
#define SHADOW_TINT_G    0.005
#define SHADOW_TINT_B    0.030
#define HIGHLIGHT_TINT_R 0.12
#define HIGHLIGHT_TINT_G 0.05
#define HIGHLIGHT_TINT_B -0.06
#define GRADE_R          0.998
#define GRADE_G          1.008
#define GRADE_B          1.00
#define SAT_ROLLOFF_FACTOR 3.0
#define SAT_ROLLOFF_MAX    0.5
#define HUE_SHIFT_CENTER   0.167
#define HUE_SHIFT_AMOUNT   0.015
#define HUE_SHIFT_WIDTH    0.12

#elif PRESET == 4
#define WHITE_R          0.96
#define WHITE_G          0.96
#define WHITE_B          0.95
#define FILM_RG          0.030
#define FILM_RB          0.010
#define FILM_GR          0.018
#define FILM_GB          0.055
#define FILM_BR          0.015
#define FILM_BG          0.075
#define TOE_TINT_R      -0.008
#define TOE_TINT_G       0.005
#define TOE_TINT_B       0.018
#define BLACK_LIFT_R     0.004
#define BLACK_LIFT_G     0.018
#define BLACK_LIFT_B     0.018
#define SHADOW_TINT_R    0.002
#define SHADOW_TINT_G    0.010
#define SHADOW_TINT_B    0.035
#define HIGHLIGHT_TINT_R 0.02
#define HIGHLIGHT_TINT_G 0.04
#define HIGHLIGHT_TINT_B -0.05
#define GRADE_R          0.993
#define GRADE_G          1.012
#define GRADE_B          1.005
#define SAT_ROLLOFF_FACTOR 8.0
#define SAT_ROLLOFF_MAX    0.5
#define HUE_SHIFT_CENTER   0.0
#define HUE_SHIFT_AMOUNT   0.055
#define HUE_SHIFT_WIDTH    0.12

#elif PRESET == 5
#define WHITE_R          0.97
#define WHITE_G          0.94
#define WHITE_B          0.91
#define FILM_RG          0.070
#define FILM_RB          0.016
#define FILM_GR          0.038
#define FILM_GB          0.050
#define FILM_BR          0.016
#define FILM_BG          0.080
#define TOE_TINT_R      -0.040
#define TOE_TINT_G      -0.020
#define TOE_TINT_B       0.030
#define BLACK_LIFT_R     0.012
#define BLACK_LIFT_G     0.030
#define BLACK_LIFT_B     0.045
#define SHADOW_TINT_R    0.008
#define SHADOW_TINT_G    0.010
#define SHADOW_TINT_B    0.065
#define HIGHLIGHT_TINT_R 0.24
#define HIGHLIGHT_TINT_G 0.08
#define HIGHLIGHT_TINT_B -0.12
#define GRADE_R          0.993
#define GRADE_G          1.018
#define GRADE_B          1.00
#define SAT_ROLLOFF_FACTOR 1.5
#define SAT_ROLLOFF_MAX    0.5
#define HUE_SHIFT_CENTER   0.667
#define HUE_SHIFT_AMOUNT  -0.035
#define HUE_SHIFT_WIDTH    0.18
#endif

// ─── Film matrix gate ──────────────────────────────────────────────────────
#define FILM_CHROMA_LO  0.08
#define FILM_CHROMA_HI  0.18
#define FILM_LUMA_LO    0.05
#define FILM_LUMA_HI    0.90

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

float3 FilmCurve(float3 x, float p25, float p50, float p75)
{
    float knee    = lerp(0.90, 0.80, saturate((p75 - 0.60) / 0.30));
    float width   = 1.0 - knee;
    float stevens = (1.48 + sqrt(max(p50, 0.0))) / 2.03;
    float factor  = 0.05 / (width * width) * stevens;
    float knee_toe = lerp(0.15, 0.25, saturate((0.40 - p25) / 0.30));
    float3 above = max(x - knee,      0.0);
    float3 below = max(knee_toe - x,  0.0);
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

float3 RGBtoHSV(float3 c)
{
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float  d = q.x - min(q.w, q.y);
    float  e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 HSVtoRGB(float3 c)
{
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

float3 LogEncode(float3 x) { return log2(max(x, 0.0001) / 0.18) / 12.0 + 0.5; }
float3 LogDecode(float3 x) { return max(0.18 * exp2((x - 0.5) * 12.0), 0.0); }

// ─── ColorTransform pixel shader ───────────────────────────────────────────

float4 ColorTransformPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;  // data highway

    float4 perc = tex2D(PercSamp, float2(0.5, 0.5));

    // ── 1. CORRECTIVE: EXPOSURE + FilmCurve ──────────────────────────────────
    float3 lin = FilmCurve(pow(max(col.rgb, 0.0), EXPOSURE), perc.r, perc.g, perc.b);
    lin = lerp(col.rgb, lin, CORRECTIVE_STRENGTH / 100.0);

    // ── 2. TONAL: Zone contrast + Clarity + Shadow lift ───────────────────────
    float3 lin_pre_tonal = lin;
    float luma        = Luma(lin);
    float4 zone_lvl   = tex2D(ZoneHistorySamp, uv);
    float zone_median = zone_lvl.r;
    float zone_iqr    = zone_lvl.b - zone_lvl.g;
    float iqr_scale   = smoothstep(0.0, 0.25, zone_iqr);
    float dt          = luma - zone_median;
    float bent        = dt + (ZONE_STRENGTH / 100.0) * iqr_scale * dt * (1.0 - saturate(abs(dt)));
    float new_luma    = saturate(zone_median + bent);

    float low_luma_fine   = tex2D(CreativeLowFreqSamp, uv).a;
    float low_luma_coarse = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).a;
    float detail          = lerp(luma - low_luma_fine, low_luma_fine - low_luma_coarse, 0.6);
    float clarity_mask    = smoothstep(0.0, 0.2, luma) * (1.0 - smoothstep(0.6, 0.9, luma));
    float bell            = 1.0 / (1.0 + detail * detail / 0.0144);
    new_luma = saturate(new_luma + detail * (CLARITY_STRENGTH / 100.0) * bell * clarity_mask);

    float lift_w = new_luma * smoothstep(0.4, 0.0, new_luma);
    new_luma     = saturate(new_luma + (SHADOW_LIFT / 100.0) * 0.75 * lift_w);
    lin          = saturate(lin * (new_luma / max(luma, 0.001)));
    lin = lerp(lin_pre_tonal, lin, TONAL_STRENGTH / 100.0);

    // ── 3. CHROMA: Oklab chroma lift ──────────────────────────────────────────
    float3 lab = RGBtoOklab(lin);
    float  C   = length(lab.yz);
    float  h   = OklabHueNorm(lab.y, lab.z);

    float la         = max(perc.g, 0.001);
    float k          = 1.0 / (5.0 * la + 1.0);
    float k4         = k * k * k * k;
    float fl         = 0.2 * k4 * (5.0 * la) + 0.1 * (1.0 - k4) * (1.0 - k4) * pow(5.0 * la, 0.333);
    float hunt_scale = pow(max(fl, 1e-6), 0.25) / 0.5912;
    float chroma_str = saturate(CHROMA_STRENGTH / 100.0 * hunt_scale);

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

    // Vector-space (a,b) reconstruction — no atan2 needed for output direction
    float2 ab_in  = float2(lab.y, lab.z);
    float  C_safe = max(C, 1e-6);
    float2 ab_s   = ab_in * (final_C / C_safe);

    float abney  = (+HueBandWeight(h, BAND_RED)     * 0.06
                   + HueBandWeight(h, BAND_YELLOW)  * 0.05
                   - HueBandWeight(h, BAND_CYAN)    * 0.08
                   - HueBandWeight(h, BAND_BLUE)    * 0.04
                   - HueBandWeight(h, BAND_MAGENTA) * 0.03) * final_C;
    float dtheta = -(GREEN_HUE_COOL * 2.0 * 3.14159265) * green_w * final_C + abney;
    float cos_dt = 1.0 - dtheta * dtheta * 0.5;
    float sin_dt = dtheta;
    float f_oka  = ab_s.x * cos_dt - ab_s.y * sin_dt;
    float f_okb  = ab_s.x * sin_dt + ab_s.y * cos_dt;

    // Hellwig 2022: hue-dependent H-K correction, C^0.587 (R15)
    float sh, ch;
    sincos(h * 6.28318, sh, ch);
    float f_hk     = -0.160 * ch + 0.132 * (ch*ch - sh*sh) - 0.405 * sh + 0.080 * (2.0*sh*ch) + 0.792;
    float hk_boost = 1.0 + (HK_STRENGTH / 100.0) * f_hk * pow(final_C, 0.587);
    float final_L  = saturate(lab.x / lerp(1.0, hk_boost, smoothstep(0.0, 0.35, lab.x)));

    // Gamut-distance density: headroom limits darkening near the sRGB boundary
    float3 rgb_probe  = OklabToRGB(float3(final_L, f_oka, f_okb));
    float  rmax_probe = max(rgb_probe.r, max(rgb_probe.g, rgb_probe.b));
    float  headroom   = saturate(1.0 - rmax_probe);
    float  delta_C    = max(final_C - C, 0.0);
    float  density_L  = saturate(final_L - delta_C * headroom * (DENSITY_STRENGTH / 100.0));

    float3 chroma_rgb = OklabToRGB(float3(density_L, f_oka, f_okb));
    float  rmax       = max(chroma_rgb.r, max(chroma_rgb.g, chroma_rgb.b));
    float  L_grey     = density_L * density_L * density_L;
    float  gclip      = saturate((1.0 - L_grey) / max(rmax - L_grey, 0.001));
    chroma_rgb        = L_grey + gclip * (chroma_rgb - L_grey);
    lin = saturate(chroma_rgb);

    // ── 4. FILM GRADE ─────────────────────────────────────────────────────────
    float3 grade_in = lin;

    float3 log_in = LogEncode(grade_in);
    float3 film_log;
    film_log.r = log_in.r * (1.0 - FILM_RG - FILM_RB) + log_in.g * FILM_RG + log_in.b * FILM_RB;
    film_log.g = log_in.r * FILM_GR + log_in.g * (1.0 - FILM_GR - FILM_GB) + log_in.b * FILM_GB;
    film_log.b = log_in.r * FILM_BR + log_in.g * FILM_BG + log_in.b * (1.0 - FILM_BR - FILM_BG);

    float fm_luma   = Luma(grade_in);
    float fm_max    = max(grade_in.r, max(grade_in.g, grade_in.b));
    float fm_min    = min(grade_in.r, min(grade_in.g, grade_in.b));
    float fm_chroma = (fm_max - fm_min) / max(fm_max, 0.001);
    float fm_gate   = smoothstep(FILM_CHROMA_LO, FILM_CHROMA_HI, fm_chroma)
                    * smoothstep(FILM_LUMA_LO,   FILM_LUMA_HI,   fm_luma);
    float3 film_lin = LogDecode(lerp(log_in, film_log, fm_gate));

    float3 S1 = sqrt(max(film_lin, 0.0));
    float3 S2 = sqrt(S1);
    float3 S3 = sqrt(S2);
    float3 result = saturate(0.662002687 * S1 + 0.684122060 * S2 - 0.323583601 * S3 - 0.0225411470 * film_lin);
    float  result_luma = Luma(result);

    // Toe tint
    float tint_base = 1.0 - smoothstep(0.0, TOE_RANGE / 100.0, result_luma);
    float toe_bell  = tint_base * (1.0 - tint_base) * 4.0;
    float tt_max    = max(result.r, max(result.g, result.b));
    float tt_min    = min(result.r, min(result.g, result.b));
    float tt_sat    = (tt_max > 0.001) ? (tt_max - tt_min) / tt_max : 0.0;
    float tt_gate   = smoothstep(0.14, 0.27, tt_sat);
    result.r += TOE_TINT_R * toe_bell * tt_gate;
    result.g += TOE_TINT_G * toe_bell * tt_gate;
    result.b += TOE_TINT_B * toe_bell * tt_gate;
    result = saturate(result);

    // Black lift
    float black_w = 1.0 - smoothstep(0.0, 0.10, result_luma);
    result += float3(BLACK_LIFT_R, BLACK_LIFT_G, BLACK_LIFT_B) * black_w;
    result = saturate(result);

    // Shadow tint
    float st_max   = max(result.r, max(result.g, result.b));
    float st_min   = min(result.r, min(result.g, result.b));
    float st_sat   = (st_max > 0.001) ? (st_max - st_min) / st_max : 0.0;
    float st_gate  = smoothstep(0.08, 0.22, st_sat);
    float g_shadow = result_luma * (1.0 - smoothstep(0.0, SHADOW_RANGE / 100.0, result_luma)) * st_gate;
    result = saturate(result + float3(SHADOW_TINT_R, SHADOW_TINT_G, SHADOW_TINT_B) * g_shadow);

    // Highlight lift
    float hl_t        = smoothstep(HIGHLIGHT_START / 100.0, 1.0, result_luma);
    float highlight_w = hl_t * hl_t * (1.0 - result_luma) / max(1.0 - HIGHLIGHT_START / 100.0, 0.001);
    result += float3(HIGHLIGHT_TINT_R, HIGHLIGHT_TINT_G, HIGHLIGHT_TINT_B) * highlight_w;
    result = saturate(result);

    // Luma-neutral midtone cast
    float luma_pre = Luma(result);
    result *= float3(GRADE_R, GRADE_G, GRADE_B);
    result *= luma_pre / max(Luma(result), 0.001);

    // White point
    result += (float3(WHITE_R, WHITE_G, WHITE_B) - 1.0) * result * result;

    // Per-hue rotation
    {
        float3 hsv     = RGBtoHSV(result);
        float  hue_dist = abs(hsv.x - HUE_SHIFT_CENTER);
        hue_dist        = min(hue_dist, 1.0 - hue_dist);
        float  hue_w    = smoothstep(HUE_SHIFT_WIDTH, 0.0, hue_dist) * hsv.y;
        hsv.x           = frac(hsv.x + HUE_SHIFT_AMOUNT * hue_w);
        result          = HSVtoRGB(hsv);
    }

    // Luminance-dependent sat rolloff
    {
        float rl      = Luma(result);
        float rolloff = pow(max(rl, 0.0), SAT_ROLLOFF_FACTOR);
        result        = lerp(result, float3(rl, rl, rl), rolloff * SAT_ROLLOFF_MAX);
    }

    result = result * (result * (result * 0.305306011 + 0.682171111) + 0.012522878);

    if (CREATIVE_SATURATION != 1.0)
    {
        float cs_lum = Luma(result);
        result = saturate(cs_lum + (result - cs_lum) * CREATIVE_SATURATION);
    }
    if (CREATIVE_CONTRAST != 1.0)
    {
        float cc_luma = Luma(result);
        float cc_t    = saturate(cc_luma / 0.36);
        float cc_s    = cc_t * cc_t * (3.0 - 2.0 * cc_t) * 0.36;
        result = saturate(result * (lerp(cc_luma, cc_s, CREATIVE_CONTRAST - 1.0) / max(cc_luma, 0.001)));
    }

    result = lerp(grade_in, result, GRADE_STRENGTH / 100.0);

    float4 pixel = float4(saturate(result), col.a);
    return DrawLabel(pixel, pos, float(BUFFER_WIDTH) - 17.0, 44.0,
                     71u, 82u, 65u, 68u, float3(0.2, 0.50, 1.0)); // GRAD
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
