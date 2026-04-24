// pro_mist.fx — Black Pro-Mist diffusion filter
//
// Simulates the optical softness of a Black Pro-Mist glass filter:
// removes the clinical digital edge without adding bloom or glow.
// Highlights stay bright but lose the pixel-perfect hardness.
//
// Uses bilateral Gaussian: each tap is weighted by both spatial distance
// AND luma similarity to the center pixel. Prevents bright regions (fog,
// sky lights) from bleeding into dark surroundings — no halo artifacts.
//
// Bilateral sigma_r adapts per-pixel from local luma variance (SVGF principle):
// high-variance areas (edges, detail) → tight range kernel (preserves sharpness);
// smooth areas → wide range kernel (more averaging, softer result).
//
// Diffuse strength adapts to scene contrast (p90–p10 from LumHistTex):
// high-contrast scenes get slightly more softening, flat scenes less.
//
// Four passes:
//   Pass 1: Compute scene contrast → ContrastTex (1×1)
//   Pass 2: Compute local luma variance → VarianceTex (full res)
//   Pass 3: Bilateral horizontal Gaussian → DiffuseTex
//   Pass 4: Bilateral vertical Gaussian on DiffuseTex + blend onto scene

// ─── Tuning ────────────────────────────────────────────────────────────────

#define DIFFUSE_STRENGTH  0.14   // 0–1; softness intensity
#define DIFFUSE_RADIUS    0.020  // physical blur width

// ─── Internal constants ────────────────────────────────────────────────────

#define HIST_BINS          64
#define BILATERAL_K_LO     5.0   // smooth area — wide range kernel
#define BILATERAL_K_HI     50.0  // edge area — tight range kernel
#define VAR_THRESH         0.02  // variance at which K saturates to HI
#define DIFFUSE_LUMA_LO    0.62
#define DIFFUSE_LUMA_HI    0.65
#define DIFFUSE_LUMA_CAP   0.88
#define DIFFUSE_LUMA_GREEN 0.10

// ─── Shared histogram texture — previous frame, from frame_analysis ────────

