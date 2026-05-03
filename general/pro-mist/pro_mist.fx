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

// R46: highlight warm bias EMA (written by corrective.fx WarmBias pass)
texture2D WarmBiasTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D WarmBiasSamp
{
    Texture   = WarmBiasTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// Zone global stats — col 6 of ChromaHistoryTex: r=log_key, g=zone_std, b=zmin, a=zmax
texture2D ChromaHistoryTex { Width = 8; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D ChromaHistSamp
{
    Texture   = ChromaHistoryTex;
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

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ─── Pass — Scatter composite ─────────────────────────────────────────────

float4 ProMistPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 base = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return base;

    // R55: multi-scale scatter — blend mip 0 (tight) and mip 1 (wider) driven by scene contrast
    float3 diffuse0 = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 0)).rgb;
    float3 diffuse1 = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).rgb;

    float4 perc      = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));
    float  p75       = perc.b;
    float  iqr       = perc.b - perc.r;
    float  adapt_str = MIST_STRENGTH * 0.09 * lerp(0.7, 1.3, saturate(iqr / 0.5));
    // R80B: scene-key adaptive — dark scenes get more mist, bright exteriors less
    float zone_log_key   = tex2Dlod(ChromaHistSamp, float4(6.5 / 8.0, 0.5 / 4.0, 0, 0)).r;
    float mist_key_scale = lerp(1.30, 0.80, smoothstep(0.05, 0.25, zone_log_key));
    // R80C: aperture proxy — low EXPOSURE (wide aperture equivalent) → more scatter
    float mist_ap_scale  = lerp(1.10, 0.90, saturate((EXPOSURE - 0.70) / 0.60));
    adapt_str *= mist_key_scale * mist_ap_scale;

    float  scene_softness = smoothstep(0.1, 0.4, iqr);
    float3 diffused       = lerp(diffuse0, diffuse1, scene_softness * 0.35);

    float  luma_in   = Luma(base.rgb);
    float  gate_lo   = saturate(p75);
    float  gate_hi   = saturate(p75 + 0.18);
    float  luma_gate = smoothstep(gate_lo, gate_hi, luma_in)
                     * (1.0 - smoothstep(0.96, 1.0, luma_in));

    // R46: adapt scatter weights to scene warmth — warm scene → neutral scatter
    float  warm_bias = tex2Dlod(WarmBiasSamp, float4(0.5, 0.5, 0, 0)).r;
    float  scatter_r = lerp(1.05, 1.00, smoothstep(0.02, 0.12, warm_bias));
    float  scatter_b = lerp(0.92, 1.00, smoothstep(0.02, 0.12, warm_bias));

    // R55: bidirectional scatter — Pro-Mist reduces contrast (not purely additive glow)
    float3 scatter_delta = (diffused - base.rgb) * adapt_str * luma_gate;
    // R80A: warm scatter bias — practical lights are warm; scatter inherits their colour
    float3 result = base.rgb + scatter_delta * float3(scatter_r * 1.05, 1.00, scatter_b * 0.92);

    float dither = frac(sin(dot(pos.xy, float2(127.1, 311.7))) * 43758.5453) - 0.5;
    result += dither * (1.0 / 255.0);

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
