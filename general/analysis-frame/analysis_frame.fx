// frame_analysis.fx — Frame-wide histogram analysis
#include "debug_text.fxh"
//
// Builds per-frame luminance and per-hue saturation histograms.
// Shared smoothed textures (LumHistTex, SatHistTex) are read by
// ZoneContrast and ChromaContrast for true percentile pivots.
//
// Five passes:
//   1. Downsample BackBuffer to 32x18
//   2. Gather luminance histogram (64 buckets, 64x1 R32F)
//   3. Gather per-hue saturation histogram (64 buckets x 6 bands, 64x6 R32F)
//   4. Temporally smooth luminance histogram
//   5. Temporally smooth saturation histogram
//
// Samples are linearized (pow 2.2) before binning so percentile values
// are in linear light — consistent with ZoneContrast and ChromaContrast
// which operate in linear space.

#define DS_W          32
#define DS_H          18
#define HIST_BINS     64
#define LERP_SPEED     4.3
#define KALMAN_Q_PERC_MIN  0.00005
#define KALMAN_Q_PERC_MAX  0.05
#define KALMAN_R_PERC      0.005
#define VFF_E_SIGMA_PERC   0.06
#define SAT_THRESHOLD 4         // 0–100; minimum saturation to include in histogram
#define BAND_WIDTH    0.15

#define BAND_RED     (0.0   / 360.0)
#define BAND_YELLOW  (60.0  / 360.0)
#define BAND_GREEN   (120.0 / 360.0)
#define BAND_CYAN    (180.0 / 360.0)
#define BAND_BLUE    (240.0 / 360.0)
#define BAND_MAGENTA (300.0 / 360.0)

float GetBandCenter(int band)
{
    if (band == 0) return BAND_RED;
    if (band == 1) return BAND_YELLOW;
    if (band == 2) return BAND_GREEN;
    if (band == 3) return BAND_CYAN;
    if (band == 4) return BAND_BLUE;
    return BAND_MAGENTA;
}

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

