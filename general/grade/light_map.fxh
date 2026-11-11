// light_map.fxh — per-pixel light estimate (v3 material veto) for 3-way CC placement.
// Adopted from the light/shade candidate: research/2026-11-09_cc_light_map_placement.md,
// research/2026-11-09_light_lift_candidate.md. Light = log luminance (every step is light) plus a
// local correction that removes only confident paint steps (chroma change > .35 not explained by any
// shade direction). Short reach: 4-level pyramid. Synthetic oracle .150 vs brightness .211.
//
// Input: the shared 1/8 spatial lane (analysis_frame; full 8x8 area mean of the native frame).
// 1. LLDirections: one sparse reduction of the 1/8 lane -> shade colour directions in log
//    chromaticity (frame shade, two dark-pixel halves split across the sky axis); sky is constant.
// 2. LLDivergence: at 1/8, divergence of the paint (non-light) luminance steps, negated.
// 3. Convolution pyramid (Farbman, Fattal & Lischinski 2011; h1 = [.15 .5 .7 .5 .15], g = [.175 .547
//    .175], zero borders): 4 down, 4 up passes -> local Poisson integral at 1/8.
// 4. LLAnchor: offset so the estimate shares the frame's mean log luminance; frame lit level.
// 5. LLLightLog (in ColorTransform): native log luminance + bilinear 1/8 paint correction. Detail
//    below the 1/8 grid follows the pixel, so the estimate is stable in camera motion; the material
//    veto acts at map scale. (A joint bilateral upsample was phase-unstable on sub-8-px shade.)

#define LL_W0 (BUFFER_WIDTH / 8)
#define LL_H0 (BUFFER_HEIGHT / 8)
#define LL_W1 ((LL_W0 + 1) / 2)
#define LL_H1 ((LL_H0 + 1) / 2)
#define LL_W2 ((LL_W1 + 1) / 2)
#define LL_H2 ((LL_H1 + 1) / 2)
#define LL_W3 ((LL_W2 + 1) / 2)
#define LL_H3 ((LL_H2 + 1) / 2)
#define LL_W4 ((LL_W3 + 1) / 2)
#define LL_H4 ((LL_H3 + 1) / 2)
#define LL_W5 ((LL_W4 + 1) / 2)
#define LL_H5 ((LL_H4 + 1) / 2)
#define LL_W6 ((LL_W5 + 1) / 2)
#define LL_H6 ((LL_H5 + 1) / 2)
#define LL_W7 ((LL_W6 + 1) / 2)
#define LL_H7 ((LL_H6 + 1) / 2)
#define LL_SKY   float2(-0.54608341, 0.83773081)   // warm -> blue, Planckian log-chroma direction
#define LL_SCALE (-1.0)                            // 4-level pyramid output -> correction stops

