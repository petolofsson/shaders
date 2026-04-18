// gzw_ca.fx — Radial chromatic aberration
//
// Color channels separate toward screen edges and corners.
// Center of frame is clean — fringe grows with distance from center.
// Mimics lens barrel distortion on cheaper/wider primes.
//
// Red shifts outward, blue shifts inward, green stays fixed.
// Strength is in UV space — very small values go a long way.

// ─── Tuning ────────────────────────────────────────────────────────────────

#define CA_STRENGTH  0.0024  // channel offset at corners (UV space) — keep very low

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

float4 ChromaticAberrationPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 center  = uv - 0.5;
    float  dist    = length(center);

    // Luma-weighted offset — fringe concentrates on bright highlights and edges,
    // barely fires in dark areas where CA is physically imperceptible
    float3 base    = tex2D(BackBuffer, uv).rgb;
    float  luma_w  = dot(base, float3(0.2126, 0.7152, 0.0722));
           luma_w  = luma_w * luma_w;   // quadratic — concentrated at brightest
    float2 dir     = center * dist * CA_STRENGTH * luma_w;

    float r = tex2D(BackBuffer, uv + dir).r;
    float g = base.g;
    float b = tex2D(BackBuffer, uv - dir).b;
    return float4(r, g, b, tex2D(BackBuffer, uv).a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique ChromaticAberration
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = ChromaticAberrationPS;
    }
}
