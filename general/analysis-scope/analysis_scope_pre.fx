// scope_pre.fx — Pre-correction luma histogram + mean capture
#include "debug_text.fxh"
#include "../common.fxh"
//
// Must run BEFORE any corrective shaders in the chain.
// Writes into BackBuffer row y=0 (the data highway):
//   Pixels 0..127 — 128-bin luma histogram (R = fraction for that bin)
//   Pixel  128    — scene mean luma (R = mean)
//
// DATA HIGHWAY CONTRACT
//   This shader is the WRITER. Every corrective shader between scope_pre and
//   scope must preserve row y=0 unchanged (guard: if (pos.y < 1.0) return col).
//   scope.fx is the READER: it reads pixels 0–128 for the red panel and yellow
//   needle, restores those pixels from row y=1, and writes pixel 129 (smoothed
//   post-correction mean). Breaking the guard in any corrective shader corrupts
//   the scope's pre-correction panel.

#define SCOPE_BINS  128
#define SCOPE_S      8
#define HUE_BINS     64
#define HUE_OFFSET  130

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

float4 ScopeCapturePS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.y < 1.0 && int(pos.x) <= SCOPE_BINS)
    {
        // Sample grid once — used for both histogram and mean
        float samples[64];
        float mean = 0.0;
        [loop]
        for (int sy = 0; sy < SCOPE_S; sy++)
        [loop]
        for (int sx = 0; sx < SCOPE_S; sx++)
        {
            float luma = Luma(tex2D(BackBuffer,
                float2((sx + 0.5) / float(SCOPE_S), (sy + 0.5) / float(SCOPE_S))).rgb);
            samples[sy * SCOPE_S + sx] = luma;
            mean += luma;
        }
        mean /= float(SCOPE_S * SCOPE_S);

        // Pixel 128 — scene mean luma
        if (int(pos.x) == SCOPE_BINS)
        {
            return float4(mean, mean, mean, 1.0);
        }

        // Pixels 0..127 — histogram bins
        int   b         = int(pos.x);
        float bucket_lo = float(b)     / float(SCOPE_BINS);
        float bucket_hi = float(b + 1) / float(SCOPE_BINS);
        float count = 0.0;
        [loop]
        for (int i = 0; i < SCOPE_S * SCOPE_S; i++)
            count += (samples[i] >= bucket_lo && samples[i] < bucket_hi) ? 1.0 : 0.0;

        float v = count / float(SCOPE_S * SCOPE_S);
        return float4(v, v, v, 1.0);
    }

    // Pixels HUE_OFFSET..HUE_OFFSET+HUE_BINS-1: pre-correction hue histogram
    if (pos.y < 1.0 && int(pos.x) >= HUE_OFFSET && int(pos.x) < HUE_OFFSET + HUE_BINS)
    {
        int   b         = int(pos.x) - HUE_OFFSET;
        float bucket_lo = float(b)     / float(HUE_BINS);
        float bucket_hi = float(b + 1) / float(HUE_BINS);
        float count = 0.0, total_w = 0.0;
        [loop] for (int sy = 0; sy < SCOPE_S; sy++)
        [loop] for (int sx = 0; sx < SCOPE_S; sx++)
        {
            float3 col = tex2D(BackBuffer,
                float2((sx + 0.5) / float(SCOPE_S), (sy + 0.5) / float(SCOPE_S))).rgb;
            float3 hsv = RGBtoHSV(col);
            float  w   = step(0.04, hsv.y);
            count   += (hsv.x >= bucket_lo && hsv.x < bucket_hi) ? w : 0.0;
            total_w += w;
        }
        float v = (total_w > 0.5) ? count / total_w : 0.0;
        return float4(v, v, v, 1.0);
    }

    float4 c = tex2D(BackBuffer, uv);
    return DrawLabel(c, pos.xy, 270.0, 18.0,
                     50u, 83u, 67u, 80u, float3(1.0, 0.50, 0.0)); // 2SCP
}

technique ScopeCapture
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = ScopeCapturePS;
    }
}
