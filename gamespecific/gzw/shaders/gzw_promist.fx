// gzw_promist.fx — Black Pro-Mist 1/4 simulation
//
// Two components — both present in the real filter:
//
//   1. Scatter/halation: bright areas bleed light outward additively.
//      Dual Kawase blur (2-level pyramid): smooth wide falloff, no halo rings at
//      object edges. The pyramid downsamples before blurring so edge information is
//      naturally soft — there is no hard kernel cutoff that can fringe.
//      Power-weighted extraction (luma^N), no hard threshold.
//      Blacks fully preserved — additive blend adds nothing to dark pixels.
//
//   2. Diffusion: gentle full-image softness blended uniformly at low opacity.
//      Separable Gaussian — small radius, removes the clinical digital edge.
//
// Passes:
//   Pass 1: Extract (luma^EXTRACT_POWER weighted) → BloomExtractTex (full res)
//   Pass 2: Diffuse horizontal Gaussian           → DiffuseTex (full res)
//   Pass 3: Kawase downsample full→half           → BloomHalfTex
//   Pass 4: Kawase downsample half→quarter        → BloomQuarterTex
//   Pass 5: Kawase upsample quarter→half          → BloomHalfTex (overwrite)
//   Pass 6: Kawase upsample half→full (inline) + diffuse V + combine → screen

// ─── Tuning ────────────────────────────────────────────────────────────────

// Scatter (halation)
#define EXTRACT_POWER     2.20   // selectivity: lower = whole canopy glows, higher = hottest pixels only
#define SCATTER_SPREAD    (BUFFER_WIDTH * 0.00176)    // Kawase tap scale — constant screen fraction (≈4.50px @ 2560)
#define SCATTER_STRENGTH  0.46   // additive blend strength (pyramid averaging reduces peak — tune up vs Gaussian)

// Warm tint on scattered layer only
#define WARM_R  1.10
#define WARM_G  1.02
#define WARM_B  0.80

// Diffusion (whole-image softness)
#define DIFFUSE_RADIUS    0.010  // tight — just takes the digital edge off
#define DIFFUSE_STRENGTH  0.185  // blend strength at full luma gate (luma-weighted, so effective midtone ~0.12)
#define DIFFUSE_LUMA_LO   0.50   // diffusion fades in from here (non-green pixels)
#define DIFFUSE_LUMA_HI   0.65   // full diffusion strength above here (highlights, skin)
#define DIFFUSE_LUMA_CAP  0.88   // diffusion fades back out above here (near-whites stay crisp)
#define DIFFUSE_LUMA_GREEN 0.10  // extended gate for green pixels — catches dark foliage

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

// Extracted highlights — full resolution
texture2D BloomExtractTex
{
    Width     = BUFFER_WIDTH;
    Height    = BUFFER_HEIGHT;
    Format    = RGBA16F;
    MipLevels = 1;
};
sampler2D BloomExtractSamp
{
    Texture   = BloomExtractTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Scatter pyramid — half resolution (written by down pass, overwritten by up pass)
texture2D BloomHalfTex
{
    Width     = BUFFER_WIDTH  / 2;
    Height    = BUFFER_HEIGHT / 2;
    Format    = RGBA16F;
    MipLevels = 1;
};
sampler2D BloomHalfSamp
{
    Texture   = BloomHalfTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Scatter pyramid — quarter resolution
texture2D BloomQuarterTex
{
    Width     = BUFFER_WIDTH  / 4;
    Height    = BUFFER_HEIGHT / 4;
    Format    = RGBA16F;
    MipLevels = 1;
};
sampler2D BloomQuarterSamp
{
    Texture   = BloomQuarterTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Diffuse intermediate — horizontal blur
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

// 9-tap Gaussian weights (sigma ≈ 1.5, normalised) — diffuse only
static const float GW[5] = { 0.2270, 0.1945, 0.1216, 0.0540, 0.0162 };

// ─── Pass 1 — Extract ──────────────────────────────────────────────────────

float4 ExtractPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 c = tex2D(BackBuffer, uv).rgb;
    // NVG gate — NVG green has near-zero blue, real scene content always has meaningful blue
    float not_nvg = smoothstep(0.05, 0.18,c.b);
    return float4(c * pow(saturate(Luma(c)), EXTRACT_POWER) * not_nvg, 1.0);
}

// ─── Pass 2 — Diffuse horizontal Gaussian ──────────────────────────────────

float4 DiffuseHPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 st = float2(DIFFUSE_RADIUS / 4.0, 0.0);
    float3 r  = tex2D(BackBuffer, uv).rgb         * GW[0];
    r += tex2D(BackBuffer, uv + st * 1.0).rgb     * GW[1];
    r += tex2D(BackBuffer, uv - st * 1.0).rgb     * GW[1];
    r += tex2D(BackBuffer, uv + st * 2.0).rgb     * GW[2];
    r += tex2D(BackBuffer, uv - st * 2.0).rgb     * GW[2];
    r += tex2D(BackBuffer, uv + st * 3.0).rgb     * GW[3];
    r += tex2D(BackBuffer, uv - st * 3.0).rgb     * GW[3];
    r += tex2D(BackBuffer, uv + st * 4.0).rgb     * GW[4];
    r += tex2D(BackBuffer, uv - st * 4.0).rgb     * GW[4];
    return float4(r, 1.0);
}

// ─── Pass 3 — Kawase downsample full→half ──────────────────────────────────
// Viewport: BUFFER_WIDTH/2 × BUFFER_HEIGHT/2
// Source texel: 1/BUFFER_WIDTH, 1/BUFFER_HEIGHT (BloomExtractTex)

float4 KawaseDown1PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 st = float2(SCATTER_SPREAD / BUFFER_WIDTH, SCATTER_SPREAD / BUFFER_HEIGHT);
    float3 sum  = tex2D(BloomExtractSamp, uv).rgb * 4.0;
    sum += tex2D(BloomExtractSamp, uv + float2(-st.x, -st.y) * 0.5).rgb;
    sum += tex2D(BloomExtractSamp, uv + float2( st.x, -st.y) * 0.5).rgb;
    sum += tex2D(BloomExtractSamp, uv + float2(-st.x,  st.y) * 0.5).rgb;
    sum += tex2D(BloomExtractSamp, uv + float2( st.x,  st.y) * 0.5).rgb;
    return float4(sum / 8.0, 1.0);
}

