// olofssonian_color_grade.fx — Camera/film color grade (creative)
//
// Operates on linear input. Internally converts to gamma for grading,
// then back to linear before blending. All preset values are in gamma space.
//
// Set PRESET to select film stock:
//   1 = ARRI ALEXA         — clean, neutral, wide latitude
//   2 = Kodak Vision3 500T — warm, filmic, golden highlights
//   3 = Sony Venice        — warm neutral, slight character, protected mids
//   4 = Fuji Eterna 500    — cool, flat, green-leaning mids
//   5 = Kodak 5219         — punchy, pushed, deep warm blacks

#include "creative_values.fx"

// ─── Tinting ranges ────────────────────────────────────────────────────────
#define TOE_RANGE       30      // 0–100; luma range for toe tint
#define SHADOW_RANGE    18      // 0–100; luma range for shadow tint
#define HIGHLIGHT_START 65      // 0–100; luma above this gets highlight tint

// ─── Preset values ─────────────────────────────────────────────────────────
//
// SAT_ROLLOFF_FACTOR — luminance exponent for highlight desaturation
//                      low (2) = aggressive (Kodak creamy), high (8) = subtle (Fuji vivid)
// SAT_ROLLOFF_MAX    — max blend toward grey at peak (0.0 = off)
// HUE_SHIFT_CENTER   — hue to rotate (0–1 hue wheel)
// HUE_SHIFT_AMOUNT   — signed rotation amount (0.0 = off)
// HUE_SHIFT_WIDTH    — half-width of affected hue range

#if PRESET == 0  // Soft base — no hard blacks/whites, neutral character
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

#elif PRESET == 1  // ARRI ALEXA — clean, neutral, wide latitude
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

#elif PRESET == 2  // Kodak Vision3 500T — warm, filmic, golden highlights
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

#elif PRESET == 3  // Sony Venice — warm neutral, slight character, protected mids
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

#elif PRESET == 4  // Fuji Eterna 500 — cool, flat, green-leaning mids
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

#elif PRESET == 5  // Kodak 5219 — punchy, pushed, deep warm blacks
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
sampler2D BackBuffer { Texture = BackBufferTex; };

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

