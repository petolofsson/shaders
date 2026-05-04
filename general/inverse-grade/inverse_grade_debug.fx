// inverse_grade_debug.fx — R90 slope diagnostic overlay
//
// Box colour (top-right corner, top half):
//   Blue  = slope < 1.1  (no compression detected, inversion near no-op)
//   Green = slope ≈ 1.5  (healthy ACES-range compression)
//   Red   = slope ≥ 2.5  (capped — flat/uniform histogram)
//
// Bottom half: three columns — p25(R), p50(G), p75(B) raw highway values.
// Dark columns = dark scene (correct). Used to verify highway is live.
//
// Place immediately after inverse_grade in chain.

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

#define PERC_X_P25    194
#define PERC_X_P50    195
#define PERC_X_P75    196
#define PERC_X_SLOPE  197

#define BOX_W   40
#define BOX_H   40
#define BOX_PAD 20

float4 InverseGradeDebugPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;

    float p25 = tex2D(BackBuffer, float2((PERC_X_P25 + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT)).r;
    float p50 = tex2D(BackBuffer, float2((PERC_X_P50 + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT)).r;
    float p75 = tex2D(BackBuffer, float2((PERC_X_P75 + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT)).r;

    float slope_enc = tex2D(BackBuffer, float2((PERC_X_SLOPE + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT)).r;
    float slope     = slope_enc * 1.5 + 1.0;

    float x0 = float(BUFFER_WIDTH  - BOX_PAD - BOX_W);
    float y0 = float(BOX_PAD);
    if (pos.x >= x0 && pos.x < x0 + float(BOX_W) &&
        pos.y >= y0 && pos.y < y0 + float(BOX_H))
    {
        float rel_x = (pos.x - x0) / float(BOX_W);
        if (pos.y < y0 + float(BOX_H) * 0.5)
        {
            // Blue(1.0) → Green(1.5) → Red(2.5)
            float t = saturate((slope - 1.0) / 1.5);   // 0 at slope=1, 1 at slope=2.5
            float r = smoothstep(0.4, 0.8, t);
            float g = smoothstep(0.0, 0.4, t) * (1.0 - smoothstep(0.7, 1.0, t));
            float b = 1.0 - smoothstep(0.0, 0.4, t);
            return float4(r, g, b, 1.0);
        }
        if (rel_x < 0.333) return float4(p25, 0.0, 0.0, 1.0);
        if (rel_x < 0.666) return float4(0.0, p50, 0.0, 1.0);
        return float4(0.0, 0.0, p75, 1.0);
    }

    return col;
}

technique OlofssonianInverseGradeDebug
{
    pass InverseGradeDebugPass
    {
        VertexShader = PostProcessVS;
        PixelShader  = InverseGradeDebugPS;
    }
}