// ─── Pass 4 — Kawase downsample half→quarter ───────────────────────────────
// Viewport: BUFFER_WIDTH/4 × BUFFER_HEIGHT/4
// Source texel: 2/BUFFER_WIDTH, 2/BUFFER_HEIGHT (BloomHalfTex)

float4 KawaseDown2PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 st = float2(SCATTER_SPREAD * 2.0 / BUFFER_WIDTH, SCATTER_SPREAD * 2.0 / BUFFER_HEIGHT);
    float3 sum  = tex2D(BloomHalfSamp, uv).rgb * 4.0;
    sum += tex2D(BloomHalfSamp, uv + float2(-st.x, -st.y) * 0.5).rgb;
    sum += tex2D(BloomHalfSamp, uv + float2( st.x, -st.y) * 0.5).rgb;
    sum += tex2D(BloomHalfSamp, uv + float2(-st.x,  st.y) * 0.5).rgb;
    sum += tex2D(BloomHalfSamp, uv + float2( st.x,  st.y) * 0.5).rgb;
    return float4(sum / 8.0, 1.0);
}

// ─── Pass 5 — Kawase upsample quarter→half ─────────────────────────────────
// Viewport: BUFFER_WIDTH/2 × BUFFER_HEIGHT/2
// Source texel: 4/BUFFER_WIDTH, 4/BUFFER_HEIGHT (BloomQuarterTex)

float4 KawaseUp1PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 st = float2(SCATTER_SPREAD * 4.0 / BUFFER_WIDTH, SCATTER_SPREAD * 4.0 / BUFFER_HEIGHT);
    float3 sum;
    sum  = tex2D(BloomQuarterSamp, uv + float2(-st.x,  0.0)).rgb * 2.0;
    sum += tex2D(BloomQuarterSamp, uv + float2( st.x,  0.0)).rgb * 2.0;
    sum += tex2D(BloomQuarterSamp, uv + float2( 0.0, -st.y)).rgb * 2.0;
    sum += tex2D(BloomQuarterSamp, uv + float2( 0.0,  st.y)).rgb * 2.0;
    sum += tex2D(BloomQuarterSamp, uv + float2(-st.x, -st.y)).rgb;
    sum += tex2D(BloomQuarterSamp, uv + float2( st.x, -st.y)).rgb;
    sum += tex2D(BloomQuarterSamp, uv + float2(-st.x,  st.y)).rgb;
    sum += tex2D(BloomQuarterSamp, uv + float2( st.x,  st.y)).rgb;
    return float4(sum / 12.0, 1.0);
}

// ─── Pass 6 — Kawase upsample half→full (inline) + diffuse V + combine ─────
// Viewport: BUFFER_WIDTH × BUFFER_HEIGHT
// Scatter source texel: 2/BUFFER_WIDTH, 2/BUFFER_HEIGHT (BloomHalfTex)

