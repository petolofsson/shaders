// alpha_chroma_lift.fx — Per-hue-band saturation median contrast (game-agnostic)
//
// CORRECTIVE STAGE — game-agnostic.
//
// CONCEPTUAL BASIS:
//   frame_analysis.fx builds a 64-bin saturation histogram for each of 6 hue bands
//   (Red, Yellow, Green, Cyan, Blue, Magenta) from a 32×18 downsample of the scene.
//   The saturation median (p50) of each band is located independently — each hue's
//   own chromatic midpoint. A smoothstep S-curve is applied to each pixel's
//   saturation, anchored at the blended median of the hue bands it falls into:
//
//     - The median saturation maps to itself exactly (invariant midpoint).
//     - Each hue band corrects independently — desaturated sky does not drag down
//       reds and greens that are already healthy.
//     - Hue band weights blend smoothly — no hard hue transitions.
//     - Full [0,1] saturation range — no percentile endpoints, no grey gate.
//
// ENGAGEMENT:
//   Near-grey pixels (saturation < 5%) are passed through unchanged.
//   CURVE_STRENGTH controls the maximum blend toward the S-curve.
//
// ARCHITECTURAL NOTE — do not change this approach without approval:
//   The per-hue-band median S-curve is the deliberate design. It was chosen over
//   whole-screen saturation equalization because each hue band adapts to its own
//   content. The 6-band structure matches frame_analysis.fx exactly and must stay
//   in sync with it. Any significant change to sampling, band layout, or the
//   S-curve anchor requires explicit approval before implementation.
//
// Two passes:
//   Pass 1 — BuildSatLevels: CDF walk per band → smoothed median → 6×1 SatLevelsTex
//   Pass 2 — ApplyChroma: hue-weighted blend of band medians → saturation S-curve

#define CURVE_STRENGTH  15      // 0–100; S-curve blend strength.
#define LERP_SPEED      0.01    // % per second, frametime-normalized
#define BAND_WIDTH      0.15    // hue band half-width — must match frame_analysis.fx

uniform float frametime < source = "frametime"; >;

// ─── Shared saturation histogram from frame_analysis — 64×6 R32F ───────────
// Must match frame_analysis.fx exactly: HIST_BINS=64, 6 hue bands, Format=R32F.
texture2D SatHistTex { Width = 64; Height = 6; Format = R32F; MipLevels = 1; };
sampler2D SatHistSamp
{
    Texture   = SatHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Per-band saturation medians — 6×1 R16F ────────────────────────────────
texture2D SatLevelsTex { Width = 6; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D SatLevelsSamp
{
    Texture   = SatLevelsTex;
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

// ─── Vertex shader ─────────────────────────────────────────────────────────
void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ─── Helpers ───────────────────────────────────────────────────────────────
float3 RGBtoHSV(float3 c)
{
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float  d = q.x - min(q.w, q.y);
    float  e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 HSVtoRGB(float3 c)
{
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

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

float HueBandWeight(float hue, float center)
{
    float d = abs(hue - center);
    d = min(d, 1.0 - d);
    return saturate(1.0 - d / BAND_WIDTH);
}

static const float kBandCenters[6] = {
      0.0 / 360.0,   // Red
     60.0 / 360.0,   // Yellow
    120.0 / 360.0,   // Green
    180.0 / 360.0,   // Cyan
    240.0 / 360.0,   // Blue
    300.0 / 360.0    // Magenta
};

// ─── Pass 1 — Walk per-band CDF for saturation median ──────────────────────
// Reads SatHistTex (from frame_analysis). Each output pixel = one band's median.

float4 BuildSatLevelsPS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    int   band  = int(pos.x);
    float row_v = (float(band) + 0.5) / 6.0;

    float4 prev  = tex2Dlod(SatLevelsSamp, float4((float(band) + 0.5) / 6.0, 0.5, 0, 0));
    float  speed = (prev.r < 0.001) ? 1.0 : (LERP_SPEED / 100.0) * (frametime / 10.0);

    float cumulative = 0.0;
    float median     = 0.5;
    float locked     = 0.0;

    [loop] for (int b = 0; b < 64; b++)
    {
        float bv   = float(b) / 64.0;
        float frac = tex2Dlod(SatHistSamp,
            float4((float(b) + 0.5) / 64.0, row_v, 0, 0)).r;
        cumulative += frac;

        float at50 = step(0.50, cumulative) * (1.0 - locked);
        median     = lerp(median, bv, at50);
        locked     = saturate(locked + at50);
    }

    return float4(lerp(prev.r, median, speed), 0.0, 0.0, 1.0);
}

// ─── Pass 2 — Apply chroma ──────────────────────────────────────────────────
float4 ApplyChromaPS(float4 pos : SV_Position,
                     float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);

    if (pos.y < 1.0) return col;  // data highway — must not be modified

    float3 hsv = RGBtoHSV(col.rgb);

    float blended_median = 0.0;
    float total_w        = 0.0;

    [loop] for (int band = 0; band < 6; band++)
    {
        float w = HueBandWeight(hsv.x, kBandCenters[band]);
        float m = tex2Dlod(SatLevelsSamp, float4((float(band) + 0.5) / 6.0, 0.5, 0, 0)).r;
        blended_median += m * w;
        total_w        += w;
    }

    blended_median = (total_w > 0.001) ? blended_median / total_w : 0.5;

    float new_sat = SCurve(hsv.y, blended_median, CURVE_STRENGTH / 100.0);
    float3 result = HSVtoRGB(float3(hsv.x, new_sat, hsv.z));

    return float4(result, col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────
technique AlphaChromaLift
{
    pass BuildSatLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildSatLevelsPS;
        RenderTarget = SatLevelsTex;
    }
    pass ApplyChroma
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyChromaPS;
    }
}
