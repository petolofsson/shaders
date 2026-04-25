// olofssonian_render_chain.fx — Corrective chain + display transform (game-agnostic)
//
// Single effect. All passes share CorrectiveBuf (RGBA16F) — no UNORM clamping
// between stages. Full scene-linear range reaches OpenDRT intact.
//
// CORRECTIVE (technical, game-agnostic):
//   Pass  1  WhiteBalance         BackBuffer    → CorrectiveBuf   WB_R/G/B only; no tonal change
//   Pass  2  ComputeLowFreq       CorrectiveBuf → LowFreqTex      1/8 res downsample (shared)
//   Pass  3  IlluminantEstimate   LowFreqTex    → IlluminantTex   Grey Pixel per 4×4 spatial zone
//   Pass  4  ComputeZoneHist      LowFreqTex    → ZoneHistTex     Zone: 32-bin per-zone histogram
//   Pass  5  BuildZoneLevels      ZoneHistTex   → ZoneLevelsTex   Zone: CDF → zone medians
//   Pass  6  CopyBufToSrc         CorrectiveBuf → CorrectiveSrcTex
//   Pass  7  ApplyAdaptation      CorrectiveSrc → CorrectiveBuf   CAT16 per-zone illuminant correction
//   Pass  8  CopyBufToSrc         CorrectiveBuf → CorrectiveSrcTex
//   Pass  9  ApplyContrast        CorrectiveSrc → CorrectiveBuf   Zone: S-curve anchored at median
//   Pass 10  BuildSatLevels       SatHistTex    → SatLevelsTex    Chroma: CDF → band medians
//   Pass 11  CopyBufToSrc         CorrectiveBuf → CorrectiveSrcTex
//   Pass 12  ApplyChroma          CorrectiveSrc → CorrectiveBuf   Chroma: per-hue S-curve
//   Pass 13  CopyBufToSrc         CorrectiveBuf → CorrectiveSrcTex
//
// OUTPUT TRANSFORM (display rendering, not creative):
//   Pass 14  OutputTransform      CorrectiveSrc → BackBuffer      OpenDRT + OKLab highlight rolloff

#include "creative_values.fx"

#define WB_R  100
#define WB_G  100
#define WB_B  100

#define YOUVAN_LERP_SPEED       4.3
#define GREY_PIXEL_THRESHOLD    0.1

#define ZONE_CURVE_STRENGTH  0
#define ZONE_LERP_SPEED      4.3
#define ZONE_HIST_LERP       4.3

#define CHROMA_CURVE_STRENGTH  0
#define CHROMA_LERP_SPEED      4.3
#define CHROMA_BAND_WIDTH      0.15

#define OT_CONTRAST         1.35
#define OT_CHROMA_COMPRESS  0.0
#define OT_BLACK_POINT      0
#define OT_SAT_MAX          85
#define OT_SAT_BLEND        15

uniform float frametime < source = "frametime"; >;

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

texture2D CorrectiveBuf { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 1; };
sampler2D CorrectiveSamp
{
    Texture   = CorrectiveBuf;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D CorrectiveSrcTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 1; };