texture2D LLDirATex { Width = 1; Height = 1; Format = RGBA32F; MipLevels = 1; };
sampler2D LLDirASamp { Texture = LLDirATex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
texture2D LLDirBTex { Width = 1; Height = 1; Format = RGBA32F; MipLevels = 1; };
sampler2D LLDirBSamp { Texture = LLDirBTex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
texture2D LLAnchorTex { Width = 1; Height = 1; Format = RGBA32F; MipLevels = 1; };
// 16×16 lane samples shared by LLDirections and LLAnchor (centre, right and down 1/8 neighbours),
// gathered in one parallel pass so the single-texel reductions read a tiny texture.
texture2D LLPtCTex { Width = 16; Height = 16; Format = RGBA32F; MipLevels = 1; };
sampler2D LLPtCSamp { Texture = LLPtCTex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
texture2D LLPtRTex { Width = 16; Height = 16; Format = RGBA32F; MipLevels = 1; };
sampler2D LLPtRSamp { Texture = LLPtRTex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
texture2D LLPtDTex { Width = 16; Height = 16; Format = RGBA32F; MipLevels = 1; };
sampler2D LLPtDSamp { Texture = LLPtDTex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
sampler2D LLAnchorSamp { Texture = LLAnchorTex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };

texture2D LLA0Tex { Width = LL_W0; Height = LL_H0; Format = R32F; MipLevels = 1; };
sampler2D LLA0Samp { Texture = LLA0Tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
texture2D LLA1Tex { Width = LL_W1; Height = LL_H1; Format = R32F; MipLevels = 1; };
sampler2D LLA1Samp { Texture = LLA1Tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
texture2D LLA2Tex { Width = LL_W2; Height = LL_H2; Format = R32F; MipLevels = 1; };
sampler2D LLA2Samp { Texture = LLA2Tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
texture2D LLA3Tex { Width = LL_W3; Height = LL_H3; Format = R32F; MipLevels = 1; };
sampler2D LLA3Samp { Texture = LLA3Tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
texture2D LLA4Tex { Width = LL_W4; Height = LL_H4; Format = R32F; MipLevels = 1; };
sampler2D LLA4Samp { Texture = LLA4Tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };

texture2D LLB0Tex { Width = LL_W0; Height = LL_H0; Format = R32F; MipLevels = 1; };
sampler2D LLB0Samp { Texture = LLB0Tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
sampler2D LLB0LinSamp { Texture = LLB0Tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = LINEAR; MagFilter = LINEAR; };
texture2D LLB1Tex { Width = LL_W1; Height = LL_H1; Format = R32F; MipLevels = 1; };
sampler2D LLB1Samp { Texture = LLB1Tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
texture2D LLB2Tex { Width = LL_W2; Height = LL_H2; Format = R32F; MipLevels = 1; };
sampler2D LLB2Samp { Texture = LLB2Tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };
texture2D LLB3Tex { Width = LL_W3; Height = LL_H3; Format = R32F; MipLevels = 1; };
sampler2D LLB3Samp { Texture = LLB3Tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; };

float LLLog(float3 rgb)
{
    return log2(max(Luma(rgb), 0.002));
}

// Natural-log chromaticity (ln R/G, ln B/G), as in the CPU reference.
float2 LLChroma(float3 rgb)
{
    float3 l = log(max(rgb, 0.002));
    return float2(l.r - l.g, l.b - l.g);
}

float2 LLUnit(float2 d)
{
    float n = length(d);
    return lerp(LL_SKY, d / max(n, 1e-6), step(1e-3, n));
}

// Paint step: chroma change large and not along any shade direction (smooth ramp .30–.40).
float LLPerp(float2 cd, float2 e)
{
    return abs(dot(cd, float2(-e.y, e.x)));
}

float LLPaint(float2 cd, float4 da, float2 db)
{
    float perp = min(min(LLPerp(cd, LL_SKY), LLPerp(cd, da.xy)), min(LLPerp(cd, da.zw), LLPerp(cd, db)));
    return smoothstep(0.30, 0.40, length(cd)) * smoothstep(0.30, 0.40, perp);
}

float LLH1(int k)
{
    int a = abs(k);
    return a == 0 ? 0.7 : (a == 1 ? 0.5 : 0.15);
}

float LLG(int k)
{
    return abs(k) == 0 ? 0.547 : 0.175;
}

float LLTap(sampler2D s, int2 q, int2 size)
{
    float inside = float(q.x >= 0) * float(q.y >= 0) * float(q.x < size.x) * float(q.y < size.y);
    float2 quv = (float2(clamp(q, int2(0, 0), size - 1)) + 0.5) / float2(size);
    return tex2Dlod(s, float4(quv, 0, 0)).r * inside;
}

// ─── 0. Shared 16×16 lane samples ───────────────────────────────────────────
void LLPointsPS(float4 pos : SV_Position, float2 uv : TEXCOORD0,
                out float4 c : SV_Target0, out float4 r : SV_Target1, out float4 d : SV_Target2)
{
    float2 suv = (floor(pos.xy) + 0.5) / 16.0;
    float2 px = 1.0 / float2(LL_W0, LL_H0);
    c = float4(ReadSpatialLane(suv).rgb, 0.0);
    r = float4(ReadSpatialLane(suv + float2(px.x, 0.0)).rgb, 0.0);
    d = float4(ReadSpatialLane(suv + float2(0.0, px.y)).rgb, 0.0);
}

float3 LLPoint(sampler2D s, float2 suv)
{
    return tex2Dlod(s, float4(suv, 0, 0)).rgb;
}

// ─── 1. Shade directions ────────────────────────────────────────────────────
void LLDirectionsPS(float4 pos : SV_Position, float2 uv : TEXCOORD0,
                    out float4 dir_a : SV_Target0, out float4 dir_b : SV_Target1)
{
    float s1 = 0.0, s2 = 0.0, n = 0.0;
    [loop] for (int j = 0; j < 16; j++)
    [loop] for (int i = 0; i < 16; i++)
    {
        float3 rgb = LLPoint(LLPtCSamp, (float2(i, j) + 0.5) / 16.0);
        float v = float(Luma(rgb) > 0.004);
        float ly = LLLog(rgb);
        s1 += v * ly; s2 += v * ly * ly; n += v;
    }
    float mean_ly = s1 / max(n, 1.0);
    float lo = mean_ly;
    float hi = mean_ly + 1.2816 * sqrt(max(s2 / max(n, 1.0) - mean_ly * mean_ly, 0.0));
    float2 across = float2(-LL_SKY.y, LL_SKY.x);
    float3 lit = 0.0, dark = 0.0;
    float w_lit_sum = 0.0, w_dark_sum = 0.0, side_sum = 0.0;
    [loop] for (int j2 = 0; j2 < 16; j2++)
    [loop] for (int i2 = 0; i2 < 16; i2++)
    {
        float3 rgb = LLPoint(LLPtCSamp, (float2(i2, j2) + 0.5) / 16.0);
        float ly = LLLog(rgb);
        float w_dark = (1.0 - smoothstep(lo - 0.25, lo + 0.25, ly)) * float(Luma(rgb) > 0.004);
        float w_lit = smoothstep(hi - 0.25, hi + 0.25, ly);
        lit += w_lit * rgb; w_lit_sum += w_lit;
        dark += w_dark * rgb; w_dark_sum += w_dark;
        side_sum += w_dark * dot(LLChroma(rgb), across);
    }
    float side_mid = side_sum / max(w_dark_sum, 1e-6);
    float3 dark_a = 0.0, dark_b = 0.0;
    float wa = 0.0, wb = 0.0;
    [loop] for (int j3 = 0; j3 < 16; j3++)
    [loop] for (int i3 = 0; i3 < 16; i3++)
    {
        float3 rgb = LLPoint(LLPtCSamp, (float2(i3, j3) + 0.5) / 16.0);
        float w_dark = (1.0 - smoothstep(lo - 0.25, lo + 0.25, LLLog(rgb))) * float(Luma(rgb) > 0.004);
        float upper = step(side_mid, dot(LLChroma(rgb), across));
        dark_a += w_dark * upper * rgb; wa += w_dark * upper;
        dark_b += w_dark * (1.0 - upper) * rgb; wb += w_dark * (1.0 - upper);
    }
    float2 c_lit = LLChroma(lit / max(w_lit_sum, 1e-6));
    float2 d_shade = LLUnit(LLChroma(dark / max(w_dark_sum, 1e-6)) - c_lit);
    float2 d_a = LLUnit(LLChroma(dark_a / max(wa, 1e-6)) - c_lit);
    float2 d_b = LLUnit(LLChroma(dark_b / max(wb, 1e-6)) - c_lit);
    dir_a = float4(d_shade, d_a);
    dir_b = float4(d_b, mean_ly, 1.0);
}

// ─── 2. Divergence of light-classified gradients at 1/8 ─────────────────────
float LLDivergencePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 da = tex2Dlod(LLDirASamp, float4(0.5, 0.5, 0, 0));
    float2 db = tex2Dlod(LLDirBSamp, float4(0.5, 0.5, 0, 0)).xy;
    float2 px = 1.0 / float2(LL_W0, LL_H0);
    float3 c = ReadSpatialLane(uv).rgb;
    float lc = LLLog(c);
    float2 cc = LLChroma(c);
    float div = 0.0;
    [unroll] for (int k = 0; k < 4; k++)
    {
        float2 off = k == 0 ? float2(1, 0) : (k == 1 ? float2(-1, 0) : (k == 2 ? float2(0, 1) : float2(0, -1)));
        float3 nb = ReadSpatialLane(uv + off * px).rgb;      // clamped at borders: step 0
        float dl = LLLog(nb) - lc;
        float2 cd = LLChroma(nb) - cc;
        div -= LLPaint(cd, da, db) * dl;     // divergence of the removed (paint) steps, negated
    }
    return div;
}

// ─── 3. Convolution pyramid ─────────────────────────────────────────────────
float LLDown(sampler2D s, int2 size, float2 pos)
{
    int2 o = int2(pos) * 2;
    float acc = 0.0;
    [unroll] for (int n = -2; n <= 2; n++)
    [unroll] for (int m = -2; m <= 2; m++)
        acc += LLH1(m) * LLH1(n) * LLTap(s, o + int2(m, n), size);
    return acc;
}

float LLG3(sampler2D s, int2 q, int2 size)
{
    float acc = 0.0;
    [unroll] for (int n = -1; n <= 1; n++)
    [unroll] for (int m = -1; m <= 1; m++)
        acc += LLG(m) * LLG(n) * LLTap(s, q + int2(m, n), size);
    return acc;
}

// b[l] = h1 * upsample_zero(b[l+1]) + g * a[l]
float LLUp(sampler2D coarse, int2 csize, sampler2D fine_a, int2 fsize, float2 pos)
{
    int2 p = int2(pos);
    float acc = 0.0;
    [unroll] for (int n = -2; n <= 2; n++)
    [unroll] for (int m = -2; m <= 2; m++)
    {
        int2 q = p + int2(m, n);
        float even = float(q.x % 2 == 0) * float(q.y % 2 == 0) * float(q.x >= 0) * float(q.y >= 0)
                   * float(q.x < fsize.x) * float(q.y < fsize.y);
        acc += LLH1(m) * LLH1(n) * even * LLTap(coarse, max(q, int2(0, 0)) / 2, csize);
    }
    return acc + LLG3(fine_a, p, fsize);
}

// Top level: the coarse input is g * a[4], evaluated on the fly (4 levels).
float LLUpTop(float2 pos)
{
    int2 p = int2(pos);
    int2 fsize = int2(LL_W3, LL_H3);
    int2 csize = int2(LL_W4, LL_H4);
    float acc = 0.0;
    [unroll] for (int n = -2; n <= 2; n++)
    [unroll] for (int m = -2; m <= 2; m++)
    {
        int2 q = p + int2(m, n);
        int2 c = max(q, int2(0, 0)) / 2;
        float even = float(q.x % 2 == 0) * float(q.y % 2 == 0) * float(q.x >= 0) * float(q.y >= 0)
                   * float(q.x < fsize.x) * float(q.y < fsize.y)
                   * float(c.x < csize.x) * float(c.y < csize.y);
        acc += LLH1(m) * LLH1(n) * even * LLG3(LLA4Samp, c, csize);
    }
    return acc + LLG3(LLA3Samp, p, fsize);
}

float LLDown1PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return LLDown(LLA0Samp, int2(LL_W0, LL_H0), pos.xy); }
float LLDown2PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return LLDown(LLA1Samp, int2(LL_W1, LL_H1), pos.xy); }
float LLDown3PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return LLDown(LLA2Samp, int2(LL_W2, LL_H2), pos.xy); }
float LLDown4PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return LLDown(LLA3Samp, int2(LL_W3, LL_H3), pos.xy); }
float LLUp3PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return LLUpTop(pos.xy); }
float LLUp2PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return LLUp(LLB3Samp, int2(LL_W3, LL_H3), LLA2Samp, int2(LL_W2, LL_H2), pos.xy); }
float LLUp1PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return LLUp(LLB2Samp, int2(LL_W2, LL_H2), LLA1Samp, int2(LL_W1, LL_H1), pos.xy); }
float LLUp0PS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return LLUp(LLB1Samp, int2(LL_W1, LL_H1), LLA0Samp, int2(LL_W0, LL_H0), pos.xy); }

// Warm-key / cool-fill evidence for one lane pair: a step over 1 stop whose darker side is
// over .1 bluer along LL_SKY (sun beside skylit shade, or a warm lamp beside cool fill).
// Pairs touching near-black (luma <= .004) count as no evidence.
float LLSunEdge(float3 c, float3 nb)
{
    float dl = LLLog(nb) - LLLog(c);
    float s = dot(LLChroma(nb) - LLChroma(c), LL_SKY) * sign(-dl);
    return step(1.0, abs(dl)) * step(0.1, s) * float(min(Luma(c), Luma(nb)) > 0.004);
}

// ─── 4. Anchor: offset that gives the correction zero mean; frame lit level ───
// .r offset; .g frame lit level (log2) = mean + 1.28 sd of the anchored light (~p90).
// .b warm-key evidence (raw, per frame): share of right/down lane pairs at the 16x16 points that
// are sun edges (LLSunEdge), ramped 1.5–3.0%. Offline screen: sun frames 1.4–7.0% (median 3.7),
// overcast 0.2–2.0% (median 0.8); research/2026-11-11_look_target.md.
float4 LLAnchorPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float sum_b = 0.0;
    [loop] for (int j = 0; j < 16; j++)
    [loop] for (int i = 0; i < 16; i++)
        sum_b += tex2Dlod(LLB0Samp, float4((float2(i, j) + 0.5) / 16.0, 0, 0)).r;
    float offset = -LL_SCALE * sum_b / 256.0;          // correction has zero mean
    float s1 = 0.0, s2 = 0.0, sun = 0.0;
    float2 px = 1.0 / float2(LL_W0, LL_H0);
    [loop] for (int j2 = 0; j2 < 16; j2++)
    [loop] for (int i2 = 0; i2 < 16; i2++)
    {
        float2 suv2 = (float2(i2, j2) + 0.5) / 16.0;
        float3 c = LLPoint(LLPtCSamp, suv2);
        float l = LLLog(c) + LL_SCALE * tex2Dlod(LLB0Samp, float4(suv2, 0, 0)).r + offset;
        s1 += l; s2 += l * l;
        sun += LLSunEdge(c, LLPoint(LLPtRSamp, suv2))
             + LLSunEdge(c, LLPoint(LLPtDSamp, suv2));
    }
    float m = s1 / 256.0;
    float sun_w = smoothstep(1.5, 3.0, sun / 512.0 * 100.0);
    return float4(offset, m + 1.2816 * sqrt(max(s2 / 256.0 - m * m, 0.0)), sun_w, 0.0);
}

// Raw per-frame warm-key evidence [0,1]; grade.fx smooths it in the adaptive history.
float LLSunRaw()
{
    return tex2Dlod(LLAnchorSamp, float4(0.5, 0.5, 0, 0)).b;
}

// Stops below the frame's lit level.
float LLBelowLit(float light_log)
{
    return tex2Dlod(LLAnchorSamp, float4(0.5, 0.5, 0, 0)).g - light_log;
}

// ─── 5. Full-resolution light ────────────────────────────────────────────────
float LLLightLog(float2 uv)
{
    float g_l = max(tex2D(NativeGuideLogSamp, uv).r, log2(0.002));
    return g_l + LL_SCALE * tex2D(LLB0LinSamp, uv).r + tex2Dlod(LLAnchorSamp, float4(0.5, 0.5, 0, 0)).r;
}
