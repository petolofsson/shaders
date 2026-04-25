// scope_pre.fx — Pre-correction luma histogram + mean capture
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

#define SCOPE_BINS 128
#define SCOPE_S    16

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

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float4 ScopeCapturePS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.y < 1.0 && pos.x <= float(SCOPE_BINS))
    {
        // Sample grid once — used for both histogram and mean
        float samples[256];
        float mean = 0.0;
        [loop]
        for (int sy = 0; sy < SCOPE_S; sy++)
        [loop]
        for (int sx = 0; sx < SCOPE_S; sx++)
        {
            float luma = Luma(tex2Dlod(BackBuffer,
                float4((sx + 0.5) / float(SCOPE_S), (sy + 0.5) / float(SCOPE_S), 0, 0)).rgb);
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

    // Debug indicator — orange (slot 1)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 64) && pos.x < float(BUFFER_WIDTH - 52))
        return float4(1.0, 0.50, 0.0, 1.0);
    return tex2D(BackBuffer, uv);
}

technique ScopeCapture
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = ScopeCapturePS;
    }
}
