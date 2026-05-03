// inverse_grade_aces.fx — R86 Scene Reconstruction prototype
//
// Analytical ACES inversion + per-hue distortion correction.
// Blend strength controlled by ACES_BLEND in creative_values.fx.
//
// NOTE: confidence-gated version shelved — PercTex sharing broken between
// new effects and the existing analysis_frame/grade chain in vkBasalt.
// Restore ACESConfidence when sharing is understood.

#include "creative_values.fx"

// ─── Shared textures ───────────────────────────────────────────────────────

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
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

// ─── Hue band constants (match grade.fx R21 system) ───────────────────────

#define BAND_RED        0.083
#define BAND_YELLOW     0.305
#define BAND_GREEN      0.396
#define BAND_CYAN       0.542
#define BAND_BLUE       0.735
#define BAND_MAGENTA    0.913
#define BAND_WIDTH      8

// ─── Oklab helpers (copied verbatim from grade.fx) ─────────────────────────

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

// ─── R86 Angle 0: ACESInverse ──────────────────────────────────────────────
// Input y in [0,1] (display-referred). Output x in [0,∞) (scene-linear).
// Solves (2.43y−2.51)x² + (0.59y−0.03)x + 0.14y = 0 for positive root.

float ACESInverse(float y)
{
    float qa = 2.43 * y - 2.51;
    float qb = 0.59 * y - 0.03;
    float qc = 0.14 * y;
    float disc = max(qb * qb - 4.0 * qa * qc, 0.0);
    return (-qb - sqrt(disc)) / (2.0 * qa);
}

float3 ACESInverse3(float3 rgb)
{
    return float3(ACESInverse(rgb.r), ACESInverse(rgb.g), ACESInverse(rgb.b));
}

// Highway positions (written by analysis_frame DebugOverlayPS each frame)
#define PERC_X_P25  194
#define PERC_X_P50  195
#define PERC_X_P75  196

float ACESConfidence(float p25, float p50, float p75)
{
    float mid_score    = smoothstep(0.10, 0.22, p50) * smoothstep(0.72, 0.58, p50);
    float spread_score = smoothstep(0.01, 0.08, max(p75 - p25, 0.0));
    return saturate(mid_score * 0.70 + spread_score * 0.30);
}

// ─── R86 Angle 1: ACESHueCorrection ────────────────────────────────────────
// Undo per-channel shoulder compression hue errors. Analytical estimates,
// expect ±25% error — tune empirically against reference footage.

#define ACES_CORR_RED     (-0.15)  // undo red→orange push   (~−5.4°)
#define ACES_CORR_YELLOW  ( 0.00)  // yellow: chroma collapse, not hue rotation
#define ACES_CORR_GREEN   ( 0.00)  // green: sub-threshold
#define ACES_CORR_CYAN    (-0.20)  // undo cyan→blue shift    (~−7.2°)
#define ACES_CORR_BLUE    (-0.10)  // undo blue→purple bleed  (~−3.6°)
#define ACES_CORR_MAG     ( 0.00)  // magenta: sub-threshold

float3 ACESHueCorrection(float3 scene_norm)
{
    float3 lab = RGBtoOklab(scene_norm);
    float  C   = length(lab.yz);
    if (C < 0.005) return scene_norm;

    float h = OklabHueNorm(lab.y, lab.z);
    float delta = ACES_CORR_RED    * HueBandWeight(h, BAND_RED)
                + ACES_CORR_YELLOW * HueBandWeight(h, BAND_YELLOW)
                + ACES_CORR_GREEN  * HueBandWeight(h, BAND_GREEN)
                + ACES_CORR_CYAN   * HueBandWeight(h, BAND_CYAN)
                + ACES_CORR_BLUE   * HueBandWeight(h, BAND_BLUE)
                + ACES_CORR_MAG    * HueBandWeight(h, BAND_MAGENTA);

    float h_out = frac(h + delta * 0.10);
    float sh, ch;
    sincos(h_out * 6.28318, sh, ch);
    lab.y = C * ch;
    lab.z = C * sh;
    return saturate(OklabToRGB(lab));
}

// ─── Main pass ─────────────────────────────────────────────────────────────

float4 ACESInversePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;
    if (ACES_BLEND <= 0.0) return col;

    float p25 = tex2D(BackBuffer, float2((PERC_X_P25 + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT)).r;
    float p50 = tex2D(BackBuffer, float2((PERC_X_P50 + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT)).r;
    float p75 = tex2D(BackBuffer, float2((PERC_X_P75 + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT)).r;

    float aces_conf  = ACESConfidence(p25, p50, p75);
    float scene_ceil = max(ACESInverse(p75), 1.0);

    float3 scene_norm = saturate(ACESInverse3(col.rgb) / scene_ceil);
    scene_norm = ACESHueCorrection(scene_norm);

    col.rgb = lerp(col.rgb, scene_norm, float(ACES_BLEND) * aces_conf);
    return col;
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique OlofssonianACESInverse
{
    pass ACESInvPass
    {
        VertexShader = PostProcessVS;
        PixelShader  = ACESInversePS;
    }
}
