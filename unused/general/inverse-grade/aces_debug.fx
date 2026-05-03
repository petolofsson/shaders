// aces_debug.fx — R86 confidence diagnostic overlay
//
// Reads p25/p50/p75 from the BackBuffer data highway (x=194,195,196 at y=0),
// encoded by analysis_frame's DebugOverlay pass. BackBuffer is the proven
// shared mechanism — PercTex cross-effect sharing is broken in vkBasalt.
//
// Box colour (top-right corner):
//   Red    = aces_conf < 0.05  (not ACES or scene too dark)
//   Yellow = aces_conf 0.05–0.5
//   Green  = aces_conf > 0.5   (strong ACES fingerprint)
//
// Pixel encoding at y=1 for aces_calib.py:
//   pixel (0,1) = (p25, p50, p75, 1)
//   pixel (1,1) = (aces_conf, 0, 0, 1)
//
// Runs last in chain.

#include "creative_values.fx"

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float ACESConfidence(float4 perc)
{
    float iqr         = max(perc.b - perc.r, 0.001);
    float highs_norm  = max(1.0 - perc.b, 0.0) / iqr;
    float shadow_rat  = perc.r / max(perc.g, 0.001);
    return saturate(
        smoothstep(3.0, 1.2, highs_norm) * 0.70 +
        smoothstep(0.72, 0.52, shadow_rat) * 0.30);
}

#define BOX_W   40
#define BOX_H   40
#define BOX_PAD 20

// Highway positions where analysis_frame encodes PercTex (x=194,195,196 at y=0)
#define PERC_X_P25  194
#define PERC_X_P50  195
#define PERC_X_P75  196

float4 ACESDebugPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;

    // Read p25/p50/p75 from the data highway (encoded by analysis_frame)
    float p25 = tex2D(BackBuffer, float2((PERC_X_P25 + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT)).r;
    float p50 = tex2D(BackBuffer, float2((PERC_X_P50 + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT)).r;
    float p75 = tex2D(BackBuffer, float2((PERC_X_P75 + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT)).r;
    float4 perc      = float4(p25, p50, p75, 0.0);
    float  aces_conf = ACESConfidence(perc);

    // Pixel encoding at y=1 for aces_calib.py
    if (pos.y >= 1.0 && pos.y < 2.0 && pos.x < 2.0)
        return (pos.x < 1.0)
            ? float4(p25, p50, p75, 1.0)
            : float4(aces_conf, 0.0, 0.0, 1.0);

    // Debug box: top-right corner
    // Top half:    red→green confidence bar
    // Bottom half: left=p25(R), mid=p50(G), right=p75(B) raw values
    float x0 = float(BUFFER_WIDTH  - BOX_PAD - BOX_W);
    float y0 = float(BOX_PAD);
    if (pos.x >= x0 && pos.x < x0 + float(BOX_W) &&
        pos.y >= y0 && pos.y < y0 + float(BOX_H))
    {
        float rel_x = (pos.x - x0) / float(BOX_W);
        if (pos.y < y0 + float(BOX_H) * 0.5)
        {
            float t = saturate(aces_conf / 0.5);
            return float4(1.0 - t, t, 0.0, 1.0);
        }
        // Bottom: three equal columns showing p25 / p50 / p75 as brightness
        if (rel_x < 0.333) return float4(p25, 0.0, 0.0, 1.0);
        if (rel_x < 0.666) return float4(0.0, p50, 0.0, 1.0);
        return float4(0.0, 0.0, p75, 1.0);
    }

    return col;
}

technique OlofssonianACESDebug
{
    pass ACESDebugPass
    {
        VertexShader = PostProcessVS;
        PixelShader  = ACESDebugPS;
    }
}
