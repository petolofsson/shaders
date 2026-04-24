// scope.fx — Dual luma histogram overlay
//
// Shows two histograms simultaneously:
//   Orange — raw game signal (pre-correction, from LumHistTex)
//   White  — post-correction signal (current BackBuffer)
//
// If the corrective chain is expanding range, the white bars spread
// wider than the orange bars. No toggling needed.
//
// Reference lines: yellow = 0.18 (18% grey), dim grey = 0.90 (p95 target).

#define SCOPE_X  10
#define SCOPE_Y  10
#define SCOPE_W  128
#define SCOPE_H  64
#define HIST_BINS 64

// ─── Shared histogram — written by frame_analysis (raw pre-correction) ──────
texture2D LumHistTex { Width = HIST_BINS; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumHist
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

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

    int   bin       = int(pos.x - x0);
    float bucket_lo = float(bin)     / float(SCOPE_W);
    float bucket_hi = float(bin + 1) / float(SCOPE_W);
    float pix       = 1.0 - (pos.y - y0) / float(SCOPE_H);

    // ── Raw histogram (orange) — from LumHistTex (pre-correction) ─────────────
    // LumHistTex has HIST_BINS=64 bins; interpolate across SCOPE_W=128 columns
    float hist_u   = (bin + 0.5) / float(SCOPE_W);
    float raw_val  = tex2Dlod(LumHist, float4(hist_u, 0.5, 0, 0)).r;
    float bar_raw  = saturate(raw_val * float(HIST_BINS));

    // ── Post-correction histogram (white) — sampled from current BackBuffer ───
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
    float bar_post = saturate(count / 64.0 * float(SCOPE_W));

    // ── Reference lines ───────────────────────────────────────────────────────
    bool ref_18 = abs(bucket_lo - 0.18) < (0.5 / float(SCOPE_W));
    bool ref_90 = abs(bucket_lo - 0.90) < (0.5 / float(SCOPE_W));

    // ── Composite ─────────────────────────────────────────────────────────────
    float3 bg      = float3(0.04, 0.04, 0.04);
    float3 orange  = float3(0.90, 0.45, 0.10);
    float3 white_c = float3(0.85, 0.85, 0.85);

    float3 scope = bg;
    if      (ref_18)              scope = float3(1.0, 0.85, 0.0);
    else if (ref_90)              scope = float3(0.35, 0.35, 0.35);
    else if (pix <= bar_raw)      scope = orange;
    if      (!ref_18 && !ref_90 && pix <= bar_post) scope = white_c;

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