sampler2D CorrectiveSrc
{
    Texture   = CorrectiveSrcTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Shared with frame_analysis — identical declaration = same GPU resource
texture2D SatHistTex { Width = 64; Height = 6; Format = R32F; MipLevels = 1; };
sampler2D SatHistSamp
{
    Texture   = SatHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Illuminant textures ──────────────────────────────────────────────────────

texture2D IlluminantTex { Width = 4; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D IlluminantSamp
{
    Texture   = IlluminantTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// ─── Alpha zone textures ──────────────────────────────────────────────────────

texture2D LowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; MipLevels = 1; };
sampler2D LowFreqSamp
{
    Texture   = LowFreqTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D ZoneHistTex { Width = 32; Height = 16; Format = R16F; MipLevels = 1; };
sampler2D ZoneHistSamp
{
    Texture   = ZoneHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D ZoneLevelsTex { Width = 4; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D ZoneLevelsSamp
{
    Texture   = ZoneLevelsTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// ─── Alpha chroma textures ────────────────────────────────────────────────────

texture2D SatLevelsTex { Width = 6; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D SatLevelsSamp
{
    Texture   = SatLevelsTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Vertex shader ───────────────────────────────────────────────────────────

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float SCurve(float x, float m, float strength)
{
    float t_lo = saturate(x / max(m, 0.001));
    float t_hi = saturate((x - m) / max(1.0 - m, 0.001));
    float s_lo = m * (t_lo * t_lo * (3.0 - 2.0 * t_lo));
    float s_hi = m + (1.0 - m) * (t_hi * t_hi * (3.0 - 2.0 * t_hi));
    float s    = lerp(s_lo, s_hi, step(m, x));
    return lerp(x, s, strength);
}

// ─── CAT16 chromatic adaptation matrices ─────────────────────────────────────

static const float3x3 M_CAT16 = float3x3(
     0.401288,  0.650173, -0.051461,
    -0.250268,  1.204414,  0.045854,
    -0.002079,  0.048952,  0.953127
);

static const float3x3 M_CAT16_inv = float3x3(
     1.862068, -1.011255,  0.149187,
     0.387526,  0.621447, -0.008974,
    -0.015842, -0.034123,  1.049964
);

// ─── Alpha chroma helpers ─────────────────────────────────────────────────────

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

float HueBandWeight(float hue, float center)
{
    float d = abs(hue - center);
    d = min(d, 1.0 - d);
    return saturate(1.0 - d / CHROMA_BAND_WIDTH);
}

static const float kBandCenters[6] = {
      0.0 / 360.0,   // Red
     60.0 / 360.0,   // Yellow
    120.0 / 360.0,   // Green
    180.0 / 360.0,   // Cyan
    240.0 / 360.0,   // Blue
    300.0 / 360.0    // Magenta
};

// ─── Output transform helpers ─────────────────────────────────────────────────

float3 RGBtoOKLab(float3 c)
{
    float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    l = pow(max(l, 0.0), 1.0 / 3.0);
    m = pow(max(m, 0.0), 1.0 / 3.0);
    s = pow(max(s, 0.0), 1.0 / 3.0);
    return float3(
         0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
         1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
         0.0259040371 * l + 0.4072426305 * m - 0.4327467890 * s
    );
}

float3 OKLabtoRGB(float3 c)
{
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    l = l * l * l;  m = m * m * m;  s = s * s * s;
    return float3(
        +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    );
}

// Scalar luma-based sigmoid — grey is the adaptive scene midpoint
float OpenDRT_luma(float luma, float grey)
{
    float gc = pow(max(grey, 0.001), OT_CONTRAST);
    float K  = gc * (1.0 - grey) / max(grey - gc, 0.0001);
    float A  = 1.0 + K;
    float xc = pow(max(luma, 0.0), OT_CONTRAST);
    return A * xc / (xc + K);
}

// ═══ Pixel shaders ════════════════════════════════════════════════════════════

// Pass 1 — Copy BackBuffer → CorrectiveBuf with white balance applied
float4 WhiteBalancePS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;  // data highway
    float3 c = col.rgb * float3(WB_R / 100.0, WB_G / 100.0, WB_B / 100.0);
    return float4(c, col.a);
}

// Passes 6, 8, 11, 13 — Snapshot CorrectiveBuf → CorrectiveSrcTex
float4 CopyBufToSrcPS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    return tex2D(CorrectiveSamp, uv);
}

// Pass 2 — 1/8 res downsample (shared by illuminant estimate + zone contrast)
float4 ComputeLowFreqPS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    float2 px = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float3 rgb = 0.0;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2(-1.5, -1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2( 1.5, -1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2(-1.5,  1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2( 1.5,  1.5) * px, 0, 0)).rgb;
    rgb *= 0.25;
    return float4(rgb, Luma(rgb));
}

// Pass 3 — Grey Pixel illuminant estimator: per 4×4 spatial zone, EMA temporal smoothing
float4 IlluminantEstimatePS(float4 pos : SV_Position,
                            float2 uv  : TEXCOORD0) : SV_Target
{
    int zone_x = int(pos.x);
    int zone_y = int(pos.y);
    if (zone_x >= 4 || zone_y >= 4) return float4(0, 0, 0, 0);

    float u_lo = float(zone_x) / 4.0;
    float v_lo = float(zone_y) / 4.0;

    float3 sum_neutral = 0.0;
    float  cnt_neutral = 0.0;
    float3 sum_all     = 0.0;

    [loop] for (int sy = 0; sy < 10; sy++)
    [loop] for (int sx = 0; sx < 10; sx++)
    {
        float2 suv     = float2(u_lo + (sx + 0.5) / 40.0,
                                v_lo + (sy + 0.5) / 40.0);
        float3 rgb     = tex2Dlod(LowFreqSamp, float4(suv, 0, 0)).rgb;
        float  den     = rgb.r + rgb.g + rgb.b + 0.001;
        float  neutral = max(abs(rgb.r - rgb.g), abs(rgb.r - rgb.b)) / den;
        float  w       = step(neutral, GREY_PIXEL_THRESHOLD);
        sum_neutral   += rgb * w;
        cnt_neutral   += w;
        sum_all       += rgb;
    }

    float3 illum   = (cnt_neutral > 0.5) ? (sum_neutral / cnt_neutral) : (sum_all / 100.0);

    float2 zone_uv = float2((float(zone_x) + 0.5) / 4.0, (float(zone_y) + 0.5) / 4.0);
    float4 prev    = tex2Dlod(IlluminantSamp, float4(zone_uv, 0, 0));
    float  speed   = (prev.a < 0.001) ? 1.0 : (YOUVAN_LERP_SPEED / 100.0) * (frametime / 10.0);

    return float4(lerp(prev.rgb, illum, speed), lerp(prev.a, 1.0, speed));
}

// Pass 4 — Zone contrast: per-zone 32-bin luma histogram
float4 ComputeZoneHistogramPS(float4 pos : SV_Position,
                              float2 uv  : TEXCOORD0) : SV_Target
{
    int b        = int(pos.x);
    int zone     = int(pos.y);
    int zone_col = zone % 4;
    int zone_row = zone / 4;

    float u_lo      = float(zone_col) / 4.0;
    float v_lo      = float(zone_row) / 4.0;
    float bucket_lo = float(b)     / 32.0;
    float bucket_hi = float(b + 1) / 32.0;

    float count = 0.0;
    [loop] for (int sy = 0; sy < 10; sy++)
    [loop] for (int sx = 0; sx < 10; sx++)
    {
        float2 suv  = float2(u_lo + (sx + 0.5) / 10.0 * 0.25,
                             v_lo + (sy + 0.5) / 10.0 * 0.25);
        float  luma = tex2Dlod(LowFreqSamp, float4(suv, 0, 0)).a;
        count += (luma >= bucket_lo && luma < bucket_hi) ? 1.0 : 0.0;
    }

    float v    = count / 100.0;
    float prev = tex2Dlod(ZoneHistSamp,
        float4((float(b) + 0.5) / 32.0, (float(zone) + 0.5) / 16.0, 0, 0)).r;
    float h    = lerp(prev, v, (ZONE_HIST_LERP / 100.0) * (frametime / 10.0));
    return float4(h, h, h, 1.0);
}

// Pass 5 — Zone contrast: CDF walk → zone medians
float4 BuildZoneLevelsPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    int zone_x = int(pos.x);
    int zone_y = int(pos.y);
    int zone   = zone_y * 4 + zone_x;

    float2 prev_uv = float2((float(zone_x) + 0.5) / 4.0, (float(zone_y) + 0.5) / 4.0);
    float4 prev    = tex2Dlod(ZoneLevelsSamp, float4(prev_uv, 0, 0));
    float  speed   = (prev.r < 0.001) ? 1.0 : (ZONE_LERP_SPEED / 100.0) * (frametime / 10.0);

    float cumulative = 0.0;
    float p25 = 0.25, median = 0.5, p75 = 0.75;
    float lock25 = 0.0, lock50 = 0.0, lock75 = 0.0;

    [loop] for (int b = 0; b < 32; b++)
    {
        float bv   = float(b) / 32.0;
        float frac = tex2Dlod(ZoneHistSamp,
            float4((float(b) + 0.5) / 32.0, (float(zone) + 0.5) / 16.0, 0, 0)).r;
        cumulative += frac;

        float at25 = step(0.25, cumulative) * (1.0 - lock25);
        float at50 = step(0.50, cumulative) * (1.0 - lock50);
        float at75 = step(0.75, cumulative) * (1.0 - lock75);
        p25    = lerp(p25,    bv, at25);
        median = lerp(median, bv, at50);
        p75    = lerp(p75,    bv, at75);
        lock25 = saturate(lock25 + at25);
        lock50 = saturate(lock50 + at50);
        lock75 = saturate(lock75 + at75);
    }

    return float4(lerp(prev.r, median, speed),
                  lerp(prev.g, p25,    speed),
                  lerp(prev.b, p75,    speed),
                  1.0);
}

// Pass 7 — CAT16 chromatic adaptation: correct per-zone illuminant toward neutral grey
float4 ApplyAdaptationPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;  // data highway

    float3 illuminant = tex2D(IlluminantSamp, uv).rgb;
    float  grey       = Luma(illuminant);

    float3 lms_illum  = mul(M_CAT16, illuminant);
    float3 lms_pixel  = mul(M_CAT16, col.rgb);
    float3 scale      = float3(grey, grey, grey) / max(abs(lms_illum), 0.001);
    scale             = clamp(scale, 0.1, 10.0);
    float3 adapted    = mul(M_CAT16_inv, lms_pixel * scale);

    float3 result = lerp(col.rgb, adapted, YOUVAN_STRENGTH / 100.0);
    return float4(result, col.a);
}

// Pass 9 — Zone contrast: S-curve anchored at zone median
float4 ApplyContrastPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;  // data highway

    float luma = Luma(col.rgb);

    float4 zone_levels = tex2D(ZoneLevelsSamp, uv);
    float  zone_median = zone_levels.r;
    float  zone_iqr    = saturate(zone_levels.b - zone_levels.g);

    float t        = luma * 2.0 - 1.0;
    float tonal_w  = 1.0 - t * t;
    float strength = (ZONE_CURVE_STRENGTH / 100.0) * tonal_w * (1.0 - zone_iqr);

    float new_luma = SCurve(luma, zone_median, strength);
    float scale    = new_luma / max(luma, 0.001);

    return float4(col.rgb * scale, col.a);
}

// Pass 10 — Chroma: CDF walk on SatHistTex → per-band saturation medians
float4 BuildSatLevelsPS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    int   band  = int(pos.x);
    float row_v = (float(band) + 0.5) / 6.0;

    float4 prev  = tex2Dlod(SatLevelsSamp, float4((float(band) + 0.5) / 6.0, 0.5, 0, 0));
    float  speed = (prev.r < 0.001) ? 1.0 : (CHROMA_LERP_SPEED / 100.0) * (frametime / 10.0);

    float cumulative = 0.0;
    float p25 = 0.25, median = 0.5, p75 = 0.75;
    float lock25 = 0.0, lock50 = 0.0, lock75 = 0.0;

    [loop] for (int b = 0; b < 64; b++)
    {
        float bv   = float(b) / 64.0;
        float frac = tex2Dlod(SatHistSamp,
            float4((float(b) + 0.5) / 64.0, row_v, 0, 0)).r;
        cumulative += frac;

        float at25 = step(0.25, cumulative) * (1.0 - lock25);
        float at50 = step(0.50, cumulative) * (1.0 - lock50);
        float at75 = step(0.75, cumulative) * (1.0 - lock75);
        p25    = lerp(p25,    bv, at25);
        median = lerp(median, bv, at50);
        p75    = lerp(p75,    bv, at75);
        lock25 = saturate(lock25 + at25);
        lock50 = saturate(lock50 + at50);
        lock75 = saturate(lock75 + at75);
    }

    return float4(lerp(prev.r, median, speed),
                  lerp(prev.g, p25,    speed),
                  lerp(prev.b, p75,    speed),
                  1.0);
}

// Pass 12 — Chroma: per-hue-band saturation S-curve
float4 ApplyChromaPS(float4 pos : SV_Position,
                     float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;  // data highway

    float3 hsv = RGBtoHSV(col.rgb);

    float blended_median = 0.0;
    float blended_iqr    = 0.0;
    float total_w        = 0.0;

    [loop] for (int band = 0; band < 6; band++)
    {
        float  w      = HueBandWeight(hsv.x, kBandCenters[band]);
        float4 levels = tex2Dlod(SatLevelsSamp, float4((float(band) + 0.5) / 6.0, 0.5, 0, 0));
        blended_median += levels.r * w;
        blended_iqr    += saturate(levels.b - levels.g) * w;
        total_w        += w;
    }

    blended_median = (total_w > 0.001) ? blended_median / total_w : 0.5;
    blended_iqr    = (total_w > 0.001) ? blended_iqr    / total_w : 0.5;

    float sat_w   = smoothstep(0.0, 0.15, hsv.y);
    float strength = (CHROMA_CURVE_STRENGTH / 100.0) * sat_w * (1.0 - blended_iqr);
    float new_sat  = SCurve(hsv.y, blended_median, strength);
    float3 result  = HSVtoRGB(float3(hsv.x, new_sat, hsv.z));

    return float4(result, col.a);
}

// Pass 14 — Output transform: OpenDRT tone curve + OKLab highlight rolloff → BackBuffer
float4 OutputTransformPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col    = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;  // data highway

    float3 result = col.rgb;

    // Gamut compression (linear, before tone curve)
    float luma_gc = Luma(result);
    float under   = saturate(-min(result.r, min(result.g, result.b)) * 10.0);
    result        = lerp(result, float3(luma_gc, luma_gc, luma_gc), under);

    float gc_max  = max(result.r, max(result.g, result.b));
    float gc_min  = min(result.r, min(result.g, result.b));
    float sat_gc  = (gc_max > 0.001) ? (gc_max - gc_min) / gc_max : 0.0;
    float excess  = max(0.0, sat_gc - OT_SAT_MAX / 100.0) / (1.0 - OT_SAT_MAX / 100.0);
    float gc_amt  = excess * excess * (OT_SAT_BLEND / 100.0);
    result        = result + (gc_max - result) * gc_amt;

    // Black lift
    result = result * (1.0 - OT_BLACK_POINT / 100.0) + OT_BLACK_POINT / 100.0;

    // Scene-adaptive grey point — average luma across all 16 IlluminantTex zones (EMA-smoothed)
    float grey = 0.0;
    [loop] for (int zy = 0; zy < 4; zy++)
    [loop] for (int zx = 0; zx < 4; zx++)
    {
        float3 illum = tex2Dlod(IlluminantSamp,
            float4((zx + 0.5) / 4.0, (zy + 0.5) / 4.0, 0, 0)).rgb;
        grey += Luma(illum);
    }
    grey = clamp(grey / 16.0, 0.05, 0.40);

    // Tone curve in OKLab L only — chroma (a*,b*) unchanged, zero saturation loss
    float3 lab_in     = RGBtoOKLab(result);
    float  L_mapped   = OpenDRT_luma(max(lab_in.x, 0.0), grey);
    float3 tonemapped = OKLabtoRGB(float3(L_mapped, lab_in.yz));
    result = lerp(result, tonemapped, OPENDRT_STRENGTH / 100.0);

    // Highlight chroma compression (OKLab)
    float3 lab    = RGBtoOKLab(result);
    float hl_gate = smoothstep(0.65, 1.0, lab.x);
    lab.yz       *= (1.0 - hl_gate * OT_CHROMA_COMPRESS);
    result        = OKLabtoRGB(lab);

    // Debug indicator — green (slot 2)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 50) && pos.x < float(BUFFER_WIDTH - 38))
        return float4(0.1, 0.90, 0.1, 1.0);
    return saturate(float4(result, col.a));
}

// ─── Technique ───────────────────────────────────────────────────────────────

technique OlofssonianRenderChain
{
    pass WhiteBalance
    {
        VertexShader = PostProcessVS;
        PixelShader  = WhiteBalancePS;
        RenderTarget = CorrectiveBuf;
    }
    pass ComputeLowFreq
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeLowFreqPS;
        RenderTarget = LowFreqTex;
    }
    pass IlluminantEstimate
    {
        VertexShader = PostProcessVS;
        PixelShader  = IlluminantEstimatePS;
        RenderTarget = IlluminantTex;
    }
    pass ComputeZoneHistogram
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeZoneHistogramPS;
        RenderTarget = ZoneHistTex;
    }
    pass BuildZoneLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildZoneLevelsPS;
        RenderTarget = ZoneLevelsTex;
    }
    pass CopyBufToSrc0
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyBufToSrcPS;
        RenderTarget = CorrectiveSrcTex;
    }
    pass ApplyAdaptation
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyAdaptationPS;
        RenderTarget = CorrectiveBuf;
    }
    pass CopyBufToSrc1
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyBufToSrcPS;
        RenderTarget = CorrectiveSrcTex;
    }
    pass ApplyContrast
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyContrastPS;
        RenderTarget = CorrectiveBuf;
    }
    pass BuildSatLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildSatLevelsPS;
        RenderTarget = SatLevelsTex;
    }
    pass CopyBufToSrc2
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyBufToSrcPS;
        RenderTarget = CorrectiveSrcTex;
    }
    pass ApplyChroma
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyChromaPS;
        RenderTarget = CorrectiveBuf;
    }
    pass CopyBufToSrc3
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyBufToSrcPS;
        RenderTarget = CorrectiveSrcTex;
    }
    pass OutputTransform
    {
        VertexShader = PostProcessVS;
        PixelShader  = OutputTransformPS;
    }
}