texture2D LumHistTex { Width = HIST_BINS; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumHist
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Scene contrast (p90–p10) — 1×1 ──────────────────────────────────────

texture2D ContrastTex { Width = 1; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D ContrastSamp
{
    Texture   = ContrastTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Per-pixel luma variance — full res R16F ───────────────────────────────

texture2D VarianceTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; MipLevels = 1; };
sampler2D VarianceSamp
{
    Texture   = VarianceTex;
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

texture2D DiffuseTex
{
    Width     = BUFFER_WIDTH;
    Height    = BUFFER_HEIGHT;
    Format    = RGBA16F;
    MipLevels = 1;
};
sampler2D DiffuseSamp
{
    Texture   = DiffuseTex;
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

// 9-tap Gaussian weights (sigma ≈ 1.5, normalised)
static const float GW[5] = { 0.2270, 0.1945, 0.1216, 0.0540, 0.0162 };

float BilateralW(float luma_c, float luma_tap, float gw, float k)
{
    float d = luma_c - luma_tap;
    return gw * exp(-d * d * k);
}

// ─── Pass 1 — Compute scene contrast (p90–p10) ─────────────────────────────

float4 ComputeContrastPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    float total = 0.0;
    [loop]
    for (int i = 0; i < HIST_BINS; i++)
        total += tex2Dlod(LumHist, float4((i + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r;

    if (total < 0.001) return float4(0.5, 0, 0, 1);

    float cumulative = 0.0;
    float p10 = 0.0, p90 = 1.0;
    bool found_p10 = false;

    [loop]
    for (int j = 0; j < HIST_BINS; j++)
    {
        cumulative += tex2Dlod(LumHist, float4((j + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r / total;
        if (!found_p10 && cumulative >= 0.10) { p10 = (j + 0.5) / float(HIST_BINS); found_p10 = true; }
        if (cumulative >= 0.90) { p90 = (j + 0.5) / float(HIST_BINS); break; }
    }

    return float4(p90 - p10, 0, 0, 1);
}

// ─── Pass 2 — Compute per-pixel local luma variance ───────────────────────
// 5-tap cross neighborhood. Drives bilateral range kernel width in H/V passes:
// low variance (smooth) → soft bilateral; high variance (edges) → tight bilateral.

float4 ComputeVariancePS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    float2 px = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float l0 = Luma(tex2Dlod(BackBuffer, float4(uv,                        0, 0)).rgb);
    float l1 = Luma(tex2Dlod(BackBuffer, float4(uv + float2( 1,  0) * px, 0, 0)).rgb);
    float l2 = Luma(tex2Dlod(BackBuffer, float4(uv + float2(-1,  0) * px, 0, 0)).rgb);
    float l3 = Luma(tex2Dlod(BackBuffer, float4(uv + float2( 0,  1) * px, 0, 0)).rgb);
    float l4 = Luma(tex2Dlod(BackBuffer, float4(uv + float2( 0, -1) * px, 0, 0)).rgb);
    float mean = (l0 + l1 + l2 + l3 + l4) * 0.2;
    float d0 = l0 - mean, d1 = l1 - mean, d2 = l2 - mean, d3 = l3 - mean, d4 = l4 - mean;
    float var = (d0*d0 + d1*d1 + d2*d2 + d3*d3 + d4*d4) * 0.2;
    return float4(var, 0, 0, 1);
}

// ─── Pass 3 — Bilateral horizontal Gaussian ────────────────────────────────

float4 DiffuseHPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 center = tex2D(BackBuffer, uv).rgb;
    float  lc     = Luma(center);
    float2 st     = float2(DIFFUSE_RADIUS / 4.0, 0.0);

    float var = tex2D(VarianceSamp, uv).r;
    float k   = lerp(BILATERAL_K_LO, BILATERAL_K_HI, saturate(var / VAR_THRESH));

    float3 r = center * GW[0];
    float  w = GW[0];

    [loop]
    for (int i = 1; i <= 4; i++)
    {
        float3 tp = tex2D(BackBuffer, uv + st * i).rgb;
        float3 tn = tex2D(BackBuffer, uv - st * i).rgb;
        float  wp = BilateralW(lc, Luma(tp), GW[i], k);
        float  wn = BilateralW(lc, Luma(tn), GW[i], k);
        r += tp * wp + tn * wn;
        w += wp + wn;
    }

    return float4(r / w, 1.0);
}

// ─── Pass 4 — Bilateral vertical Gaussian + composite ──────────────────────

float4 DiffuseVPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    if (pos.x > 2518 && pos.x < 2530 && pos.y > 15 && pos.y < 27)
        return float4(0.9, 0.1, 0.9, 1.0);

    float4 base = tex2D(BackBuffer, uv);
    float  lc   = Luma(base.rgb);
    float2 ds   = float2(0.0, DIFFUSE_RADIUS / 4.0);

    float var = tex2D(VarianceSamp, uv).r;
    float k   = lerp(BILATERAL_K_LO, BILATERAL_K_HI, saturate(var / VAR_THRESH));

    float3 diffused = tex2D(DiffuseSamp, uv).rgb * GW[0];
    float  w        = GW[0];

    [loop]
    for (int i = 1; i <= 4; i++)
    {
        float3 tp = tex2D(DiffuseSamp, uv + ds * i).rgb;
        float3 tn = tex2D(DiffuseSamp, uv - ds * i).rgb;
        float  wp = BilateralW(lc, Luma(tp), GW[i], k);
        float  wn = BilateralW(lc, Luma(tn), GW[i], k);
        diffused += tp * wp + tn * wn;
        w        += wp + wn;
    }
    diffused /= w;

    // Luma gate — softening strongest on highlights, fades in shadows and near-whites
    // Green extension: dark green-dominant pixels get lower gate start
    float g_dom   = saturate((base.g - max(base.r, base.b)) * 3.0);
    float diff_lo = lerp(DIFFUSE_LUMA_LO, DIFFUSE_LUMA_GREEN, g_dom);
    float luma_b  = lc;
    float diff_luma = smoothstep(diff_lo, DIFFUSE_LUMA_HI, luma_b)
                    * (1.0 - smoothstep(DIFFUSE_LUMA_CAP, 1.0, luma_b));

    float contrast     = tex2D(ContrastSamp, float2(0.5, 0.5)).r;
    float adaptive_str = DIFFUSE_STRENGTH * lerp(0.7, 1.3, saturate(contrast / 0.5));

    float3 result = lerp(base.rgb, diffused, adaptive_str * diff_luma * luma_b);
    return float4(saturate(result), base.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique ProMist
{
    pass ComputeContrast
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeContrastPS;
        RenderTarget = ContrastTex;
    }
    pass ComputeVariance
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeVariancePS;
        RenderTarget = VarianceTex;
    }
    pass DiffuseH
    {
        VertexShader = PostProcessVS;
        PixelShader  = DiffuseHPS;
        RenderTarget = DiffuseTex;
    }
    pass DiffuseV
    {
        VertexShader = PostProcessVS;
        PixelShader  = DiffuseVPS;
    }
}
