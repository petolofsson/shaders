// retinal_vignette.fx — Peripheral luminance and chroma falloff
//
// Two complementary retinal effects on the same Gaussian radial mask:
//
//   1. SCE luminance falloff — Gaussian darkening toward periphery.
//      Stiles-Crawford effect: photopic, driven by p50. Absent in dark scenes.
//
//   2. Purkinje chroma falloff — Oklab chroma reduction toward periphery.
//      Rod dominance: rods carry no colour. Enhanced in dark/mesopic scenes.
//
// Both effects are multiplicative or subtractive on chroma — cannot exceed
// input, cannot clip. SDR safe by construction.
//
// Shared texture contract:
//   PercTex { Width=1; Height=1; Format=RGBA16F } — written by analysis_frame
//   r=p25, g=p50, b=p75, a=iqr

#include "creative_values.fx"

// ─── Shared textures ──────────────────────────────────────────────────────

texture2D PercTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D PercSamp
{
    Texture   = PercTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

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

// ─── Oklab ────────────────────────────────────────────────────────────────

float3 RGBtoOKLab(float3 c)
{
    float l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
    float m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
    float s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;

    l = pow(l + 1e-6, 0.333333);
    m = pow(m + 1e-6, 0.333333);
    s = pow(s + 1e-6, 0.333333);

    return float3(
         0.2104542553*l + 0.7936177850*m - 0.0040720468*s,
         1.9779984951*l - 2.4285922050*m + 0.4505937099*s,
         0.0259040371*l + 0.7827717662*m - 0.8086757660*s
    );
}

float3 OKLabtoRGB(float3 lab)
{
    float l_ = lab.x + 0.3963377774*lab.y + 0.2158037573*lab.z;
    float m_ = lab.x - 0.1055613458*lab.y - 0.0638541728*lab.z;
    float s_ = lab.x - 0.0894841775*lab.y - 1.2914855480*lab.z;

    float l = l_*l_*l_;
    float m = m_*m_*m_;
    float s = s_*s_*s_;

    return float3(
         4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
        -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
        -0.0041960863*l - 0.7034186147*m + 1.7076147010*s
    );
}

// ─── Pass ─────────────────────────────────────────────────────────────────

float4 RetinalVignettePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;

    float4 perc = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));

    // Aspect-corrected Gaussian: 1 at centre, falls toward corners
    float2 uv_c  = (uv - 0.5) * float2(float(BUFFER_WIDTH) / float(BUFFER_HEIGHT), 1.0);
    float  r2    = dot(uv_c, uv_c);
    float  gauss = exp(-r2 / (VIGN_RADIUS * VIGN_RADIUS));

    // ── 1. SCE luminance darkening ─────────────────────────────────────────
    float sc_att  = smoothstep(0.04, 0.30, perc.g);
    float vweight = lerp(1.0 - VIGN_STRENGTH, 1.0, gauss);
    vweight       = lerp(1.0, vweight, sc_att);     // dark scenes → identity
    float3 rgb    = col.rgb * vweight;

    // ── 2. Purkinje chroma falloff ─────────────────────────────────────────
    float purkinje  = lerp(1.0, 1.3, 1.0 - saturate(perc.g / 0.25));
    float chroma_r  = saturate((1.0 - gauss) * VIGN_CHROMA * purkinje);
    float3 lab      = RGBtoOKLab(rgb);
    lab.yz         *= 1.0 - chroma_r;  // scale chroma axes, L untouched
    rgb             = saturate(OKLabtoRGB(lab));

    return float4(rgb, col.a);
}

// ─── Technique ────────────────────────────────────────────────────────────

technique RetinalVignette
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = RetinalVignettePS;
    }
}
