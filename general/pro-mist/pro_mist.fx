// pro_mist.fx — Black Pro-Mist diffusion filter
//
// Single-pass. Uses CreativeLowFreqTex (1/8-res, written by corrective.fx — free)
// as the scatter source. Additive chromatic composite, scene-adaptive from PercTex.
//
// Shared texture contract:
//   PercTex { Width=1; Height=1; Format=RGBA16F } — written by analysis_frame
//   r=p25, g=p50, b=p75, a=iqr
//   CreativeLowFreqTex { Width=BW/8; Height=BH/8; Format=RGBA16F } — written by corrective.fx
//   rgb=full colour, a=luma

#include "debug_text.fxh"
#include "creative_values.fx"

// ─── Shared textures ───────────────────────────────────────────────────────

texture2D PercTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D PercSamp
{
    Texture   = PercTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D CreativeLowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; MipLevels = 3; };
sampler2D CreativeLowFreqSamp
{
    Texture   = CreativeLowFreqTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
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

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ─── Pass — Scatter composite ─────────────────────────────────────────────

float4 ProMistPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 base = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return base;

    float3 diffused = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 0)).rgb;

    float4 perc      = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));
    float  p75       = perc.b;
    float  iqr       = perc.a;
    float  adapt_str = 0.09 * lerp(0.7, 1.3, saturate(iqr / 0.5));

    float  luma_in   = Luma(base.rgb);
    float  gate_lo   = saturate(p75 - 0.12);
    float  gate_hi   = saturate(p75 + 0.06);
    float  luma_gate = smoothstep(gate_lo, gate_hi, luma_in)
                     * (1.0 - smoothstep(0.96, 1.0, luma_in));

    // Additive chromatic composite — red scatters most (film layer physics: R deepest)
    float3 scatter_delta = max(0.0, diffused - base.rgb);
    float3 result = base.rgb + scatter_delta * float3(1.15, 1.00, 0.75) * adapt_str * luma_gate;

    // Clarity: Laplacian residual, bell-weighted to midtones
    float3 detail = base.rgb - diffused;
    float  bell   = luma_in * (1.0 - luma_in) * 4.0;
    result       += adapt_str * 1.10 * detail * bell;

    float4 out_col = float4(saturate(result), base.a);
    out_col = DrawLabel(out_col, pos.xy, 270.0, 58.0,
                        55u, 80u, 77u, 83u, float3(0.9, 0.1, 0.9)); // 7PMS
    return out_col;
}

// ─── Technique ────────────────────────────────────────────────────────────

technique ProMist
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = ProMistPS;
    }
}