// 12-stop log encode/decode — 0.18 grey maps to 0.5
float3 LogEncode(float3 x)
{
    return log2(max(x, 0.0001) / 0.18) / 12.0 + 0.5;
}
float3 LogDecode(float3 x)
{
    return max(0.18 * exp2((x - 0.5) * 12.0), 0.0);
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

// ─── Pixel shader ──────────────────────────────────────────────────────────

float4 ColorGradePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;  // data highway

    float3 lin = max(col.rgb, 0.0);

    // ── 1. Film matrix in log space (simulates dye interlayer cross-talk) ──
    float3 log_in = LogEncode(lin);
    float3 film_log;
    film_log.r = log_in.r * (1.0 - FILM_RG - FILM_RB) + log_in.g * FILM_RG + log_in.b * FILM_RB;
    film_log.g = log_in.r * FILM_GR + log_in.g * (1.0 - FILM_GR - FILM_GB) + log_in.b * FILM_GB;
    film_log.b = log_in.r * FILM_BR + log_in.g * FILM_BG + log_in.b * (1.0 - FILM_BR - FILM_BG);

    float fm_luma   = Luma(lin);
    float fm_max    = max(lin.r, max(lin.g, lin.b));
    float fm_min    = min(lin.r, min(lin.g, lin.b));
    float fm_chroma = (fm_max > 0.001) ? (fm_max - fm_min) / fm_max : 0.0;
    float fm_gate   = smoothstep(FILM_CHROMA_LO, FILM_CHROMA_HI, fm_chroma)
                    * smoothstep(FILM_LUMA_LO, FILM_LUMA_HI, fm_luma);
    float3 film_lin = LogDecode(lerp(log_in, film_log, fm_gate));

    // ── 2. Zone tinting in gamma space ─────────────────────────────────────
    float3 result = pow(max(film_lin, 0.0), 1.0 / 2.2);
    float  result_luma = Luma(result);

    // Toe tint — bell curve peaks mid-shadow, saturation-gated
    float tint_base = 1.0 - smoothstep(0.0, TOE_RANGE / 100.0, result_luma);
    float toe_bell  = tint_base * (1.0 - tint_base) * 4.0;
    float tt_max    = max(result.r, max(result.g, result.b));
    float tt_min    = min(result.r, min(result.g, result.b));
    float tt_sat    = (tt_max > 0.001) ? (tt_max - tt_min) / tt_max : 0.0;
    float tt_gate   = smoothstep(0.14, 0.27, tt_sat);
    result.r += TOE_TINT_R * toe_bell * tt_gate;
    result.g += TOE_TINT_G * toe_bell * tt_gate;
    result.b += TOE_TINT_B * toe_bell * tt_gate;

    // Black lift
    float black_w = 1.0 - smoothstep(0.0, 0.10, result_luma);
    result.r += BLACK_LIFT_R * black_w;
    result.g += BLACK_LIFT_G * black_w;
    result.b += BLACK_LIFT_B * black_w;

    // Shadow tint — saturation-gated
    float st_max  = max(result.r, max(result.g, result.b));
    float st_min  = min(result.r, min(result.g, result.b));
    float st_sat  = (st_max > 0.001) ? (st_max - st_min) / st_max : 0.0;
    float st_gate = smoothstep(0.08, 0.22, st_sat);
    float shadow_w = result_luma * (1.0 - smoothstep(0.0, SHADOW_RANGE / 100.0, result_luma)) * st_gate;
    result += float3(SHADOW_TINT_R, SHADOW_TINT_G, SHADOW_TINT_B) * shadow_w;

    // Highlight lift
    float hl_t        = smoothstep(HIGHLIGHT_START / 100.0, 1.0, result_luma);
    float highlight_w = hl_t * hl_t * (1.0 - result_luma) / max(1.0 - HIGHLIGHT_START / 100.0, 0.001);
    result.r += HIGHLIGHT_TINT_R * highlight_w;
    result.g += HIGHLIGHT_TINT_G * highlight_w;
    result.b += HIGHLIGHT_TINT_B * highlight_w;

    // Luma-neutral midtone cast
    float luma_pre = Luma(result);
    result.r *= GRADE_R;
    result.g *= GRADE_G;
    result.b *= GRADE_B;
    result   *= luma_pre / max(Luma(result), 0.001);

    // White point
    float3 white = float3(WHITE_R, WHITE_G, WHITE_B);
    result += (white - 1.0) * result * result;

    // ── 3. Per-hue rotation — chroma-weighted, mimics dye gamut compression ─
    {
        float3 hsv     = RGBtoHSV(result);
        float hue_dist = abs(hsv.x - HUE_SHIFT_CENTER);
        hue_dist       = min(hue_dist, 1.0 - hue_dist);
        float hue_w    = smoothstep(HUE_SHIFT_WIDTH, 0.0, hue_dist) * hsv.y;
        hsv.x          = frac(hsv.x + HUE_SHIFT_AMOUNT * hue_w);
        result         = HSVtoRGB(hsv);
    }

    // ── 4. Luminance-dependent saturation roll-off ──────────────────────────
    {
        float rl      = Luma(result);
        float rolloff = pow(max(rl, 0.0), SAT_ROLLOFF_FACTOR);
        result        = lerp(result, float3(rl, rl, rl), rolloff * SAT_ROLLOFF_MAX);
    }

    // ── 5. Back to linear + creative adjustments ───────────────────────────
    result = pow(max(result, 0.0), 2.2);

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
        float cc_new  = lerp(cc_luma, cc_s, CREATIVE_CONTRAST - 1.0);
        result = saturate(result * (cc_new / max(cc_luma, 0.001)));
    }

    // Blend toward original by GRADE_STRENGTH
    result = lerp(col.rgb, result, GRADE_STRENGTH / 100.0);

    // Debug indicator — blue (color grade slot)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 57) && pos.x < float(BUFFER_WIDTH - 45))
        return float4(0.2, 0.2, 0.9, 1.0);

    return float4(saturate(result), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique OlofssonianColorGrade
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = ColorGradePS;
    }
}
