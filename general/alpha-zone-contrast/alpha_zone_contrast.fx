// alpha_zone_contrast.fx — Histogram-driven adaptive luma contrast
//
// Uses the scene's luminance CDF as the tone curve:
//   output_luma = lerp(input_luma, CDF(input_luma), CURVE_STRENGTH)
//
// Dense tonal regions get expanded (more contrast where content lives).
// Sparse regions get compressed (no wasted contrast in empty ranges).
// Full 0–1 range graded — no fixed pivots or parameterized S-shape.
//
// Two passes:
//   Pass 1 — BuildCDF: walk LumHistTex (64 bins from frame_analysis),
//             compute cumulative sum per bin, lerp into LumCDFTex.
//   Pass 2 — ApplyContrast: sample LumCDFTex at pixel luma, scale RGB
//             to new luma (hue+sat preserved).
//
// Requires frame_analysis.fx to run before this in the chain.

#define CURVE_STRENGTH  0.30
#define LERP_SPEED      0.08
#define HIST_BINS       64

// ─── Shared histogram texture — must match frame_analysis.fx exactly ───────
texture2D LumHistTex { Width = HIST_BINS; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumHist
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── CDF LUT — smoothed across frames ─────────────────────────────────────
texture2D LumCDFTex { Width = HIST_BINS; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumCDF
{
    Texture   = LumCDFTex;
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

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ─── Pass 1 — Build smoothed CDF ───────────────────────────────────────────
// Each output pixel b stores the cumulative sum hist[0..b] (i.e. CDF at bin b).
// Temporally lerped for stability.

float4 BuildCDFPS(float4 pos : SV_Position,
                  float2 uv  : TEXCOORD0) : SV_Target
{
    int b = int(pos.x);
    if (b >= HIST_BINS) return float4(0, 0, 0, 1);

    float cdf = 0.0;
    [loop]
    for (int i = 0; i <= b; i++)
    {
        float2 h_uv = float2((i + 0.5) / float(HIST_BINS), 0.5);
        cdf += tex2Dlod(LumHist, float4(h_uv, 0, 0)).r;
    }

    float prev     = tex2Dlod(LumCDF, float4(uv, 0, 0)).r;
    float prev_max = tex2Dlod(LumCDF, float4((HIST_BINS - 0.5) / float(HIST_BINS), 0.5, 0, 0)).r;
    float speed    = (prev_max < 0.5) ? 1.0 : LERP_SPEED;

    return float4(lerp(prev, cdf, speed), 0, 0, 1);
}

// ─── Pass 2 — Apply CDF tone curve ─────────────────────────────────────────
// Samples CDF at pixel luma, blends toward equalized value, scales RGB.
// Hue and saturation are preserved — only luma changes.

float4 ApplyContrastPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2519 && pos.x < 2531 && pos.y > 15 && pos.y < 27)
        return float4(0.0, 0.7, 0.7, 1.0);

    float4 col    = tex2D(BackBuffer, uv);
    float  luma   = Luma(col.rgb);

    if (luma < 0.005) return col;

    float equalized = tex2D(LumCDF, float2(luma, 0.5)).r;
    float new_luma  = lerp(luma, equalized, CURVE_STRENGTH);
    float scale     = clamp(new_luma / luma, 0.0, 3.0);
    float3 result   = col.rgb * scale;

    return float4(saturate(result), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique AlphaZoneContrast
{
    pass BuildCDF
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildCDFPS;
        RenderTarget = LumCDFTex;
    }
    pass ApplyContrast
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyContrastPS;
    }
}
