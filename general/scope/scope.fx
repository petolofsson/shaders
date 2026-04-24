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

#define SCOPE_X   10
#define SCOPE_Y   10
#define SCOPE_W   256     // wider = more readable bins
#define SCOPE_H   120     // split: top 56 = post-correction, bottom 56 = raw, 8 = divider
#define SCOPE_AMP 8.0     // amplify bar heights so sparse bins are visible
#define SCOPE_S   16      // samples per axis (16×16 = 256 total)
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
    float rel_y     = pos.y - y0;   // 0 = top of scope box

    int half_h  = (SCOPE_H - 8) / 2;  // height of each panel (56px)
    int div_y0  = half_h;              // divider starts
    int div_y1  = half_h + 8;         // divider ends

    bool in_top = rel_y < div_y0;                          // post-correction panel
    bool in_div = rel_y >= div_y0 && rel_y < div_y1;      // divider
    bool in_bot = rel_y >= div_y1;                         // raw panel

    float pix_top = 1.0 - rel_y / float(half_h);
    float pix_bot = 1.0 - (rel_y - div_y1) / float(half_h);

    // ── Raw histogram (red) — LumHistTex pre-correction ───────────────────────
    float hist_u  = (bin + 0.5) / float(SCOPE_W);
    float raw_val = tex2Dlod(LumHist, float4(hist_u, 0.5, 0, 0)).r;
    float bar_raw = saturate(raw_val * float(HIST_BINS) * SCOPE_AMP * 0.5);

    // ── Post-correction histogram (white) — current BackBuffer ────────────────
    float count = 0.0;
    [loop]
    for (int sy = 0; sy < SCOPE_S; sy++)
    [loop]
    for (int sx = 0; sx < SCOPE_S; sx++)
    {
        float2 suv  = float2((sx + 0.5) / float(SCOPE_S), (sy + 0.5) / float(SCOPE_S));
        float  luma = Luma(tex2Dlod(BackBuffer, float4(suv, 0, 0)).rgb);
        count += (luma >= bucket_lo && luma < bucket_hi) ? 1.0 : 0.0;
    }
    float total_s  = float(SCOPE_S * SCOPE_S);
    float bar_post = saturate(count / total_s * float(SCOPE_W) * SCOPE_AMP);

    // ── Reference lines ───────────────────────────────────────────────────────
    bool ref_18 = abs(bucket_lo - 0.18) < (0.5 / float(SCOPE_W));
    bool ref_90 = abs(bucket_lo - 0.90) < (0.5 / float(SCOPE_W));

    float3 bg     = float3(0.06, 0.06, 0.06);
    float3 div_c  = float3(0.20, 0.20, 0.20);
    float3 red_c  = float3(1.00, 0.10, 0.10);
    float3 wht_c  = float3(0.90, 0.90, 0.90);
    float3 yel_c  = float3(1.00, 0.85, 0.00);
    float3 grey_c = float3(0.30, 0.30, 0.30);

    float3 scope;
    if (in_div) {
        scope = div_c;
    } else if (in_top) {
        scope = (ref_18) ? yel_c : (ref_90) ? grey_c : (pix_top <= bar_post) ? wht_c : bg;
    } else {
        scope = (ref_18) ? yel_c : (ref_90) ? grey_c : (pix_bot <= bar_raw)  ? red_c : bg;
    }

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
