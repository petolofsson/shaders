// scope.fx — Three-panel scope overlay (512×168px, bottom-left)
#include "debug_text.fxh"
//
// Top 40px    (white bars)     — post-correction luma histogram, digit overlay = post_mean
// 4px divider
// Mid 40px    (grey bars)      — pre-correction luma histogram,  digit overlay = pre_mean
// 4px divider
// Bottom 80px (hue)            — top 40px post hue (live), bottom 40px pre hue (highway)
//
// Data highway layout (row y=0, written by scope_pre.fx):
//   Pixels   0..127  — pre-correction luma histogram bins
//   Pixel    128     — pre-correction mean luma
//   Pixel    129     — post-correction mean, smoothed (written by this shader)
//   Pixels 130..193  — pre-correction hue histogram bins
//
// Reference lines:
//   Yellow = scene mean for that panel
//   Grey   = 0.90 reference line

#define SCOPE_X    10
#define SCOPE_Y    10
#define SCOPE_W    256
#define SCOPE_PH   20
#define SCOPE_DIV  2
#define SCOPE_H    84
#define SCOPE_AMP  1.5
#define SCOPE_S    8
#define SCOPE_BINS 128
#define SCOPE_HSB   20
#define SCOPE_HS     4
#define SCOPE_HAMP 2.0
#define HUE_BINS    64
#define HUE_OFFSET 130

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Native (pre-inverse_grade) histogram — shared with frame_analysis
texture2D LumHistTex { Width = 64; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumHistSamp
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
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

float3 RGBtoHSV(float3 c)
{
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float  d = q.x - min(q.w, q.y);
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

float3 HueToRGB(float h)
{
    float3 p = abs(frac(h + float3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
    return saturate(p - 1.0);
}

int GetDigitRow(int d, int row)
{
    int enc = 0;
    if (d== 0) enc = 31599;
    if (d== 1) enc =  9367;
    if (d== 2) enc = 29671;
    if (d== 3) enc = 29647;
    if (d== 4) enc = 23497;
    if (d== 5) enc = 31183;
    if (d== 6) enc = 31215;
    if (d== 7) enc = 29257;
    if (d== 8) enc = 31727;
    if (d== 9) enc = 31695;
    if (d==10) enc =     2;
    return (enc >> (3 * (4 - row))) & 7;
}

bool SampleDigit(int d, int px, int py)
{
    return (GetDigitRow(clamp(d, 0, 10), py) >> (2 - px)) & 1;
}

bool ShowNumber(float val, int px, int py)
{
    val = clamp(val, 0.0, 0.999);
    int w = int(val);
    int f = int(frac(val) * 100.0);
    if (px >= 0  && px <= 2)  return SampleDigit(w,      px,      py);
    if (px >= 4  && px <= 6)  return SampleDigit(10,     px - 4,  py);
    if (px >= 8  && px <= 10) return SampleDigit(f / 10, px - 8,  py);
    if (px >= 12 && px <= 14) return SampleDigit(f % 10, px - 12, py);
    return false;
}

float4 ScopePS(float4 pos : SV_Position,
               float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);

    // Row y=0 — data highway
    if (pos.y < 1.0)
    {
        // Pixels 0..128: put game content back (highway data not needed after this pass)
        if (int(pos.x) <= SCOPE_BINS)
            return tex2D(BackBuffer, float2(uv.x, 1.5 / float(BUFFER_HEIGHT)));

        // Pixel 129: live post-correction mean (no cross-frame smoothing — vkBasalt has no BB persistence)
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
            return float4(live, live, live, 1.0);
        }

        return col; // pixels 130+: passthrough (reserved for future stage means)
    }

    col = DrawLabel(col, pos.xy, 270.0, 82.0,
                    83u, 67u, 79u, 80u, float3(0.0, 0.80, 1.0)); // SCOP

    float x0 = SCOPE_X;
    float y0 = SCOPE_Y;
    float x1 = x0 + SCOPE_W;
    float y1 = y0 + SCOPE_H;

    if (pos.x < x0 || pos.x >= x1 || pos.y < y0 || pos.y >= y1)
        return col;

    // 1px border
    if (pos.x < x0 + 1 || pos.x >= x1 - 1 || pos.y < y0 + 1 || pos.y >= y1 - 1)
        return float4(0.3, 0.3, 0.3, 1.0);

    int   bin   = int((pos.x - x0) / float(SCOPE_W) * float(SCOPE_BINS));
    float rel_y = pos.y - y0;

    bool in_top  = rel_y < SCOPE_PH;
    bool in_div  = rel_y >= SCOPE_PH && rel_y < SCOPE_PH + SCOPE_DIV;
    bool in_div2 = rel_y >= SCOPE_PH * 2 + SCOPE_DIV && rel_y < SCOPE_PH * 2 + SCOPE_DIV * 2;
    bool in_hue  = rel_y >= SCOPE_PH * 2 + SCOPE_DIV * 2;

    if (in_div || in_div2)
        return float4(0.18, 0.18, 0.18, 1.0);

    float data_v = 0.5 / float(BUFFER_HEIGHT);

    // Stage means from data highway
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
        [loop] for (int sy = 0; sy < SCOPE_S; sy++)
        [loop] for (int sx = 0; sx < SCOPE_S; sx++)
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
        int dig_x = int(pos.x - x0) - (SCOPE_W - 18);
        int dig_y = int(rel_y) - 2;
        if (dig_x >= 0 && dig_x < 15 && dig_y >= 0 && dig_y < 5)
            if (ShowNumber(post_mean, dig_x, dig_y))
                scope = float3(1.0, 0.85, 0.0);
        return float4(lerp(col.rgb, scope, 0.92), col.a);
    }

    if (!in_hue)
    {
        float pix     = 1.0 - (rel_y - float(SCOPE_PH + SCOPE_DIV)) / float(SCOPE_PH);
        float data_u  = (float(bin) + 0.5) / float(BUFFER_WIDTH);
        float raw_val = tex2Dlod(BackBuffer, float4(data_u, data_v, 0, 0)).r;
        float bar     = saturate(raw_val * float(SCOPE_BINS) * SCOPE_AMP);
        bool ref_mean = (bin == int(pre_mean * float(SCOPE_BINS)));
        float3 scope;
        if      (ref_mean)   scope = float3(1.0, 0.85, 0.0);
        else if (ref_90)     scope = float3(0.4, 0.4,  0.4);
        else if (pix <= bar) scope = float3(0.45, 0.45, 0.45);
        else                 scope = bg;
        int dig_x = int(pos.x - x0) - (SCOPE_W - 18);
        int dig_y = int(rel_y) - (SCOPE_PH + SCOPE_DIV + 2);
        if (dig_x >= 0 && dig_x < 15 && dig_y >= 0 && dig_y < 5)
            if (ShowNumber(pre_mean, dig_x, dig_y))
                scope = float3(1.0, 0.85, 0.0);
        return float4(lerp(col.rgb, scope, 0.92), col.a);
    }

    // Hue panel — top 40px post-correction, bottom 40px pre-correction
    {
        int   hue_bin    = clamp(int((pos.x - x0) / float(SCOPE_W) * float(HUE_BINS)), 0, HUE_BINS - 1);
        float hue_center = (float(hue_bin) + 0.5) / float(HUE_BINS);
        float3 hue_col   = HueToRGB(hue_center);
        float  hue_off   = float(SCOPE_PH * 2 + SCOPE_DIV * 2);
        bool   in_post   = rel_y < hue_off + float(SCOPE_HSB);

        if (in_post)
        {
            float pix = 1.0 - (rel_y - hue_off) / float(SCOPE_HSB);
            float bucket_lo = float(hue_bin)     / float(HUE_BINS);
            float bucket_hi = float(hue_bin + 1) / float(HUE_BINS);
            float count = 0.0, total_w = 0.0;
            [loop] for (int sy = 0; sy < SCOPE_HS; sy++)
            [loop] for (int sx = 0; sx < SCOPE_HS; sx++)
            {
                float3 s   = tex2Dlod(BackBuffer,
                    float4((sx + 0.5) / float(SCOPE_HS), (sy + 0.5) / float(SCOPE_HS), 0, 0)).rgb;
                float3 hsv = RGBtoHSV(s);
                float  w   = step(0.04, hsv.y);
                count   += (hsv.x >= bucket_lo && hsv.x < bucket_hi) ? w : 0.0;
                total_w += w;
            }
            float bar = (total_w > 0.5) ? saturate(count / total_w * float(HUE_BINS) * SCOPE_HAMP) : 0.0;
            float3 scope = (pix <= bar) ? hue_col : bg;
            return float4(lerp(col.rgb, scope, 0.92), col.a);
        }
        else
        {
            float pix     = 1.0 - (rel_y - hue_off - float(SCOPE_HSB)) / float(SCOPE_HSB);
            float hue_u   = (float(HUE_OFFSET + hue_bin) + 0.5) / float(BUFFER_WIDTH);
            float hue_val = tex2Dlod(BackBuffer, float4(hue_u, data_v, 0, 0)).r;
            float bar     = saturate(hue_val * float(HUE_BINS) * SCOPE_HAMP);
            float3 scope  = (pix <= bar) ? hue_col * 0.55 : bg;
            return float4(lerp(col.rgb, scope, 0.92), col.a);
        }
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
