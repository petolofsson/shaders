// scope.fx — Real-time luma histogram overlay
//
// Draws a small histogram in the bottom-left corner showing the luminance
// distribution of the current frame. Use to verify range expansion:
// with corrective chain active the bars should spread wider across 0→1.
// Without shaders they cluster in a compressed band.
//
// Samples 8×8 = 64 points across the frame. 64 bins × 64 samples.
// Normalized so a flat distribution fills full bar height.
// Reference lines: white = 0.18 (18% grey), grey = 0.90 (p95 target).

#define SCOPE_X   10     // left edge (pixels from left)
#define SCOPE_Y   10     // bottom edge (pixels from bottom)
#define SCOPE_W   128    // width in pixels = number of bins
#define SCOPE_H   64     // height in pixels

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

    int   bin        = int(pos.x - x0);
    float bucket_lo  = float(bin)     / float(SCOPE_W);
    float bucket_hi  = float(bin + 1) / float(SCOPE_W);

    // Count samples falling in this bin
    float count = 0.0;
    [loop]
    for (int sy = 0; sy < 8; sy++)
    [loop]
    for (int sx = 0; sx < 8; sx++)
    {
        float2 suv  = float2((sx + 0.5) / 8.0, (sy + 0.5) / 8.0);
        float  luma = Luma(tex2Dlod(BackBuffer, float4(suv, 0, 0)).rgb);
        count += (luma >= bucket_lo && luma < bucket_hi) ? 1.0 : 0.0;
    }

    // Normalize: flat distribution → full bar height
    float bar = saturate(count / 64.0 * float(SCOPE_W));
    float pix = 1.0 - (pos.y - y0) / float(SCOPE_H);  // 0 = bottom, 1 = top

    // Reference lines
    float ref_18  = abs(bucket_lo - 0.18) < (0.5 / float(SCOPE_W));  // 18% grey
    float ref_90  = abs(bucket_lo - 0.90) < (0.5 / float(SCOPE_W));  // p95 target

    float3 bg     = float3(0.04, 0.04, 0.04);
    float3 bar_c  = float3(0.85, 0.85, 0.85);
    float3 ref18  = float3(1.0,  0.85, 0.0);   // yellow — 18% grey
    float3 ref90  = float3(0.4,  0.4,  0.4);   // grey  — p95 target

    float3 scope;
    if      (ref_18 > 0.5) scope = ref18;
    else if (ref_90 > 0.5) scope = ref90;
    else                   scope = (pix <= bar) ? bar_c : bg;

    return float4(lerp(col.rgb, scope, 0.90), col.a);
}

technique Scope
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = ScopePS;
    }
}
