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
// Two passes:
//   Pass 1: Bilateral horizontal Gaussian → DiffuseTex
//   Pass 2: Bilateral vertical Gaussian on DiffuseTex + blend onto scene

// ─── Tuning ────────────────────────────────────────────────────────────────

#define DIFFUSE_STRENGTH  0.14   // 0–1; softness intensity
#define DIFFUSE_RADIUS    0.020  // physical blur width

// ─── Internal constants ────────────────────────────────────────────────────

#define BILATERAL_K        20.0  // luma similarity strictness — higher = tighter edge preservation
#define DIFFUSE_LUMA_LO    0.62
#define DIFFUSE_LUMA_HI    0.65
#define DIFFUSE_LUMA_CAP   0.88
#define DIFFUSE_LUMA_GREEN 0.10

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

float BilateralW(float luma_c, float luma_tap, float gw)
{
    float d = luma_c - luma_tap;
    return gw * exp(-d * d * BILATERAL_K);
}

// ─── Pass 1 — Bilateral horizontal Gaussian ────────────────────────────────

float4 DiffuseHPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 center = tex2D(BackBuffer, uv).rgb;
    float  lc     = Luma(center);
    float2 st     = float2(DIFFUSE_RADIUS / 4.0, 0.0);

    float3 r = center * GW[0];
    float  w = GW[0];

    [loop]
    for (int i = 1; i <= 4; i++)
    {
        float3 tp = tex2D(BackBuffer, uv + st * i).rgb;
        float3 tn = tex2D(BackBuffer, uv - st * i).rgb;
        float  wp = BilateralW(lc, Luma(tp), GW[i]);
        float  wn = BilateralW(lc, Luma(tn), GW[i]);
        r += tp * wp + tn * wn;
        w += wp + wn;
    }

    return float4(r / w, 1.0);
}

// ─── Pass 2 — Bilateral vertical Gaussian + composite ──────────────────────

float4 DiffuseVPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    if (pos.x > 2518 && pos.x < 2530 && pos.y > 15 && pos.y < 27)
        return float4(0.9, 0.1, 0.9, 1.0);

    float4 base = tex2D(BackBuffer, uv);
    float  lc   = Luma(base.rgb);
    float2 ds   = float2(0.0, DIFFUSE_RADIUS / 4.0);

    float3 diffused = tex2D(DiffuseSamp, uv).rgb * GW[0];
    float  w        = GW[0];

    [loop]
    for (int i = 1; i <= 4; i++)
    {
        float3 tp = tex2D(DiffuseSamp, uv + ds * i).rgb;
        float3 tn = tex2D(DiffuseSamp, uv - ds * i).rgb;
        float  wp = BilateralW(lc, Luma(tp), GW[i]);
        float  wn = BilateralW(lc, Luma(tn), GW[i]);
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

    float3 result = lerp(base.rgb, diffused, DIFFUSE_STRENGTH * diff_luma * luma_b);
    return float4(saturate(result), base.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique ProMist
{
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
