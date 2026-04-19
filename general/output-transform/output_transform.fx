// output_transform.fx — Display Rendering Transform
//
// Per-channel OpenDRT-style tone curve:
//   f(x) = A * x^c / (x^c + K)
//   A and K derived from two constraints:
//     - f(0.18) = 0.18  (scene grey maps to display grey)
//     - f(1.0)  = 1.0   (scene white maps to display white)
//   Result: smooth toe, slight midtone lift, soft highlight shoulder.
//   Per-channel processing means saturated highlights naturally shift
//   toward pastel/white — no hard clip.
//
// Also applies gamut compression for out-of-gamut negatives.

// ─── Tuning ────────────────────────────────────────────────────────────────

#define CONTRAST         1.35   // curve contrast — affects toe and shoulder steepness
#define CHROMA_COMPRESS  0.25   // 0–1; highlight desaturation strength (0 = none)
#define BLACK_POINT      3.5    // 0–100; black floor lift
#define SAT_MAX          85     // 0–100; gamut compression threshold
#define SAT_BLEND        15     // 0–100; gamut compression strength

// ─── Shared saturation histogram — from frame_analysis ────────────────────

#define HIST_BINS 64

texture2D SatHistTex { Width = HIST_BINS; Height = 6; Format = R32F; MipLevels = 1; };
sampler2D SatHist
{
    Texture   = SatHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Scene average saturation — 1×1 ──────────────────────────────────────

texture2D SceneSatTex { Width = 1; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D SceneSatSamp
{
    Texture   = SceneSatTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

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

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ─── OpenDRT tone curve ─────────────────────────────────────────────────────
// Applied per-channel. Constants K and A solved analytically:
//   grey = 0.18, gc = grey^CONTRAST
//   K = gc*(1-grey)/(grey-gc),  A = 1+K

float3 OpenDRT(float3 x)
{
    const float grey = 0.18;
    float gc = pow(grey, CONTRAST);
    float K  = gc * (1.0 - grey) / (grey - gc);
    float A  = 1.0 + K;

    float3 xc = pow(max(x, 0.0), CONTRAST);
    return A * xc / (xc + K);
}

// ─── Pass 1 — Compute scene average saturation ────────────────────────────
// Mean saturation per hue band = Σ(bin_centre × bin_value) — averages across 6 bands.
// Low sat (fog/storm) → less compress; high sat → more compress.

float4 ComputeSceneSatPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    float total = 0.0;
    [loop]
    for (int band = 0; band < 6; band++)
    {
        float v = (band + 0.5) / 6.0;
        [loop]
        for (int b = 0; b < HIST_BINS; b++)
        {
            float u      = (b + 0.5) / float(HIST_BINS);
            float centre = u;
            total += tex2Dlod(SatHist, float4(u, v, 0, 0)).r * centre;
        }
    }
    return float4(total / 6.0, 0, 0, 1);
}

// ─── Pass 2 — Pixel shader ─────────────────────────────────────────────────

float4 OutputTransformPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2548 && pos.x < 2560 && pos.y > 15 && pos.y < 27)
        return float4(0.45, 0.0, 0.0, 1.0);

    float4 col    = tex2D(BackBuffer, uv);
    float3 result = col.rgb;

    // ── Gamut compression (linear space, before tone curve) ──────────────────
    float luma_gc = Luma(result);
    float under   = saturate(-min(result.r, min(result.g, result.b)) * 10.0);
    result        = lerp(result, float3(luma_gc, luma_gc, luma_gc), under);

    float gc_max  = max(result.r, max(result.g, result.b));
    float gc_min  = min(result.r, min(result.g, result.b));
    float sat_gc  = (gc_max > 0.001) ? (gc_max - gc_min) / gc_max : 0.0;
    float excess  = max(0.0, sat_gc - SAT_MAX / 100.0) / (1.0 - SAT_MAX / 100.0);
    float gc_amt  = excess * excess * (SAT_BLEND / 100.0);
    result        = result + (gc_max - result) * gc_amt;

    // ── Black lift ────────────────────────────────────────────────────────────
    result = result * (1.0 - BLACK_POINT / 100.0) + BLACK_POINT / 100.0;

    // ── OpenDRT per-channel tone curve ────────────────────────────────────────
    result = OpenDRT(result);

    // ── Highlight chroma compression ──────────────────────────────────────────
    // Scales with scene saturation: vivid scenes need more compress, flat less.
    float avg_sat        = tex2D(SceneSatSamp, float2(0.5, 0.5)).r;
    float adaptive_comp  = CHROMA_COMPRESS * lerp(0.5, 1.5, saturate(avg_sat * 5.0));
    float luma_post      = Luma(result);
    float hl_gate        = smoothstep(0.65, 1.0, luma_post);
    result               = lerp(result, float3(luma_post, luma_post, luma_post),
                                hl_gate * adaptive_comp);

    return saturate(float4(result, col.a));
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique OutputTransform
{
    pass ComputeSceneSat
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeSceneSatPS;
        RenderTarget = SceneSatTex;
    }
    pass Apply
    {
        VertexShader = PostProcessVS;
        PixelShader  = OutputTransformPS;
    }
}
