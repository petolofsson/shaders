// alpha_zone_contrast.fx — Spatial 4×4 zone contrast with tonal weighting (game-agnostic)
//
// CORRECTIVE STAGE — game-agnostic.
//
// CONCEPTUAL BASIS:
//   The screen is divided into a 4×4 grid of 16 zones. Each zone builds its own
//   32-bin luma histogram from a 10×10 sample of the low-frequency scene (1/8 res).
//   The median (p50) of each zone is located — the zone's local Zone V equivalent.
//   A smoothstep S-curve is applied to each pixel's luma, anchored at the median
//   of its zone. The 4×4 zone medians are stored in a texture sampled with LINEAR
//   filtering, giving smooth bilinear transitions at every zone boundary.
//
//     - A bright sky zone adapts independently from a dark ground zone.
//     - Zone boundaries blend seamlessly — no visible grid edges.
//     - Tonal weighting: midtones receive full strength, extreme shadows and
//       highlights taper toward zero — prevents crushing blacks or clipping whites.
//
// ARCHITECTURAL NOTE — do not change this approach without approval:
//   The 4×4 spatial zone grid with bilinear blending is the deliberate design.
//   It was chosen over a single global median because local zone medians let
//   bright sky and dark ground adapt independently. The tonal weighting
//   (parabola peaking at midtone) is what prevents shadows from being crushed.
//   Any significant change to grid size, sampling, or S-curve anchor requires
//   explicit approval before implementation.
//
// Four passes:
//   Pass 1 — ComputeLowFreq: downsample CorrectiveSamp to 1/8 res (RGBA = R,G,B,luma)
//   Pass 2 — ComputeZoneHistogram: 32-bin luma histogram per zone (32×16 texture)
//   Pass 3 — BuildZoneLevels: CDF walk per zone → smoothed median → 4×4 ZoneLevelsTex
//   Pass 4 — ApplyContrast: bilinear zone median + tonal weight → luma S-curve

#define CURVE_STRENGTH  15      // 0–100; S-curve blend strength.
#define LERP_SPEED      0.01    // % per second, frametime-normalized
#define HIST_LERP       5.0     // % per second, frametime-normalized

uniform float frametime < source = "frametime"; >;

// ─── Low-frequency RGB+luma — 1/8 resolution ───────────────────────────────
texture2D LowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; MipLevels = 1; };
sampler2D LowFreqSamp
{
    Texture   = LowFreqTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// ─── 32-bin luma histogram, 16 rows (one per zone) ─────────────────────────
texture2D ZoneHistTex { Width = 32; Height = 16; Format = R16F; MipLevels = 1; };
sampler2D ZoneHistSamp
{
    Texture   = ZoneHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Zone medians — 4×4 R16F, LINEAR sampled for smooth zone blending ───────
texture2D ZoneLevelsTex { Width = 4; Height = 4; Format = R16F; MipLevels = 1; };
sampler2D ZoneLevelsSamp
{
    Texture   = ZoneLevelsTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
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

// ─── Vertex shader ─────────────────────────────────────────────────────────
void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// S-curve anchored at median m: m→m (invariant), full [0,1] range.
float SCurve(float x, float m, float strength)
{
    float t_lo = saturate(x / max(m, 0.001));
    float t_hi = saturate((x - m) / max(1.0 - m, 0.001));
    float s_lo = m * (t_lo * t_lo * (3.0 - 2.0 * t_lo));
    float s_hi = m + (1.0 - m) * (t_hi * t_hi * (3.0 - 2.0 * t_hi));
    float s    = lerp(s_lo, s_hi, step(m, x));
    return lerp(x, s, strength);
}

// ─── Pass 1 — Downsample to low-frequency RGB + luma ───────────────────────
float4 ComputeLowFreqPS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    float2 px = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float3 rgb = 0.0;
    rgb += tex2Dlod(BackBuffer, float4(uv + float2(-1.5, -1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(BackBuffer, float4(uv + float2( 1.5, -1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(BackBuffer, float4(uv + float2(-1.5,  1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(BackBuffer, float4(uv + float2( 1.5,  1.5) * px, 0, 0)).rgb;
    rgb *= 0.25;
    return float4(rgb, Luma(rgb));
}

// ─── Pass 2 — Build per-zone luma histogram from LowFreqTex ────────────────
// ZoneHistTex rows 0-15 = zones (row-major, 4 cols × 4 rows).
// Each pixel (b, zone) = fraction of 10×10 samples in that bin for that zone.

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
        float2 suv = float2(u_lo + (sx + 0.5) / 10.0 * 0.25,
                            v_lo + (sy + 0.5) / 10.0 * 0.25);
        float luma = tex2Dlod(LowFreqSamp, float4(suv, 0, 0)).a;
        count += (luma >= bucket_lo && luma < bucket_hi) ? 1.0 : 0.0;
    }

    float v    = count / 100.0;
    float prev = tex2Dlod(ZoneHistSamp,
        float4((float(b) + 0.5) / 32.0, (float(zone) + 0.5) / 16.0, 0, 0)).r;
    float h    = lerp(prev, v, (HIST_LERP / 100.0) * (frametime / 10.0));
    return float4(h, h, h, 1.0);
}

// ─── Pass 3 — Walk per-zone CDF for median → 4×4 ZoneLevelsTex ─────────────
float4 BuildZoneLevelsPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    int zone_x = int(pos.x);
    int zone_y = int(pos.y);
    int zone   = zone_y * 4 + zone_x;

    float2 prev_uv = float2((float(zone_x) + 0.5) / 4.0, (float(zone_y) + 0.5) / 4.0);
    float4 prev    = tex2Dlod(ZoneLevelsSamp, float4(prev_uv, 0, 0));
    float  speed   = (prev.r < 0.001) ? 1.0 : (LERP_SPEED / 100.0) * (frametime / 10.0);

    float cumulative = 0.0;
    float median     = 0.5;
    float locked     = 0.0;

    [loop] for (int b = 0; b < 32; b++)
    {
        float bv   = float(b) / 32.0;
        float frac = tex2Dlod(ZoneHistSamp,
            float4((float(b) + 0.5) / 32.0, (float(zone) + 0.5) / 16.0, 0, 0)).r;
        cumulative += frac;

        float at50 = step(0.50, cumulative) * (1.0 - locked);
        median     = lerp(median, bv, at50);
        locked     = saturate(locked + at50);
    }

    return float4(lerp(prev.r, median, speed), 0.0, 0.0, 1.0);
}

// ─── Pass 4 — Apply contrast ────────────────────────────────────────────────
float4 ApplyContrastPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);

    if (pos.y < 1.0) return col;  // data highway — must not be modified

    float luma = Luma(col.rgb);

    float zone_median = tex2D(ZoneLevelsSamp, uv).r;

    // Tonal weighting: peaks at midtone (0.5), tapers to zero at black/white.
    float t        = luma * 2.0 - 1.0;
    float tonal_w  = 1.0 - t * t;
    float strength = (CURVE_STRENGTH / 100.0) * tonal_w;

    float new_luma = SCurve(luma, zone_median, strength);
    float scale    = new_luma / max(luma, 0.001);

    return float4(col.rgb * scale, col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────
technique AlphaZoneContrast
{
    pass ComputeLowFreq
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeLowFreqPS;
        RenderTarget = LowFreqTex;
    }
    pass ComputeZoneHistogram
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeZoneHistogramPS;
        RenderTarget = ZoneHistTex;
    }
    pass BuildZoneLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildZoneLevelsPS;
        RenderTarget = ZoneLevelsTex;
    }
    pass ApplyContrast
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyContrastPS;
    }
}
