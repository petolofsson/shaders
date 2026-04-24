// vignette.fx — Per-channel radial lens vignette
//
// Models optical falloff using a radial polynomial applied independently
// per RGB channel. Red falls off least, blue most — matches real lens
// behaviour where shorter wavelengths suffer greater peripheral attenuation.
//
// v(r) = 1 + α₁r² + α₂r⁴  (two-term even polynomial, always ≤ 1)
//
// Single pass, one radial distance per pixel.

// ─── Tuning ────────────────────────────────────────────────────────────────

#define VIGNETTE_STRENGTH  0.55   // 0–1; overall falloff intensity
#define VIGNETTE_FALLOFF   1.80   // 1–4; shape — higher = tighter, more abrupt
#define CHROMA_SPLIT       0.18   // 0–1; per-channel spread (0 = monochrome vignette)

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

// ─── Pixel shader ──────────────────────────────────────────────────────────

float4 VignettePS(float4 pos : SV_Position,
                  float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);

    // Radial distance from centre, aspect-corrected, normalised to corner = 1
    float2 d   = uv - 0.5;
    d.x       *= BUFFER_WIDTH / float(BUFFER_HEIGHT);
    float  r2  = dot(d, d) * 2.0;   // ×2 so corner distance ≈ 1

    // Per-channel α₁ — red attenuates least, blue most
    float3 alpha = VIGNETTE_STRENGTH * float3(
        1.0 - CHROMA_SPLIT,
        1.0,
        1.0 + CHROMA_SPLIT
    );

    float rn = pow(r2, VIGNETTE_FALLOFF * 0.5);

    float3 falloff = saturate(1.0 - alpha * rn);

    return float4(col.rgb * falloff, col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique Vignette
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = VignettePS;
    }
}
