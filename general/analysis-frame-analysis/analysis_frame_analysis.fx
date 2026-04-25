// frame_analysis.fx — Frame-wide histogram analysis
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
#define LERP_SPEED    8         // 0–100; temporal smoothing rate for histograms
#define SAT_THRESHOLD 4         // 0–100; minimum saturation to include in histogram
#define BAND_WIDTH    0.15

#define BAND_RED     (0.0   / 360.0)
#define BAND_YELLOW  (60.0  / 360.0)
#define BAND_GREEN   (120.0 / 360.0)
#define BAND_CYAN    (180.0 / 360.0)
#define BAND_BLUE    (240.0 / 360.0)
#define BAND_MAGENTA (300.0 / 360.0)

static const float kBandCenters[6] = {
    BAND_RED, BAND_YELLOW, BAND_GREEN, BAND_CYAN, BAND_BLUE, BAND_MAGENTA
};

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

texture2D LumHistRawTex { Width = HIST_BINS; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumHistRaw
{
    Texture   = LumHistRawTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D SatHistRawTex { Width = HIST_BINS; Height = 6; Format = R32F; MipLevels = 1; };
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
texture2D LumHistTex { Width = HIST_BINS; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumHist
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D SatHistTex { Width = HIST_BINS; Height = 6; Format = R32F; MipLevels = 1; };
sampler2D SatHist
{
    Texture   = SatHistTex;
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
    float center    = kBandCenters[band];

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
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 78) && pos.x < float(BUFFER_WIDTH - 66))
        return float4(1.0, 0.95, 0.0, 1.0);
    return tex2D(BackBuffer, uv);
}

// ─── Pass 5 — Smooth luminance histogram ───────────────────────────────────

float4 LumHistSmoothPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float raw  = tex2D(LumHistRaw, uv).r;
    float prev = tex2D(LumHist,    uv).r;
    return float4(lerp(prev, raw, LERP_SPEED / 100.0), 0.0, 0.0, 1.0);
}

// ─── Pass 6 — Smooth saturation histogram ──────────────────────────────────

float4 SatHistSmoothPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float raw  = tex2D(SatHistRaw, uv).r;
    float prev = tex2D(SatHist,    uv).r;
    return float4(lerp(prev, raw, LERP_SPEED / 100.0), 0.0, 0.0, 1.0);
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
}
