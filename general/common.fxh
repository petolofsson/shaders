// common.fxh — Shared vertex shader, color space utilities, and texture highway
// Included by all effect files in this pipeline.
// Edit here; do not copy these functions into individual effect files.

// ─── Texture Highway ────────────────────────────────────────────────────────
// TexHwyTex (BUFFER_WIDTH/8 × BUFFER_HEIGHT/8+TEX_HWY_ROWS, RGBA16F):
//   Rows 0..BUFFER_HEIGHT/8-1  : spatial lane  r=R g=G b=B a=Luma  written by analysis_frame
//   Data row +0 pixel 0        : p25/p50/p75/Kalman_P               written by analysis_frame
//   Data row +0 pixel 1        : p90/p10/p75_C/kappa                written by analysis_frame
//   Data row +0 pixel 2        : median_C/mean_a/mean_b/achrom_frac written by analysis_frame
//   Data row +0 pixel 3        : scene_cut/p50_prev/mode/entropy    written by analysis_frame
//   Data row +0 pixel 4        : NeutralIllum RGB (one-frame delay) written by grade
//   Data rows +1..+4 cols 0..7 : ChromaHistoryTex 8×4               written by corrective
//
// Pass-through: each effect's TexHwyWritePS copies unowned pixels from TexHwyTex.
// Same mechanism as HighwayWritePS / HighwayTex in highway.fxh.

#define TEX_HWY_ROWS      5
#define TEX_HWY_SPATIAL_H (BUFFER_HEIGHT / 8)
#define TEX_HWY_TOTAL_H   (BUFFER_HEIGHT / 8 + TEX_HWY_ROWS)

texture2D TexHwyTex
{
    Width     = BUFFER_WIDTH / 8;
    Height    = BUFFER_HEIGHT / 8 + TEX_HWY_ROWS;
    Format    = RGBA16F;
    MipLevels = 1;
};
sampler2D TexHwySamp
{
    Texture   = TexHwyTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Read spatial lane luma at full-screen UV uv∈[0,1].
float ZoneLuma(float2 uv)
{
    float sy = uv.y * float(TEX_HWY_SPATIAL_H) / float(TEX_HWY_TOTAL_H);
    return tex2Dlod(TexHwySamp, float4(uv.x, sy, 0, 0)).a;
}

// Read data row pixel. dr = row offset from spatial lane base (0..TEX_HWY_ROWS-1).
float4 ReadTexHwyData(int dr, int col)
{
    float u = (float(col) + 0.5) * (8.0 / float(BUFFER_WIDTH));
    float v = (float(TEX_HWY_SPATIAL_H + dr) + 0.5) / float(TEX_HWY_TOTAL_H);
    return tex2Dlod(TexHwySamp, float4(u, v, 0, 0));
}

float4 ReadTexHwyPerc()       { return ReadTexHwyData(0, 0); }  // p25/p50/p75/P
float4 ReadTexHwyPercHigh()   { return ReadTexHwyData(0, 1); }  // p90/p10/p75_C/kappa
float4 ReadTexHwyMeanChroma() { return ReadTexHwyData(0, 2); }  // median_C/mean_a/mean_b/achrom_frac
float4 ReadTexHwySceneCut()   { return ReadTexHwyData(0, 3); }  // scene_cut/p50_prev/mode/entropy
float4 ReadTexHwyIlluminant() { return ReadTexHwyData(0, 4); }  // NeutralIllum RGB (grade, prev frame)
// ChromaHistory row r (0..3), col c (0..7) → data rows 1..4
float4 ReadTexHwyChroma(int r, int c) { return ReadTexHwyData(1 + r, c); }

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float3 RGBtoOklab(float3 rgb)
{
    rgb = saturate(rgb);
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

// Adaptive zone gates — shadow/highlight relative to scene key (Oklab L).
// key_L = cbrt(slow_key) from SceneCtx, clamped [0.30, 0.80].
// Shadow: fixed offsets below/above key_L. At key_L≈0.563: fades 0.46→0.60.
// Highlight: headroom-proportional (key_L + fraction of [key_L,1.0]) so the zone
// stays alive in bright scenes. At key_L≈0.563: fades 0.78→0.93 (same as before).
float ZoneShadowW(float L, float key_L)
{
    return 1.0 - smoothstep(key_L - 0.10, key_L + 0.04, L);
}
float ZoneHighlightW(float L, float key_L)
{
    float head = 1.0 - key_L;
    return smoothstep(key_L + head * 0.50, key_L + head * 0.85, L);
}
float ZoneMidW(float L, float key_L)
{
    return max(0.0, 1.0 - ZoneShadowW(L, key_L) - ZoneHighlightW(L, key_L));
}

// CAT16 sRGB→LMS illuminant warmth. Input: unnormalised linear sRGB.
// Returns warmth proxy: D65≈0.39, warm scene >0.39, cool scene <0.39.
float IllumWarm(float3 rgb)
{
    float3 n = rgb / max(Luma(rgb), 0.001);
    float L  = dot(n, float3(0.302825, 0.602279, 0.070428));
    float M  = dot(n, float3(0.153818, 0.777214, 0.085341));
    float S  = dot(n, float3(0.027974, 0.147911, 0.908874));
    return saturate((L - S) / max(M, 0.001) + 0.5);
}


