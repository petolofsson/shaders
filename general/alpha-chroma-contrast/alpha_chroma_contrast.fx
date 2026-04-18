// alpha_chroma_contrast.fx — Histogram-driven adaptive chroma contrast
//
// Per-hue-band saturation equalization via CDF LUT:
//   output_sat = lerp(input_sat, CDF_band(input_sat), CURVE_STRENGTH)
//
// Each of 6 hue bands (Red/Yellow/Green/Cyan/Blue/Magenta) gets its own
// CDF built from SatHistTex (6×64 from frame_analysis). Bands overlap with
// smooth weights so transitions are seamless.
//
// Two passes:
//   Pass 1 — BuildSatCDF: walk each row of SatHistTex, compute per-band
//             cumulative sum, lerp into SatCDFTex (64×6).
//   Pass 2 — ApplyChroma: per-pixel, blend band CDFs by hue weight, apply
//             equalized saturation. Preserves green hue cool-shift.
//
// Requires frame_analysis.fx to run before this in the chain.

#define CURVE_STRENGTH  0.45
#define LERP_SPEED      0.08
#define BAND_WIDTH      0.15
#define SAT_THRESHOLD   0.05
#define GREEN_HUE_COOL  (4.0 / 360.0)
#define HIST_BINS       64

#define BAND_RED     (0.0   / 360.0)
#define BAND_YELLOW  (60.0  / 360.0)
#define BAND_GREEN   (120.0 / 360.0)
#define BAND_CYAN    (180.0 / 360.0)
#define BAND_BLUE    (240.0 / 360.0)
#define BAND_MAGENTA (300.0 / 360.0)

static const float kBandCenters[6] = {
    BAND_RED, BAND_YELLOW, BAND_GREEN, BAND_CYAN, BAND_BLUE, BAND_MAGENTA
};

// ─── Shared histogram texture — must match frame_analysis.fx exactly ───────
texture2D SatHistTex { Width = HIST_BINS; Height = 6; Format = R32F; MipLevels = 1; };
sampler2D SatHist
{
    Texture   = SatHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Per-band saturation CDF LUT — 64×6 RGBA16F ────────────────────────────
texture2D SatCDFTex { Width = HIST_BINS; Height = 6; Format = R32F; MipLevels = 1; };
sampler2D SatCDF
{
    Texture   = SatCDFTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
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
    return saturate(1.0 - d / BAND_WIDTH);
}

// ─── Pass 1 — Build per-band saturation CDF ────────────────────────────────
// Each output pixel at (b, band) stores cumulative sum satHist[0..b] for that band.
// Temporally lerped for stability.

float4 BuildSatCDFPS(float4 pos : SV_Position,
                     float2 uv  : TEXCOORD0) : SV_Target
{
    int b    = int(pos.x);
    int band = int(pos.y);
    if (b >= HIST_BINS || band >= 6) return float4(0, 0, 0, 1);

    float row_v = (band + 0.5) / 6.0;
    float cdf   = 0.0;

    [loop]
    for (int i = 0; i <= b; i++)
    {
        float2 h_uv = float2((i + 0.5) / float(HIST_BINS), row_v);
        cdf += tex2Dlod(SatHist, float4(h_uv, 0, 0)).r;
    }

    float prev     = tex2Dlod(SatCDF, float4(uv, 0, 0)).r;
    float prev_max = tex2Dlod(SatCDF, float4((HIST_BINS - 0.5) / float(HIST_BINS), row_v, 0, 0)).r;
    float speed    = (prev_max < 0.5) ? 1.0 : LERP_SPEED;

    return float4(lerp(prev, cdf, speed), 0, 0, 1);
}

// ─── Pass 2 — Apply per-band CDF saturation curve ──────────────────────────

float4 ApplyChromaPS(float4 pos : SV_Position,
                     float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2504 && pos.x < 2516 && pos.y > 15 && pos.y < 27)
        return float4(0.9, 0.3, 0.1, 1.0);

    float4 col = tex2D(BackBuffer, uv);
    float3 hsv = RGBtoHSV(col.rgb);

    if (hsv.y < SAT_THRESHOLD) return col;

    float new_sat = 0.0;
    float total_w = 0.0;
    float green_w = 0.0;

    for (int b = 0; b < 6; b++)
    {
        float w      = HueBandWeight(hsv.x, kBandCenters[b]);
        float row_v  = (b + 0.5) / 6.0;
        float equalized = tex2D(SatCDF, float2(hsv.y, row_v)).r;
        float band_sat  = lerp(hsv.y, equalized, CURVE_STRENGTH);

        new_sat += band_sat * w;
        total_w += w;

        if (b == 2) green_w = w;
    }

    float final_sat = (total_w > 0.001) ? new_sat / total_w : hsv.y;
    float final_hue = hsv.x - GREEN_HUE_COOL * green_w * final_sat;

    float3 result = HSVtoRGB(float3(final_hue, final_sat, hsv.z));
    return float4(result, col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique AlphaChromaContrast
{
    pass BuildSatCDF
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildSatCDFPS;
        RenderTarget = SatCDFTex;
    }
    pass ApplyChroma
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyChromaPS;
    }
}
