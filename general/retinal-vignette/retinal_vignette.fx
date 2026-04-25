// retinal_vignette.fx — Eccentricity-dependent chroma falloff
//
// Simulates how cone density drops from the fovea to the periphery:
// the further from screen centre, the less chromatic the signal.
// No darkening — purely a chroma reduction toward grey.
//
// Operates in OKLab: L (lightness) preserved exactly, chroma axes (a, b)
// scaled toward zero. This avoids the luminance shifts that HSV desaturation
// introduces.
//
// Falloff: power curve starting just outside the foveal zone (central 5%
// of the half-diagonal, calibrated for 27" @ 65cm). Aspect-ratio corrected
// so the boundary is circular, not oval.
//
// Purkinje adaptation: dark scenes drive stronger peripheral achromacy —
// rod vision dominates in scotopic conditions, pushing the periphery toward
// monochrome. Reads scene p50 from shared PercTex.
//
// Position in chain: last — retinal desaturation is post-receptor/neural,
// applied after all optical effects (pro_mist, veil).
//
// One pass — analytical, no intermediate textures.
//
// Shared texture contract:
//   PercTex { Width=1; Height=1; Format=RGBA16F } — written by frame_analysis
//   r=p25, g=p50, b=p75, a=iqr

#include "creative_values.fx"

#define RETINAL_FOVEAL  0.05   // inner radius (fraction of half-diagonal) with no effect
#define RETINAL_MAX     0.65   // physics limit: max chroma reduction at corners

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

// ─── OKLab (linear RGB ↔ perceptual colour space) ─────────────────────────

float3 RGBtoOKLab(float3 c)
{
    float l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
    float m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
    float s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;

    l = pow(abs(l) + 1e-6, 1.0/3.0) * sign(l);
    m = pow(abs(m) + 1e-6, 1.0/3.0) * sign(m);
    s = pow(abs(s) + 1e-6, 1.0/3.0) * sign(s);

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

// ─── Pass 1 — Retinal chroma falloff ──────────────────────────────────────

float4 RetinalVignettePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;

    // Aspect-corrected distance so falloff is circular
    float  aspect   = float(BUFFER_WIDTH) / float(BUFFER_HEIGHT);
    float2 centered = (uv - 0.5) * float2(aspect, 1.0);
    float  dist     = length(centered);
    float  corner   = length(float2(0.5 * aspect, 0.5));

    // Normalise: 0 at centre, 1 at corners; then subtract foveal dead-zone
    float norm = dist / corner;
    float ecc  = saturate((norm - RETINAL_FOVEAL) / (1.0 - RETINAL_FOVEAL));

    // Power curve — RETINAL_FALLOFF < 1 = slow centre / fast edge (physiological)
    float mask = pow(ecc, RETINAL_FALLOFF);

    // Purkinje shift: dark scenes → stronger peripheral achromacy
    float lum_p50  = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0)).g;
    float purkinje = lerp(1.0, 1.3, 1.0 - saturate(lum_p50 / 0.25));

    float reduction = saturate(mask * RETINAL_MAX * (RETINAL_STRENGTH / 100.0) * purkinje);

    // Scale OKLab chroma toward zero, leave L untouched
    float3 lab = RGBtoOKLab(col.rgb);
    lab.y     *= 1.0 - reduction;
    lab.z     *= 1.0 - reduction;

    return float4(saturate(OKLabtoRGB(lab)), col.a);
}

// ─── Technique ────────────────────────────────────────────────────────────

technique RetinalVignette
{
    pass Apply
    {
        VertexShader = PostProcessVS;
        PixelShader  = RetinalVignettePS;
    }
}
