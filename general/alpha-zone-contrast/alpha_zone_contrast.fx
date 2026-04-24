// alpha_zone_contrast.fx — Multi-scale histogram-driven luma contrast
//
// Uses the scene's luminance CDF as the tone curve, applied to the
// large-scale (low-frequency) luma component only:
//   luma_low  = spatially smoothed luma (1/8 res, bilinear upsample on read)
//   luma_high = luma_full - luma_low  (local detail — edges, texture)
//   output_luma = CDF_equalize(luma_low) + luma_high
//
// Dense tonal regions get expanded (more contrast where content lives).
// Sparse regions get compressed (no wasted contrast in empty ranges).
// Fine detail is unaffected — only large-scale tonal structure is equalized.
//
// Three passes:
//   Pass 1 — BuildCDF: walk LumHistTex (64 bins from frame_analysis),
//             compute cumulative sum per bin, lerp into LumCDFTex.
//   Pass 2 — ComputeLowFreq: downsample BackBuffer luma to 1/8 res —
//             captures large-scale tonal structure (structures > 8px).
//   Pass 3 — ApplyContrast: equalize low-freq luma via CDF, add back
//             high-freq detail, scale RGB (hue+sat preserved).
//
// Requires frame_analysis.fx to run before this in the chain.

#define CURVE_STRENGTH  20      // -100 to 100; positive = expands, negative = compresses. Scale feels logarithmic — small values (5–30) have strong effect, use fine steps. 20 = technical baseline (recover game compression only).
#define LERP_SPEED      0.5     // 0–100; temporal smoothing rate for CDF
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

// ─── Low-frequency luma — 1/8 resolution, bilinear upsampled on read ───────
texture2D LowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16F; MipLevels = 1; };
sampler2D LowFreqSamp
{
    Texture   = LowFreqTex;
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
    float speed    = (prev_max < 0.5) ? 1.0 : clamp(LERP_SPEED / 100.0, 0.001, 1.0);

    return float4(lerp(prev, cdf, speed), 0, 0, 1);
}

// ─── Pass 2 — Downsample to low-frequency luma ─────────────────────────────
// 4-tap box at offset ±1.5px in full-res space. At 1/8 output resolution the
// hardware bilinear adds another level of smoothing — captures structures > 8px.

float4 ComputeLowFreqPS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    float2 px = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float luma = 0.0;
    luma += Luma(tex2Dlod(BackBuffer, float4(uv + float2(-1.5, -1.5) * px, 0, 0)).rgb);
    luma += Luma(tex2Dlod(BackBuffer, float4(uv + float2( 1.5, -1.5) * px, 0, 0)).rgb);
    luma += Luma(tex2Dlod(BackBuffer, float4(uv + float2(-1.5,  1.5) * px, 0, 0)).rgb);
    luma += Luma(tex2Dlod(BackBuffer, float4(uv + float2( 1.5,  1.5) * px, 0, 0)).rgb);
    return float4(luma * 0.25, 0, 0, 1);
}

// ─── Pass 3 — Apply multi-scale CDF tone curve ─────────────────────────────

float4 ApplyContrastPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2473 && pos.x < 2485 && pos.y > 15 && pos.y < 27)
        return float4(0.0, 0.7, 0.7, 1.0);

    float4 col       = tex2D(BackBuffer, uv);
    float  luma_full = Luma(col.rgb);

    if (luma_full < 0.005) return col;

    float luma_low  = tex2D(LowFreqSamp, uv).r;
    float luma_high = luma_full - luma_low;

    float equalized_low = tex2D(LumCDF, float2(luma_low, 0.5)).r;
    float new_luma_low  = lerp(luma_low, equalized_low, -(CURVE_STRENGTH / 100.0));

    float new_luma = max(0.001, new_luma_low + luma_high);
    float scale    = clamp(new_luma / luma_full, 0.0, 3.0);

    return float4(saturate(col.rgb * scale), col.a);
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
    pass ComputeLowFreq
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeLowFreqPS;
        RenderTarget = LowFreqTex;
    }
    pass ApplyContrast
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyContrastPS;
    }
}