float4 CombinePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 base = tex2D(BackBuffer, uv);

    // Scatter — Kawase upsample half→full, then warm tint
    float2 ss = float2(SCATTER_SPREAD * 2.0 / BUFFER_WIDTH, SCATTER_SPREAD * 2.0 / BUFFER_HEIGHT);
    float3 scattered;
    scattered  = tex2D(BloomHalfSamp, uv + float2(-ss.x,  0.0)).rgb * 2.0;
    scattered += tex2D(BloomHalfSamp, uv + float2( ss.x,  0.0)).rgb * 2.0;
    scattered += tex2D(BloomHalfSamp, uv + float2( 0.0, -ss.y)).rgb * 2.0;
    scattered += tex2D(BloomHalfSamp, uv + float2( 0.0,  ss.y)).rgb * 2.0;
    scattered += tex2D(BloomHalfSamp, uv + float2(-ss.x, -ss.y)).rgb;
    scattered += tex2D(BloomHalfSamp, uv + float2( ss.x, -ss.y)).rgb;
    scattered += tex2D(BloomHalfSamp, uv + float2(-ss.x,  ss.y)).rgb;
    scattered += tex2D(BloomHalfSamp, uv + float2( ss.x,  ss.y)).rgb;
    scattered /= 12.0;
    scattered.r *= WARM_R;
    scattered.g *= WARM_G;
    scattered.b *= WARM_B;

    // Diffuse — vertical Gaussian on DiffuseTex
    float2 ds = float2(0.0, DIFFUSE_RADIUS / 4.0);
    float3 diffused  = tex2D(DiffuseSamp, uv).rgb           * GW[0];
    diffused += tex2D(DiffuseSamp, uv + ds * 1.0).rgb       * GW[1];
    diffused += tex2D(DiffuseSamp, uv - ds * 1.0).rgb       * GW[1];
    diffused += tex2D(DiffuseSamp, uv + ds * 2.0).rgb       * GW[2];
    diffused += tex2D(DiffuseSamp, uv - ds * 2.0).rgb       * GW[2];
    diffused += tex2D(DiffuseSamp, uv + ds * 3.0).rgb       * GW[3];
    diffused += tex2D(DiffuseSamp, uv - ds * 3.0).rgb       * GW[3];
    diffused += tex2D(DiffuseSamp, uv + ds * 4.0).rgb       * GW[4];
    diffused += tex2D(DiffuseSamp, uv - ds * 4.0).rgb       * GW[4];

    // NVG gate — suppress diffuse softening on NVG pixels (near-zero blue)
    float not_nvg = smoothstep(0.05, 0.18,base.b);

    // Luma gate — diffusion strongest on highlights, fades out toward shadows
    // Matches physical Pro-Mist behaviour: bright areas soften, darks stay crisp
    // Green extension: dark foliage gets a lower gate start so stems/dark leaves included
    float g_dom   = saturate((base.g - max(base.r, base.b)) * 3.0);
    float diff_lo = lerp(DIFFUSE_LUMA_LO, DIFFUSE_LUMA_GREEN, g_dom);
    float luma_b  = Luma(base.rgb);
    float diff_luma = smoothstep(diff_lo, DIFFUSE_LUMA_HI, luma_b)
                    * (1.0 - smoothstep(DIFFUSE_LUMA_CAP, 1.0, luma_b));

    float3 result = base.rgb;
    // Luma-weighted diffuse: bright highlights soften most, darks stay crisp
    result = lerp(result, diffused, DIFFUSE_STRENGTH * not_nvg * diff_luma * luma_b);
    float headroom = 1.0 - Luma(result) * 0.65;
    result = saturate(result + scattered * SCATTER_STRENGTH * headroom);

    return float4(result, base.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique ProMist
{
    pass Extract
    {
        VertexShader = PostProcessVS;
        PixelShader  = ExtractPS;
        RenderTarget = BloomExtractTex;
    }
    pass DiffuseH
    {
        VertexShader = PostProcessVS;
        PixelShader  = DiffuseHPS;
        RenderTarget = DiffuseTex;
    }
    pass KawaseDown1
    {
        VertexShader = PostProcessVS;
        PixelShader  = KawaseDown1PS;
        RenderTarget = BloomHalfTex;
    }
    pass KawaseDown2
    {
        VertexShader = PostProcessVS;
        PixelShader  = KawaseDown2PS;
        RenderTarget = BloomQuarterTex;
    }
    pass KawaseUp1
    {
        VertexShader = PostProcessVS;
        PixelShader  = KawaseUp1PS;
        RenderTarget = BloomHalfTex;
    }
    pass Combine
    {
        VertexShader = PostProcessVS;
        PixelShader  = CombinePS;
    }
}
