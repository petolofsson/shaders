// scope.fx — Dual luma histogram overlay
//
// Two panels (each 80px tall, 4px divider):
//   Top   (white) — post-correction — current BackBuffer
//   Bottom (red)  — pre-correction  — read from BackBuffer row y=0
//                   (encoded by scope_pre.fx, preserved by corrective shaders)
//
// Data highway layout (row y=0):
//   Pixels 0..127  — pre-correction histogram bins (written by scope_pre)
//   Pixel  128     — pre-correction mean            (written by scope_pre)
//   Pixel  129     — post-correction mean, smoothed (written by this shader)
//
// Reference lines:
//   Yellow = scene mean for that panel (pre or post correction)
//   Grey   = 0.90 (p95 target — where highlights should land)

#define SCOPE_X    10
#define SCOPE_Y    10
#define SCOPE_W    512
#define SCOPE_PH   80
#define SCOPE_DIV  4
#define SCOPE_H    164
#define SCOPE_AMP  1.5
#define SCOPE_S    16
#define SCOPE_BINS 128
#define SCOPE_LERP 4.3

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

uniform float frametime < source = "frametime"; >;

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float4 ScopePS(float4 pos : SV_Position,
               float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);

    // Row y=0 — data highway
    if (pos.y < 1.0)
    {
        // Pixels 0..128: restore from y=1 (histogram + pre_mean, written by scope_pre)
        if (int(pos.x) <= SCOPE_BINS)
            return tex2D(BackBuffer, float2(uv.x, 1.0 / float(BUFFER_HEIGHT)));

        // Pixel 129: compute + store smoothed post-correction mean
        if (int(pos.x) == SCOPE_BINS + 1)
        {
            float live = 0.0;
            [loop]
            for (int my = 0; my < SCOPE_S; my++)
            [loop]
            for (int mx = 0; mx < SCOPE_S; mx++)
                live += Luma(tex2Dlod(BackBuffer,
                    float4((mx + 0.5) / float(SCOPE_S), (my + 0.5) / float(SCOPE_S), 0, 0)).rgb);
            live /= float(SCOPE_S * SCOPE_S);
            float dv   = 0.5 / float(BUFFER_HEIGHT);
            float prev = tex2Dlod(BackBuffer,
                float4((float(SCOPE_BINS + 1) + 0.5) / float(BUFFER_WIDTH), dv, 0, 0)).r;
            float s = lerp(prev, live, (SCOPE_LERP / 100.0) * (frametime / 10.0));
            return float4(s, s, s, 1.0);
        }

        return col; // pixels 130+: passthrough (reserved for future stage means)
    }

    // Debug indicator — cyan (slot 4)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 22) && pos.x < float(BUFFER_WIDTH - 10))
        return float4(0.0, 0.80, 1.0, 1.0);

    float x0 = SCOPE_X;
    float y0 = BUFFER_HEIGHT - SCOPE_Y - SCOPE_H;
    float x1 = x0 + SCOPE_W;
    float y1 = y0 + SCOPE_H;

    if (pos.x < x0 || pos.x >= x1 || pos.y < y0 || pos.y >= y1)
        return col;

    // 1px border
    if (pos.x < x0 + 1 || pos.x >= x1 - 1 || pos.y < y0 + 1 || pos.y >= y1 - 1)
        return float4(0.3, 0.3, 0.3, 1.0);

    int   bin   = int((pos.x - x0) / float(SCOPE_W) * float(SCOPE_BINS));
    float rel_y = pos.y - y0;

    bool in_top = rel_y < SCOPE_PH;
    bool in_div = rel_y >= SCOPE_PH && rel_y < (SCOPE_PH + SCOPE_DIV);

    if (in_div)
        return float4(0.18, 0.18, 0.18, 1.0);

    float data_v = 0.5 / float(BUFFER_HEIGHT);

    // Stage means from data highway (both temporally smoothed)
    float pre_mean_u  = (float(SCOPE_BINS)     + 0.5) / float(BUFFER_WIDTH);
    float post_mean_u = (float(SCOPE_BINS + 1) + 0.5) / float(BUFFER_WIDTH);
    float pre_mean    = tex2Dlod(BackBuffer, float4(pre_mean_u,  data_v, 0, 0)).r;
    float post_mean   = tex2Dlod(BackBuffer, float4(post_mean_u, data_v, 0, 0)).r;

    bool ref_90 = (bin == int(0.90 * float(SCOPE_BINS)));

    float3 bg = float3(0.06, 0.06, 0.06);

    if (in_top)
    {
        float pix       = 1.0 - rel_y / float(SCOPE_PH);
        float bucket_lo = float(bin)     / float(SCOPE_BINS);
        float bucket_hi = float(bin + 1) / float(SCOPE_BINS);
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

        bool ref_mean = (bin == int(post_mean * float(SCOPE_BINS)));

        float3 scope;
        if      (ref_mean)   scope = float3(1.0, 0.85, 0.0);
        else if (ref_90)     scope = float3(0.4, 0.4,  0.4);
        else if (pix <= bar) scope = float3(0.9, 0.9,  0.9);
        else                 scope = bg;
        return float4(lerp(col.rgb, scope, 0.92), col.a);
    }
    else
    {
        float pix     = 1.0 - (rel_y - float(SCOPE_PH + SCOPE_DIV)) / float(SCOPE_PH);
        float data_u  = (float(bin) + 0.5) / float(BUFFER_WIDTH);
        float raw_val = tex2Dlod(BackBuffer, float4(data_u, data_v, 0, 0)).r;
        float bar     = saturate(raw_val * float(SCOPE_BINS) * SCOPE_AMP);

        bool ref_mean = (bin == int(pre_mean * float(SCOPE_BINS)));

        float3 scope;
        if      (ref_mean)   scope = float3(1.0, 0.85, 0.0);
        else if (ref_90)     scope = float3(0.4, 0.4,  0.4);
        else if (pix <= bar) scope = float3(1.0, 0.05, 0.05);
        else                 scope = bg;
        return float4(lerp(col.rgb, scope, 0.92), col.a);
    }
}

technique Scope
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = ScopePS;
    }
}
