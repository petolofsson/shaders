// pro_mist.fx — Black Pro-Mist diffusion filter
//
// Two-pass global diffusion. Pass 1 downsamples the full BackBuffer to
// 1/4-res float16 with mips (no threshold — all tones). Pass 2 blends a
// mip-blurred copy back: lerp(sharp, blurred, strength). Softens edges and
// reduces micro-contrast uniformly across shadows, mids, and highlights.
// Highlight glow is handled by halation.fx + veil.fx.
//
// Shared texture contract:
//   PercTex { Width=1; Height=1; Format=RGBA16F } — written by analysis_frame
//   r=p25, g=p50, b=p75, a=iqr
//   ChromaHistoryTex { Width=8; Height=4; Format=RGBA16F } — written by corrective.fx

#include "debug_text.fxh"
#include "../highway.fxh"
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

// ─── Private textures ──────────────────────────────────────────────────────

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Full-image downsample at 1/4-res — float16, mips for blur depth
texture2D MistDiffuseTex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; MipLevels = 4; };
sampler2D MistDiffuseSamp
{
    Texture   = MistDiffuseTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = LINEAR;
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

// ─── Pass 1 — Full-image downsample ───────────────────────────────────────

float4 DownsamplePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    if (pos.y < 1.0) return float4(0.0, 0.0, 0.0, 0.0);
    return float4(tex2D(BackBuffer, uv).rgb, 1.0);
}

// ─── Pass 2 — Global diffusion composite ──────────────────────────────────

float4 ProMistPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 base = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return base;

    // Mip 2 of 1/4-res = 1/16-res effective = heavily blurred full image
    float3 blurred = tex2Dlod(MistDiffuseSamp, float4(uv, 0, 2)).rgb;

    float4 perc      = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));
    float  iqr       = perc.b - perc.r;
    // High-contrast scenes get slightly more diffusion
    float  adapt_str = MIST_STRENGTH * 0.06 * lerp(0.8, 1.2, saturate(iqr / 0.5));
    // R80B: scene-key adaptive — dark scenes get more diffusion, bright exteriors less
    float zone_log_key   = tex2Dlod(ChromaHistSamp, float4(6.5 / 8.0, 0.5 / 4.0, 0, 0)).r;
    float mist_key_scale = lerp(1.20, 0.85, smoothstep(0.05, 0.25, zone_log_key));
    // R80C: aperture proxy — low EXPOSURE (wide aperture equivalent) → more diffusion
    float mist_ap_scale  = lerp(1.10, 0.90, saturate((EXPOSURE - 0.70) / 0.60));
    adapt_str *= mist_key_scale * mist_ap_scale;

    float3 result = lerp(base.rgb, blurred, saturate(adapt_str));

    // IGN blue-noise dither (Jimenez 2016) — matches grade.fx
    float dither = frac(52.9829189 * frac(dot(pos.xy, float2(0.06711056, 0.00583715)))) - 0.5;
    result += dither * (1.0 / 255.0);

    float4 out_col = float4(saturate(result), base.a);
    out_col = DrawLabel(out_col, pos.xy, 270.0, 58.0,
                        55u, 80u, 77u, 83u, float3(0.9, 0.1, 0.9)); // 7PMS
    return out_col;
}

// ─── Technique ────────────────────────────────────────────────────────────

technique ProMist
{
    pass Downsample
    {
        VertexShader = PostProcessVS;
        PixelShader  = DownsamplePS;
        RenderTarget = MistDiffuseTex;
    }
    pass Composite
    {
        VertexShader = PostProcessVS;
        PixelShader  = ProMistPS;
    }
}
