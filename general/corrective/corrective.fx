// corrective.fx — Game-agnostic corrective analysis chain
#include "debug_text.fxh"
#include "../highway.fxh"
#include "../hue_bands.fxh"
#include "../common.fxh"
//
// Prepares all analysis textures consumed by grade.fx (MegaPass).
// Single vkBasalt effect — no inter-effect BackBuffer clears, no wasted Passthroughs.
//
// Passes:
//   1. ComputeLowFreq       BackBuffer → CreativeLowFreqTex    1/8 res downsample
//   2. ComputeZoneHistogram CreativeLowFreqTex → CreativeZoneHistTex  32-bin per-zone histogram
//   3. BuildZoneLevels      CreativeZoneHistTex → CreativeZoneLevelsTex  CDF → zone medians
//   4. SmoothZoneLevels     CreativeZoneLevelsTex → ZoneHistoryTex  temporal smoothing
//   5. UpdateHistory        BackBuffer → ChromaHistoryTex  per-band Oklab chroma stats
//   6. Passthrough          BackBuffer → BackBuffer  keeps BB non-black for vkBasalt
// R152: WarmBias pass removed (dead — no consumer); 6 passes remain.

#include "creative_values.fx"

#define KALMAN_Q_MIN     0.0001   // process noise: steady-state (scene stable)
#define KALMAN_Q_MAX     0.10     // process noise: scene cut (K rises to ~0.91)
#define VFF_E_SIGMA      0.08     // innovation scale for luma — triggers ramp at 0.08 luma units
#define VFF_E_SIGMA_CHROMA 0.04   // innovation scale for chroma — Oklab a/b magnitudes are smaller
#define KALMAN_R         0.01     // measurement noise
#define KALMAN_K_INF     0.095    // steady-state gain for secondary channels (EMA)
#define SAT_THRESHOLD    2

uniform float FRAME_TIMER < source = "timer"; >;        // ms since app start

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

