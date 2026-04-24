// alpha_chroma_lift.fx — Histogram-driven adaptive chroma contrast
//
// Per-hue-band saturation equalization via CDF LUT:
//   output_sat = lerp(input_sat, CDF_band(input_sat), -(CURVE_STRENGTH/100))
//
// Positive CURVE_STRENGTH = inverse equalization = expands compressed saturation.
// Negative = forward equalization = compresses saturation.
//
// The grey gate (SAT_THRESHOLD equivalent) is computed automatically each frame
// from the scene's own saturation CDF — no manual tuning needed.
//
// Three passes:
//   Pass 1 — BuildSatCDF: cumulative histogram per hue band into SatCDFTex.
//   Pass 2 — ComputeSatGate: walks SatCDFTex to find scene 10th-percentile
//             saturation, stores in SatGateTex (1×1).
//   Pass 3 — ApplyChromaLift: smoothstep gate from SatGateTex, apply curve.
//
// Requires frame_analysis.fx to run before this in the chain.

#define CURVE_STRENGTH  15     // -100 to 100; positive = expands, negative = compresses. Scale feels logarithmic — small values (5–25) have strong effect, use fine steps. 15 = technical baseline (recover game compression only).

// ─── Internal constants ────────────────────────────────────────────────────
#define LERP_SPEED      0.5     // 0–100; temporal smoothing rate for CDF
#define BAND_WIDTH      0.15
#define HIST_BINS       64
#define GATE_PERCENTILE 0.10    // bottom 10% of scene saturation = grey floor

static const float kBandCenters[6] = {
    0.0/360.0, 60.0/360.0, 120.0/360.0, 180.0/360.0, 240.0/360.0, 300.0/360.0
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

// ─── Per-band saturation CDF LUT — 64×6 R32F ──────────────────────────────
texture2D SatCDFTex { Width = HIST_BINS; Height = 6; Format = R32F; MipLevels = 1; };
sampler2D SatCDF
{
    Texture   = SatCDFTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// ─── Adaptive grey gate — 1×1, updated each frame ─────────────────────────
texture2D SatGateTex { Width = 1; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D SatGate
{
    Texture   = SatGateTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
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
    float speed    = (prev_max < 0.5) ? 1.0 : clamp(LERP_SPEED / 100.0, 0.001, 1.0);

    return float4(lerp(prev, cdf, speed), 0, 0, 1);
}

// ─── Pass 2 — Compute adaptive grey gate ───────────────────────────────────
// Walks the average CDF across all 6 bands to find the saturation value at
// GATE_PERCENTILE. Pixels below this level are the scene's grey floor.
// Runs on a 1×1 target — negligible cost.

float4 ComputeSatGatePS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    [loop]
    for (int i = 1; i < HIST_BINS; i++)
    {
        float sat_val = (i + 0.5) / float(HIST_BINS);
        float avg_cdf = 0.0;

        [loop]
        for (int band = 0; band < 6; band++)
        {
            float row_v = (band + 0.5) / 6.0;
            avg_cdf += tex2Dlod(SatCDF, float4(sat_val, row_v, 0, 0)).r;
        }
        avg_cdf /= 6.0;

        if (avg_cdf >= GATE_PERCENTILE)
            return float4(sat_val, 0, 0, 1);
    }

    return float4(1.0 / float(HIST_BINS), 0, 0, 1);
}

// ─── Pass 3 — Apply per-band CDF saturation curve ──────────────────────────

float4 ApplyChromaLiftPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2488 && pos.x < 2500 && pos.y > 15 && pos.y < 27)
        return float4(0.9, 0.3, 0.1, 1.0);

    float4 col = tex2D(BackBuffer, uv);
    float3 hsv = RGBtoHSV(col.rgb);

    float gate_sat = tex2D(SatGate, float2(0.5, 0.5)).r;
    float gate     = smoothstep(gate_sat * 0.5, gate_sat * 1.5, hsv.y);

    if (gate < 0.001) return col;

    float new_sat = 0.0;
    float total_w = 0.0;

    for (int b = 0; b < 6; b++)
    {
        float w         = HueBandWeight(hsv.x, kBandCenters[b]);
        float row_v     = (b + 0.5) / 6.0;
        float equalized = tex2D(SatCDF, float2(hsv.y, row_v)).r;
        float band_sat  = lerp(hsv.y, equalized, -(CURVE_STRENGTH / 100.0));

        new_sat += band_sat * w;
        total_w += w;
    }

    float final_sat = (total_w > 0.001) ? new_sat / total_w : hsv.y;
    float3 processed = HSVtoRGB(float3(hsv.x, final_sat, hsv.z));
    return float4(lerp(col.rgb, processed, gate), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique AlphaChromaLift
{
    pass BuildSatCDF
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildSatCDFPS;
        RenderTarget = SatCDFTex;
    }
    pass ComputeSatGate
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeSatGatePS;
        RenderTarget = SatGateTex;
    }
    pass ApplyChromaLift
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyChromaLiftPS;
    }
}