texture2D DownsampleTex { Width = DS_W; Height = DS_H; Format = RGBA16F; MipLevels = 1; };
sampler2D Downsample
{
    Texture   = DownsampleTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D LumHistRawTex { Width = HIST_BINS; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D LumHistRaw
{
    Texture   = LumHistRawTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D SatHistRawTex { Width = HIST_BINS; Height = 6; Format = R16F; MipLevels = 1; };
sampler2D SatHistRaw
{
    Texture   = SatHistRawTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// Shared smoothed textures — re-declared with identical descriptors in
// olofssonian_zone_contrast.fx and olofssonian_chroma_lift.fx
texture2D LumHistTex { Width = HIST_BINS; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D LumHist
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D SatHistTex { Width = HIST_BINS; Height = 6; Format = R16F; MipLevels = 1; };
sampler2D SatHist
{
    Texture   = SatHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// Shared percentile cache — r=p25, g=p50, b=p75, a=P (Kalman variance)
// Written here, read by corrective_render_chain and grade
texture2D PercTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D PercSamp
{
    Texture   = PercTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// R53: scene-cut signal — r=scene_cut [0,1], g=p50 from last frame (for delta)
// Written here, read by corrective passes to override Kalman gain
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

float3 RGBtoHSV(float3 c)
{
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float  d = q.x - min(q.w, q.y);
    float  e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float HueBandWeight(float hue, float center)
{
    float d = abs(hue - center);
    d = min(d, 1.0 - d);
    return saturate(1.0 - d / BAND_WIDTH);
}

// ─── Pass 1 — Downsample ───────────────────────────────────────────────────

float4 DownsamplePS(float4 pos : SV_Position,
                    float2 uv  : TEXCOORD0) : SV_Target
{
    return tex2D(BackBuffer, uv);
}

// ─── Pass 2 — Luminance histogram gather ───────────────────────────────────
// Each output pixel (bucket b) counts linearized-luma samples in [b/64, (b+1)/64).
// Normalized by total samples so the histogram sums to 1.0.

float4 LumHistGatherPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    int   b         = int(pos.x);
    float bucket_lo = float(b)     / float(HIST_BINS);
    float bucket_hi = float(b + 1) / float(HIST_BINS);

    float count = 0.0;
    [loop]
    for (int y = 0; y < DS_H; y++)
    {
        [loop]
        for (int x = 0; x < DS_W; x++)
        {
            float2 s_uv = float2((x + 0.5) / float(DS_W), (y + 0.5) / float(DS_H));
            float3 c    = tex2D(Downsample, s_uv).rgb;  // already linear — vkBasalt linearizes on read
            float  luma = Luma(c);
            count += (luma >= bucket_lo && luma < bucket_hi) ? 1.0 : 0.0;
        }
    }

    return float4(count / float(DS_W * DS_H), 0.0, 0.0, 1.0);
}

// ─── Pass 3 — Saturation histogram gather ──────────────────────────────────
// Each output pixel (bucket b, band row) counts hue-weighted saturation samples.
// Normalized by total band weight so per-row CDF sums to 1.0.

float4 SatHistGatherPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    int   b         = int(pos.x);
    int   band      = int(pos.y);
    float bucket_lo = float(b)     / float(HIST_BINS);
    float bucket_hi = float(b + 1) / float(HIST_BINS);
    float center    = GetBandCenter(band);

    float count   = 0.0;
    float total_w = 0.0;

    [loop]
    for (int y = 0; y < DS_H; y++)
    {
        [loop]
        for (int x = 0; x < DS_W; x++)
        {
            float2 s_uv   = float2((x + 0.5) / float(DS_W), (y + 0.5) / float(DS_H));
            float3 col = tex2D(Downsample, s_uv).rgb;
            float3 hsv = RGBtoHSV(col);
            float  w      = HueBandWeight(hsv.x, center) * step(SAT_THRESHOLD / 100.0, hsv.y);
            float  in_b   = (hsv.y >= bucket_lo && hsv.y < bucket_hi) ? 1.0 : 0.0;
            count   += in_b * w;
            total_w += w;
        }
    }

    float normalized = (total_w > 0.001) ? count / total_w : 0.0;
    return float4(normalized, 0.0, 0.0, 1.0);
}

// ─── Pass 4 — Debug indicator (yellow, slot 0) ────────────────────────────

float4 DebugOverlayPS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    float4 c = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return c;  // data highway
    return DrawLabel(c, pos.xy, 270.0, 10.0,
                     49u, 65u, 78u, 76u, float3(1.0, 0.95, 0.0)); // 1ANL
}

// ─── Pass 5 — Smooth luminance histogram ───────────────────────────────────

float4 LumHistSmoothPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float raw  = tex2D(LumHistRaw, uv).r;
    float prev = tex2D(LumHist,    uv).r;
    return float4(lerp(prev, raw, saturate((LERP_SPEED / 100.0) * (frametime / 10.0))), 0.0, 0.0, 1.0);
}

// ─── Pass 6 — Smooth saturation histogram ──────────────────────────────────

float4 SatHistSmoothPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float raw  = tex2D(SatHistRaw, uv).r;
    float prev = tex2D(SatHist,    uv).r;
    return float4(lerp(prev, raw, saturate((LERP_SPEED / 100.0) * (frametime / 10.0))), 0.0, 0.0, 1.0);
}

// ─── Pass 7 — CDF walk → 1×1 percentile cache ─────────────────────────────
// Trimmed: targets 0.275/0.50/0.725 exclude the bottom and top 5% of mass,
// making anchors immune to specular spikes and crushed-black collapse.
// Intra-bin interpolation raises effective resolution from 1/64 to ~1/512.

float4 CDFWalkPS(float4 pos : SV_Position,
                 float2 uv  : TEXCOORD0) : SV_Target
{
    float cumul = 0.0;
    float p25 = 0.25, p50 = 0.50, p75 = 0.75;
    float lk25 = 0.0, lk50 = 0.0, lk75 = 0.0;

    [loop] for (int b = 0; b < HIST_BINS; b++)
    {
        float frc  = tex2Dlod(LumHist, float4((float(b) + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r;
        float prev = cumul;
        cumul += frc;

        float inv  = (frc > 0.0) ? 1.0 / frc : 0.0;
        float t25  = saturate((0.275 - prev) * inv);
        float t50  = saturate((0.500 - prev) * inv);
        float t75  = saturate((0.725 - prev) * inv);

        float bv25 = (float(b) + t25) / float(HIST_BINS);
        float bv50 = (float(b) + t50) / float(HIST_BINS);
        float bv75 = (float(b) + t75) / float(HIST_BINS);

        float at25 = step(0.275, cumul) * (1.0 - lk25);
        float at50 = step(0.500, cumul) * (1.0 - lk50);
        float at75 = step(0.725, cumul) * (1.0 - lk75);
        p25  = lerp(p25, bv25, at25);
        p50  = lerp(p50, bv50, at50);
        p75  = lerp(p75, bv75, at75);
        lk25 = saturate(lk25 + at25);
        lk50 = saturate(lk50 + at50);
        lk75 = saturate(lk75 + at75);
    }

    // R34+R39: VFF Kalman on percentile outputs — P in .a (replaces IQR sentinel)
    float4 prev    = tex2D(PercSamp, float2(0.5, 0.5));
    float  P       = (prev.a < 0.001) ? 1.0 : prev.a;
    float  e_p50   = p50 - prev.g;
    float  Q_vff_p = lerp(KALMAN_Q_PERC_MIN, KALMAN_Q_PERC_MAX, smoothstep(0.0, VFF_E_SIGMA_PERC, abs(e_p50)));
    float  P_pred  = P + Q_vff_p;
    float  K       = P_pred / (P_pred + KALMAN_R_PERC);
    float  P_new   = (1.0 - K) * P_pred;
    return float4(prev.r + K * (p25 - prev.r),
                  prev.g + K * e_p50,
                  prev.b + K * (p75 - prev.b),
                  P_new);
}

// ─── Pass 8 — R53: scene-cut detection ────────────────────────────────────

float4 SceneCutPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float p50_now  = tex2Dlod(PercSamp,    float4(0.5, 0.5, 0, 0)).g;
    float p50_prev = tex2Dlod(SceneCutSamp, float4(0.5, 0.5, 0, 0)).g;
    float scene_cut = smoothstep(0.10, 0.25, abs(p50_now - p50_prev));
    return float4(scene_cut, p50_now, 0.0, 1.0);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique FrameAnalysis
{
    pass Downsample
    {
        VertexShader = PostProcessVS;
        PixelShader  = DownsamplePS;
        RenderTarget = DownsampleTex;
    }
    pass LumHistGather
    {
        VertexShader = PostProcessVS;
        PixelShader  = LumHistGatherPS;
        RenderTarget = LumHistRawTex;
    }
    pass SatHistGather
    {
        VertexShader = PostProcessVS;
        PixelShader  = SatHistGatherPS;
        RenderTarget = SatHistRawTex;
    }
    pass DebugOverlay
    {
        VertexShader = PostProcessVS;
        PixelShader  = DebugOverlayPS;
    }
    pass LumHistSmooth
    {
        VertexShader = PostProcessVS;
        PixelShader  = LumHistSmoothPS;
        RenderTarget = LumHistTex;
    }
    pass SatHistSmooth
    {
        VertexShader = PostProcessVS;
        PixelShader  = SatHistSmoothPS;
        RenderTarget = SatHistTex;
    }
    pass CDFWalk
    {
        VertexShader = PostProcessVS;
        PixelShader  = CDFWalkPS;
        RenderTarget = PercTex;
    }
    pass SceneCut
    {
        VertexShader = PostProcessVS;
        PixelShader  = SceneCutPS;
        RenderTarget = SceneCutTex;
    }
}