texture2D CreativeLowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; MipLevels = 1; };  // R117: mip1/2 never used (grade.fx builds LowFreqMip1/2Tex explicitly)
sampler2D CreativeLowFreqSamp
{
    Texture   = CreativeLowFreqTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D CreativeZoneHistTex { Width = 32; Height = 16; Format = R16F; MipLevels = 1; };
sampler2D CreativeZoneHistSamp
{
    Texture   = CreativeZoneHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D CreativeZoneLevelsTex { Width = 4; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D CreativeZoneLevelsSamp
{
    Texture   = CreativeZoneLevelsTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D ZoneHistoryTex { Width = 4; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D ZoneHistorySamp
{
    Texture   = ZoneHistoryTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D ChromaHistoryTex { Width = 8; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D ChromaHistory
{
    Texture   = ChromaHistoryTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// Global scene percentiles — r=p25, g=p50, b=p75, a=P (written by analysis_frame)
texture2D PercTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D PercSamp
{
    Texture   = PercTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};


// ─── Helpers ───────────────────────────────────────────────────────────────

// ─── Halton(2,3) sequence — procedural, avoids static const array SPIR-V issue ──

float Halton2(uint i)
{
    float r = 0.0, f = 0.5;
    [unroll] for (int b = 0; b < 8; b++) { r += f * float(i & 1u); i >>= 1u; f *= 0.5; }
    return r;
}

float Halton3(uint i)
{
    float r = 0.0, f = 1.0 / 3.0;
    [unroll] for (int b = 0; b < 6; b++) { r += f * float(i % 3u); i /= 3u; f /= 3.0; }
    return r;
}

// ─── Pass 1 — 1/8 res downsample ───────────────────────────────────────────

float4 ComputeLowFreqPS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    float2 px = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float3 rgb = 0.0;
    rgb += tex2D(BackBuffer, uv + float2(-1.5, -1.5) * px).rgb;
    rgb += tex2D(BackBuffer, uv + float2( 1.5, -1.5) * px).rgb;
    rgb += tex2D(BackBuffer, uv + float2(-1.5,  1.5) * px).rgb;
    rgb += tex2D(BackBuffer, uv + float2( 1.5,  1.5) * px).rgb;
    rgb *= 0.25;
    return float4(rgb, Luma(rgb));
}

// ─── Pass 2 — per-zone 32-bin luma histogram ───────────────────────────────

float4 ComputeZoneHistogramPS(float4 pos : SV_Position,
                              float2 uv  : TEXCOORD0) : SV_Target
{
    int b        = int(pos.x);
    int zone     = int(pos.y);
    int zone_col = zone % 4;
    int zone_row = zone / 4;

    float u_lo      = float(zone_col) / 4.0;
    float v_lo      = float(zone_row) / 4.0;
    float bucket_lo = float(b)     / 32.0;
    float bucket_hi = float(b + 1) / 32.0;

    float count = 0.0;
    [loop] for (int sy = 0; sy < 10; sy++)
    [loop] for (int sx = 0; sx < 10; sx++)
    {
        float2 suv  = float2(u_lo + (sx + 0.5) / 10.0 * 0.25,
                             v_lo + (sy + 0.5) / 10.0 * 0.25);
        float  luma = tex2Dlod(CreativeLowFreqSamp, float4(suv, 0, 0)).a;
        count += (luma >= bucket_lo && luma < bucket_hi) ? 1.0 : 0.0;
    }

    float v = count / 100.0;
    return float4(v, v, v, 1.0);
}

// ─── Pass 3 — CDF walk → zone medians ──────────────────────────────────────

float4 BuildZoneLevelsPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    int zone_x = int(pos.x);
    int zone_y = int(pos.y);
    int zone   = zone_y * 4 + zone_x;

    float cumulative = 0.0;
    float p25 = 0.25, median = 0.5, p75 = 0.75;
    float lock25 = 0.0, lock50 = 0.0, lock75 = 0.0;
    float sum_x = 0.0, sum_x2 = 0.0;  // R116: histogram moments for intra-zone variance

    [loop] for (int b = 0; b < 32; b++)
    {
        float bc   = (float(b) + 0.5) / 32.0;  // bin centre for variance moments
        float frac = tex2Dlod(CreativeZoneHistSamp,
            float4((float(b) + 0.5) / 32.0, (float(zone) + 0.5) / 16.0, 0, 0)).r;
        float prev = cumulative;
        cumulative += frac;
        sum_x      += bc * frac;
        sum_x2     += bc * bc * frac;

        // Intra-bin interpolation — matches CDFWalkPS precision (~8× vs raw bin edge)
        float inv  = (frac > 0.0) ? 1.0 / frac : 0.0;
        float t25  = saturate((0.25 - prev) * inv);
        float t50  = saturate((0.50 - prev) * inv);
        float t75  = saturate((0.75 - prev) * inv);
        float bv25 = (float(b) + t25) / 32.0;
        float bv50 = (float(b) + t50) / 32.0;
        float bv75 = (float(b) + t75) / 32.0;
        float at25 = step(0.25, cumulative) * (1.0 - lock25);
        float at50 = step(0.50, cumulative) * (1.0 - lock50);
        float at75 = step(0.75, cumulative) * (1.0 - lock75);
        p25    = lerp(p25,    bv25, at25);
        median = lerp(median, bv50, at50);
        p75    = lerp(p75,    bv75, at75);
        lock25 = saturate(lock25 + at25);
        lock50 = saturate(lock50 + at50);
        lock75 = saturate(lock75 + at75);
    }

    // E[X²] - E[X]² = per-pixel luma variance within this zone
    float intra_std = sqrt(max(sum_x2 - sum_x * sum_x, 0.0));
    return float4(median, p25, p75, intra_std);
}

// ─── Pass 4 — temporal smoothing ───────────────────────────────────────────

float4 SmoothZoneLevelsPS(float4 pos : SV_Position,
                          float2 uv  : TEXCOORD0) : SV_Target
{
    float4 current = tex2D(CreativeZoneLevelsSamp, uv);
    float4 prev    = tex2D(ZoneHistorySamp, uv);

    float scene_cut = ReadHWY(HWY_SCENE_CUT);
    float k         = lerp(KALMAN_K_INF, 1.0, scene_cut);
    float median    = lerp(prev.r, current.r, k);
    float p25       = lerp(prev.g, current.g, k);
    float p75       = lerp(prev.b, current.b, k);
    float intra_std = lerp(prev.a, current.a, k);  // R116: per-zone intra_std

    return float4(median, p25, p75, intra_std);
}

// ─── Pass 5 — per-band chroma stats ────────────────────────────────────────

float4 ComputeZoneStats()
{
    float m = 0.0, avg_intra_std = 0.0;
    [unroll] for (int zy = 0; zy < 4; zy++)
    [unroll] for (int zx = 0; zx < 4; zx++)
    {
        float4 zs = tex2Dlod(ZoneHistorySamp,
            float4((zx + 0.5) / 4.0, (zy + 0.5) / 4.0, 0, 0));
        m             += zs.r;
        avg_intra_std += zs.a;
    }
    // R116: zone_log_key = linear mean of zone medians; zone_std = mean of per-zone intra_std
    return float4(m * 0.0625, avg_intra_std * 0.0625, 0.0, 0.0);
}

float4 ComputeSlowKey()
{
    float zone_log_key = tex2Dlod(ChromaHistory, float4(6.5 / 8.0, 0.5 / 4.0, 0, 0)).r;
    float prev_slow    = tex2Dlod(ChromaHistory, float4(7.5 / 8.0, 0.5 / 4.0, 0, 0)).r;
    prev_slow = lerp(zone_log_key, prev_slow, step(0.001, prev_slow));
    return float4(lerp(prev_slow, zone_log_key, 0.003), 0, 0, 0);
}

float4 UpdateChromaKalman(int band_idx)
{
    uint  base_idx = (uint(FRAME_TIMER / 41.667) * 8u) % 256u;
    float sum_w    = 0.0;
    float sum_wc   = 0.0;
    float sum_wc2  = 0.0;
    [unroll] for (int i = 0; i < 8; i++)
    {
        uint   idx  = (base_idx + uint(i)) % 256u;
        float2 s_uv = float2(Halton2(idx), Halton3(idx));
        float3 lab  = RGBtoOklab(tex2D(BackBuffer, s_uv).rgb);
        float  C    = length(lab.yz);
        float  h    = OklabHueNorm(lab.y, lab.z);
        float  w    = HueBandWeight(h, GetBandCenter(band_idx)) * smoothstep(0.03, 0.08, C);
        float  C_c  = min(C, 0.20);  // clamp outliers (neon, fire) from biasing the pivot
        sum_w   += w;
        sum_wc  += w * C_c;
        sum_wc2 += w * C_c * C_c;
    }
    float mean   = sum_wc  / max(sum_w, 0.001);
    float var    = max(sum_wc2 / max(sum_w, 0.001) - mean * mean, 0.0);
    float stddev = sqrt(var);
    // R171: observation confidence — how much of sum_w came from real hue matches.
    // Absent bands (sum_w≈0) get obs_confidence≈0: Q collapses to Q_MIN, K→0, EMA→0.
    // State freezes; P still inflates via Q_MIN so re-entry adapts immediately.
    float obs_confidence = saturate(sum_w * 0.5);

    float4 prev    = tex2D(ChromaHistory, float2((band_idx + 0.5) / 8.0, 0.5 / 4.0));
    // R39: VFF Kalman — chroma mean (.r), P in .a, cold-start when uninitialized
    float P_prev   = (prev.a < 0.001) ? 1.0 : prev.a;
    float e_chroma = mean - prev.r;
    // R88: Sage-Husa Q — driven by posterior P, not instantaneous innovation spike
    // R171: gate by obs_confidence — no Q inflation when band absent
    float Q_vff_c  = lerp(KALMAN_Q_MIN,
                          lerp(KALMAN_Q_MIN, KALMAN_Q_MAX,
                               smoothstep(KALMAN_R * 0.5, KALMAN_R * 5.0, P_prev)),
                          obs_confidence);
    float P_pred   = P_prev + Q_vff_c;
    float K        = P_pred / (P_pred + KALMAN_R);
    // R53: scene-cut override — spike K toward 1.0 on hard cuts
    float scene_cut = ReadHWY(HWY_SCENE_CUT);
    K = lerp(K, 1.0, scene_cut) * obs_confidence;
    float new_mean = prev.r + K * e_chroma;
    float P_new    = saturate((1.0 - K) * P_pred);
    // EMA: std and wsum — gate by obs_confidence so absent bands don't decay
    float k_ema    = lerp(KALMAN_K_INF, 1.0, scene_cut) * obs_confidence;
    return float4(new_mean, lerp(prev.g, stddev, k_ema), lerp(prev.b, sum_w, k_ema), P_new);
}

float4 UpdateHistoryPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    int band_idx = int(pos.x);
    if (pos.y >= 1.0 || band_idx >= 8) return float4(0, 0, 0, 0);
    if (band_idx == 6) return ComputeZoneStats();
    if (band_idx == 7) return ComputeSlowKey();
    return UpdateChromaKalman(band_idx);
}


// ─── Pass 8 — Passthrough ──────────────────────────────────────────────────

float4 PassthroughPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 c = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) {
        int xi = int(pos.x);
        if (xi == HWY_STEVENS) {
            // R153: mode is the dominant scene luminance — more accurate Stevens calibration
            // than zone_log_key (mean of zone medians), which is pulled up by bright zones.
            float mode = ReadHWY(HWY_MODE);
            float fc_s = (1.48 + exp2(log2(max(mode, 1e-6)) * (1.0 / 3.0))) / 2.04;
            return float4(saturate(fc_s / 1.3), 0.0, 0.0, 1.0);
        }
        if (xi == HWY_ZONE_KEY || xi == HWY_ZONE_STD) {
            float4 ch6 = tex2Dlod(ChromaHistory, float4(6.5 / 8.0, 0.5 / 4.0, 0, 0));
            return float4(xi == HWY_ZONE_KEY ? ch6.r : ch6.g, 0.0, 0.0, 1.0);
        }
        if (xi == HWY_SLOW_KEY)
            return float4(tex2Dlod(ChromaHistory, float4(7.5 / 8.0, 0.5 / 4.0, 0, 0)).r, 0.0, 0.0, 1.0);
        return c;
    }
    c = DrawLabel(c, pos.xy, 270.0, 26.0,
                  51u, 67u, 79u, 82u, float3(0.1, 0.90, 0.1));  // 3COR
    c = DrawLabel(c, pos.xy, 270.0, 34.0,
                  52u, 90u, 79u, 78u, float3(0.7, 0.20, 1.0));  // 4ZON
    c = DrawLabel(c, pos.xy, 270.0, 42.0,
                  53u, 67u, 72u, 82u, float3(1.0, 0.20, 0.20)); // 5CHR
    return c;
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique Corrective
{
    pass ComputeLowFreq
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeLowFreqPS;
        RenderTarget = CreativeLowFreqTex;
    }
    pass ComputeZoneHistogram
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeZoneHistogramPS;
        RenderTarget = CreativeZoneHistTex;
    }
    pass BuildZoneLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildZoneLevelsPS;
        RenderTarget = CreativeZoneLevelsTex;
    }
    pass SmoothZoneLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = SmoothZoneLevelsPS;
        RenderTarget = ZoneHistoryTex;
    }
    pass UpdateHistory
    {
        VertexShader = PostProcessVS;
        PixelShader  = UpdateHistoryPS;
        RenderTarget = ChromaHistoryTex;
    }
    pass Passthrough
    {
        VertexShader = PostProcessVS;
        PixelShader  = PassthroughPS;
    }
}
