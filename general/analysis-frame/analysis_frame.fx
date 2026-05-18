// analysis_frame.fx — Frame-wide histogram analysis
#include "../highway.fxh"
#include "../common.fxh"
//
// Builds per-frame luminance histogram and scene statistics.
// All samples are in linear light — vkBasalt linearizes the sRGB swapchain on read.
// TexHwyTex spatial lane (1/8-res) replaces DownsampleTex (fixed 32×18).
// Histogram still gathers 32×18 = 576 samples from the spatial lane via bilinear reads.

#define DS_W          32
#define DS_H          18
#define HIST_BINS     64
#define LERP_SPEED     4.3
#define KALMAN_Q_PERC_MIN  0.00005
#define KALMAN_Q_PERC_MAX  0.05
#define KALMAN_R_PERC      0.005
#define VFF_E_SIGMA_PERC   0.06

uniform float frametime < source = "frametime"; >;

// ─── Textures ──────────────────────────────────────────────────────────────

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D LumHistRawTex { Width = HIST_BINS; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D LumHistRaw
{
    Texture   = LumHistRawTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// Shared smoothed luma histogram
texture2D LumHistTex { Width = HIST_BINS; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D LumHist
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// Shared percentile cache — r=p25, g=p50, b=p75, a=P (Kalman variance)
// Written here, read by corrective_render_chain and grade
texture2D PercTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D PercSamp
{
    Texture   = PercTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// R53: scene-cut signal — r=scene_cut [0,1], g=p50 from last frame (for delta)
// Written here, read by corrective passes to override Kalman gain
texture2D SceneCutTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D SceneCutSamp
{
    Texture   = SceneCutTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// Scene chroma stats — r=median_C, g=mean_a, b=mean_b, a=achromatic_fraction
// median_C: histogram p50 over all pixels (R116). mean_a/b: arithmetic centroid of ab plane.
texture2D MeanChromaTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D MeanChromaSamp
{
    Texture   = MeanChromaTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// p90 luma cache (r) and p10 shadow floor (g) — EMA-smoothed
texture2D PercHighTex { Width = 1; Height = 1; Format = RG16F; MipLevels = 1; };
sampler2D PercHighSamp
{
    Texture   = PercHighTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// R147: histogram mode (argmax bin center), EMA-smoothed
texture2D ModeTex { Width = 1; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D ModeSamp
{
    Texture   = ModeTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// p75 Oklab C and hue concentration κ — written by ChromaExtraPS
texture2D ChromaExtraTex { Width = 1; Height = 1; Format = RG16F; MipLevels = 1; };
sampler2D ChromaExtraSamp
{
    Texture   = ChromaExtraTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// R195: normalized histogram entropy H_norm, EMA-smoothed
texture2D EntropyTex { Width = 1; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D EntropySamp
{
    Texture   = EntropyTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Pass 1 — TexHwyWrite (spatial lane) ───────────────────────────────────
// Writes pre-correction scene RGB+Luma into TexHwyTex spatial lane (rows 0..BUFFER_HEIGHT/8-1).
// 4-tap box filter at ±1.5 px offsets — same kernel as former ComputeLowFreqPS.
// Data rows pass through from TexHwyTex previous state (grade's NeutralIllum survives).

float4 TexHwyWriteSpatialPS(float4 pos : SV_Position,
                             float2 uv  : TEXCOORD0) : SV_Target
{
    int row = int(pos.y);
    if (row >= TEX_HWY_SPATIAL_H)
        return tex2Dlod(TexHwySamp, float4(uv, 0, 0));  // data rows: pass-through
    // Spatial lane: 4-tap box downsample from BackBuffer.
    // uv.y maps [0, SPATIAL_H/TOTAL_H) when row < SPATIAL_H — rescale to full [0,1] for BB.
    float bb_y = uv.y * float(TEX_HWY_TOTAL_H) / float(TEX_HWY_SPATIAL_H);
    float2 bb_uv = float2(uv.x, bb_y);
    float2 px = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float3 rgb = 0.0;
    rgb += tex2D(BackBuffer, bb_uv + float2(-1.5, -1.5) * px).rgb;
    rgb += tex2D(BackBuffer, bb_uv + float2( 1.5, -1.5) * px).rgb;
    rgb += tex2D(BackBuffer, bb_uv + float2(-1.5,  1.5) * px).rgb;
    rgb += tex2D(BackBuffer, bb_uv + float2( 1.5,  1.5) * px).rgb;
    rgb *= 0.25;
    return float4(rgb, Luma(rgb));
}

// ─── Pass 2 — Luminance histogram gather ───────────────────────────────────
// Gathers DS_W×DS_H = 576 bilinear samples from TexHwyTex spatial lane.
// Resolution-independent: samples are spaced evenly across the spatial lane
// regardless of BUFFER_WIDTH/HEIGHT (unlike the old fixed 32×18 DownsampleTex).

float4 LumHistGatherPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    int   b         = int(pos.x);
    float bucket_lo = float(b)     / float(HIST_BINS);
    float bucket_hi = float(b + 1) / float(HIST_BINS);
    float scale_y   = float(TEX_HWY_SPATIAL_H) / float(TEX_HWY_TOTAL_H);

    float count = 0.0;
    [loop]
    for (int y = 0; y < DS_H; y++)
    {
        [loop]
        for (int x = 0; x < DS_W; x++)
        {
            float2 s_uv = float2((x + 0.5) / float(DS_W),
                                 (y + 0.5) / float(DS_H) * scale_y);
            float  luma = tex2Dlod(TexHwySamp, float4(s_uv, 0, 0)).a;
            count += (luma >= bucket_lo && luma < bucket_hi) ? 1.0 : 0.0;
        }
    }

    return float4(count / float(DS_W * DS_H), 0.0, 0.0, 1.0);
}

// ─── Pass 3 — Passthrough ─────────────────────────────────────────────────

float4 PassthroughPS(float4 pos : SV_Position,
                     float2 uv  : TEXCOORD0) : SV_Target
{
    return tex2D(BackBuffer, uv);
}

// ─── Pass 10b — TexHwy data rows write ─────────────────────────────────────
// Packs private analysis textures into TexHwyTex data rows.
// Spatial lane (row < BUFFER_HEIGHT/8): pass-through from TexHwyWriteSpatial.
// Data row 0: analysis stats (5 pixels). Data rows 1..4: pass-through (corrective writes).

float4 TexHwyWriteDataPS(float4 pos : SV_Position,
                          float2 uv  : TEXCOORD0) : SV_Target
{
    int row = int(pos.y);
    int col = int(pos.x);
    if (row < TEX_HWY_SPATIAL_H)
        return tex2Dlod(TexHwySamp, float4(uv, 0, 0));  // spatial lane: pass-through
    int dr = row - TEX_HWY_SPATIAL_H;
    if (dr == 0) {
        if (col == 0) return tex2Dlod(PercSamp,         float4(0.5, 0.5, 0, 0));
        if (col == 1) {
            float2 ph = tex2Dlod(PercHighSamp,    float4(0.5, 0.5, 0, 0)).rg;
            float2 ce = tex2Dlod(ChromaExtraSamp, float4(0.5, 0.5, 0, 0)).rg;
            return float4(ph.r, ph.g, ce.r, ce.g);
        }
        if (col == 2) return tex2Dlod(MeanChromaSamp,   float4(0.5, 0.5, 0, 0));
        if (col == 3) {
            float sc   = tex2Dlod(SceneCutSamp,  float4(0.5, 0.5, 0, 0)).r;
            float p50p = tex2Dlod(SceneCutSamp,  float4(0.5, 0.5, 0, 0)).g;
            float mode = tex2Dlod(ModeSamp,      float4(0.5, 0.5, 0, 0)).r;
            float ent  = tex2Dlod(EntropySamp,   float4(0.5, 0.5, 0, 0)).r;
            return float4(sc, p50p, mode, ent);
        }
    }
    return tex2Dlod(TexHwySamp, float4(uv, 0, 0));  // all other pixels: pass-through
}

// ─── Pass 10 — Highway write (HighwayTex, 256×1) ──────────────────────────
// Runs after all analysis passes so all source textures hold current-frame data.
// Unknown slots pass through the previous HighwayTex state (corrective adds its own).

float4 HighwayWritePS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    int    xi   = int(pos.x);
    float4 perc = tex2Dlod(PercSamp,       float4(0.5, 0.5, 0, 0));
    if (xi == HWY_P25) return float4(perc.r, 0, 0, 1);
    if (xi == HWY_P50) return float4(perc.g, 0, 0, 1);
    if (xi == HWY_P75) return float4(perc.b, 0, 0, 1);
    if (xi == HWY_CHROMA_SLOPE) {
        float median_C = tex2Dlod(MeanChromaSamp, float4(0.5, 0.5, 0, 0)).r;
        float slope    = lerp(1.8, 1.15, saturate(median_C / 0.15));
        return float4((slope - 1.0) / 1.5, 0, 0, 1);
    }
    if (xi == HWY_SCENE_CUT)
        return float4(tex2Dlod(SceneCutSamp,  float4(0.5, 0.5, 0, 0)).r, 0, 0, 1);
    if (xi == HWY_MEDIAN_C)
        return float4(tex2Dlod(MeanChromaSamp, float4(0.5, 0.5, 0, 0)).r, 0, 0, 1);
    if (xi == HWY_P90)
        return float4(tex2Dlod(PercHighSamp,  float4(0.5, 0.5, 0, 0)).r, 0, 0, 1);
    if (xi == HWY_CHROMA_ANGLE) {
        float2 ab = tex2Dlod(MeanChromaSamp, float4(0.5, 0.5, 0, 0)).gb;
        return float4((atan2(ab.y, ab.x) + 3.14159265) / (2.0 * 3.14159265), 0, 0, 1);
    }
    if (xi == HWY_ACHROM_FRAC)
        return float4(tex2Dlod(MeanChromaSamp, float4(0.5, 0.5, 0, 0)).a, 0, 0, 1);
    if (xi == HWY_MODE)
        return float4(tex2Dlod(ModeSamp,      float4(0.5, 0.5, 0, 0)).r, 0, 0, 1);
    if (xi == HWY_H_NORM)
        return float4(tex2Dlod(EntropySamp,   float4(0.5, 0.5, 0, 0)).r, 0, 0, 1);
    if (xi == HWY_IQR)
        return float4(perc.b - perc.r, 0, 0, 1);
    if (xi == HWY_P10)
        return float4(tex2Dlod(PercHighSamp,   float4(0.5, 0.5, 0, 0)).g, 0, 0, 1);
    if (xi == HWY_CHROMA_P75)
        return float4(tex2Dlod(ChromaExtraSamp, float4(0.5, 0.5, 0, 0)).r, 0, 0, 1);
    if (xi == HWY_HUE_CONC)
        return float4(tex2Dlod(ChromaExtraSamp, float4(0.5, 0.5, 0, 0)).g, 0, 0, 1);
    return float4(ReadHWY(xi), 0, 0, 1);  // pass through corrective's slots unchanged
}

// ─── Pass 4 — Smooth luminance histogram ───────────────────────────────────

float4 LumHistSmoothPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float raw  = tex2D(LumHistRaw, uv).r;
    float prev = tex2D(LumHist,    uv).r;
    return float4(lerp(prev, raw, saturate((LERP_SPEED / 100.0) * (frametime / 10.0))), 0.0, 0.0, 1.0);
}

// ─── Pass 4b — Normalized histogram entropy (R195) ────────────────────────
// H_norm = −Σ h_i·log₂(h_i) / log₂(64). Source: EMA-smoothed LumHist.
// H_norm=0: all mass at one luminance (fog/overexposure). H_norm=1: uniform spread.
// Drives zone S-curve attenuation in grade.fx BuildSceneCtx.

float4 HistEntropyPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float H = 0.0;
    [loop] for (int b = 0; b < 64; b++)
    {
        float h  = tex2Dlod(LumHist, float4((float(b) + 0.5) / 64.0, 0.5, 0, 0)).r;
        H       -= h * log2(max(h, 1e-6));
    }
    float h_norm = saturate(H / 6.0);
    float prev   = tex2Dlod(EntropySamp, float4(0.5, 0.5, 0, 0)).r;
    float alpha  = saturate(frametime * 0.002);
    return float4(lerp(prev, h_norm, alpha), 0, 0, 1);
}

// ─── Pass 5 — CDF walk → 1×1 percentile cache ─────────────────────────────
// Trimmed: targets 0.275/0.50/0.725 exclude the bottom and top 5% of mass,
// making anchors immune to specular spikes and crushed-black collapse.
// Intra-bin interpolation raises effective resolution from 1/64 to ~1/512.

float4 CDFWalkPS(float4 pos : SV_Position,
                 float2 uv  : TEXCOORD0) : SV_Target
{
    float cumul = 0.0;
    float p25 = 0.25, p50 = 0.50, p75 = 0.75;
    float lk25 = 0.0, lk50 = 0.0, lk75 = 0.0;

    [loop] for (int b = 0; b < HIST_BINS; b++)
    {
        float frc  = tex2Dlod(LumHist, float4((float(b) + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r;
        float prev = cumul;
        cumul += frc;

        float inv  = (frc > 0.0) ? 1.0 / frc : 0.0;
        float t25  = saturate((0.275 - prev) * inv);
        float t50  = saturate((0.500 - prev) * inv);
        float t75  = saturate((0.725 - prev) * inv);

        float bv25 = (float(b) + t25) / float(HIST_BINS);
        float bv50 = (float(b) + t50) / float(HIST_BINS);
        float bv75 = (float(b) + t75) / float(HIST_BINS);

        float at25 = step(0.275, cumul) * (1.0 - lk25);
        float at50 = step(0.500, cumul) * (1.0 - lk50);
        float at75 = step(0.725, cumul) * (1.0 - lk75);
        p25  = lerp(p25, bv25, at25);
        p50  = lerp(p50, bv50, at50);
        p75  = lerp(p75, bv75, at75);
        lk25 = saturate(lk25 + at25);
        lk50 = saturate(lk50 + at50);
        lk75 = saturate(lk75 + at75);
    }

    // R34+R39: VFF Kalman on percentile outputs — P in .a (replaces IQR sentinel)
    float4 prev    = tex2D(PercSamp, float2(0.5, 0.5));
    float  P       = (prev.a < 0.001) ? 1.0 : prev.a;
    float  e_p50   = p50 - prev.g;
    float  Q_vff_p = lerp(KALMAN_Q_PERC_MIN, KALMAN_Q_PERC_MAX, smoothstep(0.0, VFF_E_SIGMA_PERC, abs(e_p50)));
    float  P_pred  = P + Q_vff_p;
    float  K       = P_pred / (P_pred + KALMAN_R_PERC);
    float  P_new   = (1.0 - K) * P_pred;
    float  h_p     = 1.0 - 0.5 * smoothstep(0.0, VFF_E_SIGMA_PERC * 8.0, abs(e_p50));
    return float4(prev.r + K * (p25 - prev.r) * h_p,
                  prev.g + K * e_p50 * h_p,
                  prev.b + K * (p75 - prev.b) * h_p,
                  P_new);
}

// ─── Pass 6 — R53: scene-cut detection ────────────────────────────────────

float4 SceneCutPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float p50_now  = tex2Dlod(PercSamp,    float4(0.5, 0.5, 0, 0)).g;
    float p50_prev = tex2Dlod(SceneCutSamp, float4(0.5, 0.5, 0, 0)).g;
    float scene_cut = smoothstep(0.10, 0.25, abs(p50_now - p50_prev));
    return float4(scene_cut, p50_now, 0.0, 1.0);
}

// ─── Pass 7 — Scene median Oklab chroma ───────────────────────────────────
// R116: replaced arithmetic mean_C with histogram p50 (median). Mean was biased
// toward saturated outliers (neon, fire, UI), causing inverse_grade to over-expand
// globally and wash out shadows. Median tracks typical scene chroma.
// (a, b) direction kept as arithmetic mean — direction is robust, magnitude is not.
// 32 bins over [0, 0.30] — bin width ~0.009, intra-bin interp gives ~0.001 resolution.

#define CHROMA_BINS   32
#define CHROMA_C_MAX  0.30

float ComputeMedianC(float hist[CHROMA_BINS], float count)
{
    float target   = max(count, 1.0) * 0.50;
    float cumul    = 0.0;
    float median_C = 0.10;
    float lk       = 0.0;
    [loop] for (int b = 0; b < CHROMA_BINS; b++)
    {
        float prev_c = cumul;
        cumul       += hist[b];
        float inv    = (hist[b] > 0.0) ? 1.0 / hist[b] : 0.0;
        float t      = saturate((target - prev_c) * inv);
        float bv     = (float(b) + t) / float(CHROMA_BINS) * CHROMA_C_MAX;
        float at     = step(target, cumul) * (1.0 - lk);
        median_C     = lerp(median_C, bv, at);
        lk           = saturate(lk + at);
    }
    return median_C;
}

float4 MeanChromaPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float hist[CHROMA_BINS];
    [unroll] for (int i = 0; i < CHROMA_BINS; i++) hist[i] = 0.0;

    float sum_a = 0.0, sum_b = 0.0;
    float count = 0.0, achrom_count = 0.0;
    float scale_y = float(TEX_HWY_SPATIAL_H) / float(TEX_HWY_TOTAL_H);
    [loop]
    for (int y = 0; y < DS_H; y++)
    {
        [loop]
        for (int x = 0; x < DS_W; x++)
        {
            float2 s_uv = float2((x + 0.5) / float(DS_W),
                                 (y + 0.5) / float(DS_H) * scale_y);
            float3 lab  = RGBtoOklab(tex2Dlod(TexHwySamp, float4(s_uv, 0, 0)).rgb);
            float  C    = length(lab.yz);
            float  in_b = step(0.05, C);
            int    bin  = clamp(int(C / CHROMA_C_MAX * CHROMA_BINS), 0, CHROMA_BINS - 1);
            hist[bin]  += in_b;
            sum_a      += lab.y * in_b;
            sum_b      += lab.z * in_b;
            count      += in_b;
            achrom_count += 1.0 - in_b;
        }
    }

    float median_C    = ComputeMedianC(hist, count);
    float valid       = step(0.5, count);
    float inv_count   = 1.0 / max(count, 1.0);
    float out_C       = lerp(0.10, median_C, valid);
    float mean_a      = lerp(0.0,  sum_a * inv_count, valid);
    float mean_b      = lerp(0.0,  sum_b * inv_count, valid);
    float achrom_frac = achrom_count / float(DS_W * DS_H);

    float4 prev      = tex2Dlod(MeanChromaSamp, float4(0.5, 0.5, 0, 0));
    float  scene_cut = tex2Dlod(SceneCutSamp,  float4(0.5, 0.5, 0, 0)).r;
    float  alpha     = lerp(saturate(frametime * 0.001), 1.0, scene_cut);
    return float4(
        lerp(prev.r, out_C,       alpha),
        lerp(prev.g, mean_a,      alpha),
        lerp(prev.b, mean_b,      alpha),
        lerp(prev.a, achrom_frac, alpha)
    );
}

// ─── Pass 7b — p75 Oklab C and hue concentration κ ───────────────────────
// p75_C: 75th percentile of per-pixel Oklab C over chromatic pixels (C > 0.05).
//   Complements median_C: median tracks typical chroma, p75_C tracks the vivid tail.
//   High p75_C with low median_C = a few vivid objects in a muted scene.
// κ: mean resultant length = |mean_ab| / median_C.
//   κ≈1: all chromatic pixels share one hue (sunset, underwater).
//   κ≈0: hue distribution is uniform (forest, cityscape).
//   Computed from existing MeanChromaSamp — no extra pixel loop needed for κ.

float4 ChromaExtraPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float hist[CHROMA_BINS];
    [unroll] for (int i = 0; i < CHROMA_BINS; i++) hist[i] = 0.0;

    float count = 0.0;
    float scale_y = float(TEX_HWY_SPATIAL_H) / float(TEX_HWY_TOTAL_H);
    [loop]
    for (int y = 0; y < DS_H; y++)
    {
        [loop]
        for (int x = 0; x < DS_W; x++)
        {
            float2 s_uv = float2((x + 0.5) / float(DS_W),
                                 (y + 0.5) / float(DS_H) * scale_y);
            float3 lab  = RGBtoOklab(tex2Dlod(TexHwySamp, float4(s_uv, 0, 0)).rgb);
            float  C    = length(lab.yz);
            float  in_b = step(0.05, C);
            int    bin  = clamp(int(C / CHROMA_C_MAX * CHROMA_BINS), 0, CHROMA_BINS - 1);
            hist[bin]  += in_b;
            count      += in_b;
        }
    }

    float target = max(count, 1.0) * 0.75;
    float cumul  = 0.0;
    float p75_C  = CHROMA_C_MAX * 0.75;
    float lk     = 0.0;
    [loop] for (int b = 0; b < CHROMA_BINS; b++)
    {
        float prev_c = cumul;
        cumul       += hist[b];
        float inv    = (hist[b] > 0.0) ? 1.0 / hist[b] : 0.0;
        float t      = saturate((target - prev_c) * inv);
        float bv     = (float(b) + t) / float(CHROMA_BINS) * CHROMA_C_MAX;
        float at     = step(target, cumul) * (1.0 - lk);
        p75_C        = lerp(p75_C, bv, at);
        lk           = saturate(lk + at);
    }
    float valid = step(0.5, count);
    p75_C = lerp(CHROMA_C_MAX * 0.75, p75_C, valid);

    float4 mc    = tex2Dlod(MeanChromaSamp, float4(0.5, 0.5, 0, 0));
    float  kappa = saturate(length(mc.gb) / max(mc.r, 0.001));

    float2 prev      = tex2Dlod(ChromaExtraSamp, float4(0.5, 0.5, 0, 0)).rg;
    float  scene_cut = tex2Dlod(SceneCutSamp,    float4(0.5, 0.5, 0, 0)).r;
    float  alpha     = lerp(saturate(frametime * 0.001), 1.0, scene_cut);
    return float4(lerp(prev.r, p75_C, alpha), lerp(prev.g, kappa, alpha), 0.0, 1.0);
}

// ─── Pass 8 — p90 luma percentile ────────────────────────────────────────
// Same 64-bin CDF walk as CDFWalkPS but targets the 90th percentile.
// No Kalman — simple EMA is sufficient for a coarse highlight threshold signal.

float4 CDFWalkHighPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float cumul = 0.0;
    float p90 = 0.90, p10 = 0.10;
    float lk90 = 0.0,  lk10 = 0.0;

    [loop] for (int b = 0; b < HIST_BINS; b++)
    {
        float frc  = tex2Dlod(LumHist, float4((float(b) + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r;
        float prev = cumul;
        cumul += frc;

        float inv  = (frc > 0.0) ? 1.0 / frc : 0.0;
        float t90  = saturate((0.90 - prev) * inv);
        float t10  = saturate((0.10 - prev) * inv);
        float bv90 = (float(b) + t90) / float(HIST_BINS);
        float bv10 = (float(b) + t10) / float(HIST_BINS);
        float at90 = step(0.90, cumul) * (1.0 - lk90);
        float at10 = step(0.10, cumul) * (1.0 - lk10);
        p90  = lerp(p90, bv90, at90);
        p10  = lerp(p10, bv10, at10);
        lk90 = saturate(lk90 + at90);
        lk10 = saturate(lk10 + at10);
    }

    float2 prev = tex2Dlod(PercHighSamp, float4(0.5, 0.5, 0, 0)).rg;
    float alpha = saturate(frametime * 0.005);
    return float4(lerp(prev.r, p90, alpha), lerp(prev.g, p10, alpha), 0.0, 1.0);
}

// ─── Pass 9 — R147: histogram mode (argmax bin center) ───────────────────
// Branchless argmax: step(best_val + 1e-6, frc) gates a lerp that tracks the
// running maximum bin across the 64-bin loop. EMA-smoothed; scene-cut resets.

float4 CDFWalkModePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float best_val = 0.0;
    float mode = 0.5 / float(HIST_BINS);

    [loop] for (int b = 0; b < HIST_BINS; b++)
    {
        float frc    = tex2Dlod(LumHist, float4((float(b) + 0.5) / float(HIST_BINS), 0.5, 0, 0)).r;
        float better = step(best_val + 1e-6, frc);
        best_val     = lerp(best_val, frc, better);
        mode         = lerp(mode, (float(b) + 0.5) / float(HIST_BINS), better);
    }

    float prev       = tex2Dlod(ModeSamp, float4(0.5, 0.5, 0, 0)).r;
    float scene_cut  = tex2Dlod(SceneCutSamp, float4(0.5, 0.5, 0, 0)).r;
    float alpha      = saturate(frametime * 0.005);
    alpha            = lerp(alpha, 1.0, scene_cut);
    return float4(lerp(prev, mode, alpha), 0.0, 0.0, 1.0);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique FrameAnalysis
{
    pass TexHwyWriteSpatial
    {
        VertexShader = PostProcessVS;
        PixelShader  = TexHwyWriteSpatialPS;
        RenderTarget = TexHwyTex;
    }
    pass LumHistGather
    {
        VertexShader = PostProcessVS;
        PixelShader  = LumHistGatherPS;
        RenderTarget = LumHistRawTex;
    }
    pass Passthrough
    {
        VertexShader = PostProcessVS;
        PixelShader  = PassthroughPS;
    }
    pass LumHistSmooth
    {
        VertexShader = PostProcessVS;
        PixelShader  = LumHistSmoothPS;
        RenderTarget = LumHistTex;
    }
    pass HistEntropy
    {
        VertexShader = PostProcessVS;
        PixelShader  = HistEntropyPS;
        RenderTarget = EntropyTex;
    }
    pass CDFWalk
    {
        VertexShader = PostProcessVS;
        PixelShader  = CDFWalkPS;
        RenderTarget = PercTex;
    }
    pass SceneCut
    {
        VertexShader = PostProcessVS;
        PixelShader  = SceneCutPS;
        RenderTarget = SceneCutTex;
    }
    pass CDFWalkHigh
    {
        VertexShader = PostProcessVS;
        PixelShader  = CDFWalkHighPS;
        RenderTarget = PercHighTex;
    }
    pass MeanChroma
    {
        VertexShader = PostProcessVS;
        PixelShader  = MeanChromaPS;
        RenderTarget = MeanChromaTex;
    }
    pass ChromaExtra
    {
        VertexShader = PostProcessVS;
        PixelShader  = ChromaExtraPS;
        RenderTarget = ChromaExtraTex;
    }
    pass CDFWalkMode
    {
        VertexShader = PostProcessVS;
        PixelShader  = CDFWalkModePS;
        RenderTarget = ModeTex;
    }
    pass TexHwyWriteData
    {
        VertexShader = PostProcessVS;
        PixelShader  = TexHwyWriteDataPS;
        RenderTarget = TexHwyTex;
    }
    pass HighwayWrite
    {
        VertexShader = PostProcessVS;
        PixelShader  = HighwayWritePS;
        RenderTarget = HighwayTex;
    }
}
