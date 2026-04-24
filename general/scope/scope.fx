// scope.fx — Real-time luma histogram overlay
//
// Single panel showing the luminance distribution of the current frame.
// Use to verify range: bars should span from shadow floor to near 0.90.
//
// Reference lines:
//   Yellow = 0.18 (18% grey — photographic middle grey)
//   Grey   = 0.90 (p95 target — where highlights should land)
//
// 16×16 = 256 samples, 64 bins.

#define SCOPE_X   10
#define SCOPE_Y   10
#define SCOPE_W   256
#define SCOPE_H   80
#define SCOPE_AMP 1.5
#define SCOPE_S   16
#define SCOPE_BINS 64

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

float4 ScopePS(float4 pos : SV_Position,
               float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);

    float x0 = SCOPE_X;
    float y0 = BUFFER_HEIGHT - SCOPE_Y - SCOPE_H;
    float x1 = x0 + SCOPE_W;
    float y1 = y0 + SCOPE_H;

    if (pos.x < x0 || pos.x >= x1 || pos.y < y0 || pos.y >= y1)
        return col;

    // 1px border
    if (pos.x < x0 + 1 || pos.x >= x1 - 1 || pos.y < y0 + 1 || pos.y >= y1 - 1)
        return float4(0.3, 0.3, 0.3, 1.0);

    int   bin       = int((pos.x - x0) / float(SCOPE_W) * float(SCOPE_BINS));
    float bucket_lo = float(bin)     / float(SCOPE_BINS);
    float bucket_hi = float(bin + 1) / float(SCOPE_BINS);
    float pix       = 1.0 - (pos.y - y0) / float(SCOPE_H);

    // Count samples in this bin
    float count = 0.0;
    [loop]
    for (int sy = 0; sy < SCOPE_S; sy++)
    [loop]
    for (int sx = 0; sx < SCOPE_S; sx++)
    {
        float luma = Luma(tex2Dlod(BackBuffer,
            float4((sx + 0.5) / float(SCOPE_S), (sy + 0.5) / float(SCOPE_S), 0, 0)).rgb);
        count += (luma >= bucket_lo && luma < bucket_hi) ? 1.0 : 0.0;
    }
    float bar = saturate(count / float(SCOPE_S * SCOPE_S) * float(SCOPE_BINS) * SCOPE_AMP);

    // Reference lines
    bool ref_18 = (bin == int(0.18 * float(SCOPE_BINS)));
    bool ref_90 = (bin == int(0.90 * float(SCOPE_BINS)));

    float3 bg    = float3(0.06, 0.06, 0.06);
    float3 bar_c = float3(0.9, 0.15, 0.15);

    float3 scope;
    if      (ref_18)       scope = float3(1.0,  0.85, 0.0);
    else if (ref_90)       scope = float3(0.4,  0.4,  0.4);
    else if (pix <= bar)   scope = bar_c;
    else                   scope = bg;

    return float4(lerp(col.rgb, scope, 0.92), col.a);
}

technique Scope
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = ScopePS;
    }
}
