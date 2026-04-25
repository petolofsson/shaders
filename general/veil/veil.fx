// veil.fx — Veiling glare: additive luminance lift
//
// Simulates intraocular scatter / lens internal reflections: a global additive
// lift proportional to scene median luminance, stronger at centre than edges.
//
// Physics: glare is additive scatter — adds a spectrally-shifted floor to every
// channel. Desaturation is a natural side effect (no extra code needed).
// Radial: AR coating reflections are slightly stronger toward the optical axis.
// Tint: float3(1.0, 0.95, 0.80) — leftover spectrum from typical AR coatings.
//
// Run after pro_mist: pro_mist handles spatial highlight glow, veil handles the
// DC offset (global contrast floor).
//
// One pass — reads scene median (p50) from shared PercTex.
//
// Shared texture contract:
//   PercTex { Width=1; Height=1; Format=RGBA16F } — written by frame_analysis
//   r=p25, g=p50, b=p75, a=iqr

#include "creative_values.fx"

#define VEIL_TINT float3(1.0, 0.95, 0.80)  // AR coating amber

// ─── Shared percentile cache ───────────────────────────────────────────────

texture2D PercTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D PercSamp
{
    Texture   = PercTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Textures ─────────────────────────────────────────────────────────────

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// ─── Vertex shader ────────────────────────────────────────────────────────

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ─── Pass 1 — Apply veiling glare ─────────────────────────────────────────

float4 ApplyVeilPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;

    float lum_p50 = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0)).g;

    // Radial: 1.0 at centre, 0.85 at corners (0.707 = max UV distance)
    float dist    = distance(uv, float2(0.5, 0.5));
    float spatial = lerp(1.0, 0.85, saturate(dist / 0.707));

    float3 glare  = lum_p50 * (VEIL_STRENGTH / 100.0) * VEIL_TINT * spatial;

    return float4(saturate(col.rgb + glare), col.a);
}

// ─── Technique ────────────────────────────────────────────────────────────

technique Veil
{
    pass Apply
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyVeilPS;
    }
}
