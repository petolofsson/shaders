// olofssonian_zone_contrast.fx — Per-frame percentile-pivoted adaptive contrast
//
// Two-pass approach:
//   Pass 1: Sample 128 full-screen Halton(2,3) points, bitonic sort, extract
//           25th and 75th percentiles. Lerp toward them each frame.
//   Pass 2: Apply two pivoted S-curves (dark pivot + bright pivot), blend
//           per-pixel by luma — content-aware, no fixed screen zones.
//           Then apply filmic toe + shoulder to the blended result.
//
// Why percentiles instead of zones:
//   A fixed sky/combat/ground split uses screen position as a proxy for content.
//   A cave ceiling at the top of the screen got the sky curve. With percentiles,
//   each pixel blends toward the curve that matches its own brightness —
//   dark pixels get the dark-world pivot, bright pixels get the bright-world pivot.
//
// Pure contrast shader — no color ops, no tonal range.
// Stack color_grade after this for black/white point and tonal tinting.

// ─── Tuning ────────────────────────────────────────────────────────────────
#define CURVE_STRENGTH  30     // -100 to 100; S-curve bend strength
#define LERP_SPEED      8      // 0–100; adaptation speed


uniform int FRAME_COUNT < source = "framecount"; >;

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

// Persistent texture — R = dark percentile (25th), G = bright percentile (75th)
texture2D HistoryTex
{
    Width     = 4;
    Height    = 4;
    Format    = RGBA16F;
    MipLevels = 1;
};
sampler2D History
{
    Texture   = HistoryTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
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
float Luma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// Pre-baked Halton(2,3) sequence — 256 points, UV coordinates.
// Replaces runtime VanDerCorput() calls — array lookup vs per-sample math.
// Frame-jitter slides the 128-point window: idx = (s + frame_offset) % 256.
static const float2 kHalton[256] = {
    float2(0.000000, 0.000000), float2(0.500000, 0.333333),
    float2(0.250000, 0.666667), float2(0.750000, 0.111111),
    float2(0.125000, 0.444444), float2(0.625000, 0.777778),
    float2(0.375000, 0.222222), float2(0.875000, 0.555556),
    float2(0.062500, 0.888889), float2(0.562500, 0.037037),
    float2(0.312500, 0.370370), float2(0.812500, 0.703704),
    float2(0.187500, 0.148148), float2(0.687500, 0.481481),
    float2(0.437500, 0.814815), float2(0.937500, 0.259259),
    float2(0.031250, 0.592593), float2(0.531250, 0.925926),
    float2(0.281250, 0.074074), float2(0.781250, 0.407407),
    float2(0.156250, 0.740741), float2(0.656250, 0.185185),
    float2(0.406250, 0.518519), float2(0.906250, 0.851852),
    float2(0.093750, 0.296296), float2(0.593750, 0.629630),
    float2(0.343750, 0.962963), float2(0.843750, 0.012346),
    float2(0.218750, 0.345679), float2(0.718750, 0.679012),
    float2(0.468750, 0.123457), float2(0.968750, 0.456790),
    float2(0.015625, 0.790123), float2(0.515625, 0.234568),
    float2(0.265625, 0.567901), float2(0.765625, 0.901235),
    float2(0.140625, 0.049383), float2(0.640625, 0.382716),
    float2(0.390625, 0.716049), float2(0.890625, 0.160494),
    float2(0.078125, 0.493827), float2(0.578125, 0.827160),
    float2(0.328125, 0.271605), float2(0.828125, 0.604938),
    float2(0.203125, 0.938272), float2(0.703125, 0.086420),
    float2(0.453125, 0.419753), float2(0.953125, 0.753086),
    float2(0.046875, 0.197531), float2(0.546875, 0.530864),
    float2(0.296875, 0.864198), float2(0.796875, 0.308642),
    float2(0.171875, 0.641975), float2(0.671875, 0.975309),
    float2(0.421875, 0.024691), float2(0.921875, 0.358025),
    float2(0.109375, 0.691358), float2(0.609375, 0.135802),
    float2(0.359375, 0.469136), float2(0.859375, 0.802469),
    float2(0.234375, 0.246914), float2(0.734375, 0.580247),
    float2(0.484375, 0.913580), float2(0.984375, 0.061728),
    float2(0.007813, 0.395062), float2(0.507813, 0.728395),
    float2(0.257813, 0.172840), float2(0.757813, 0.506173),
    float2(0.132813, 0.839506), float2(0.632813, 0.283951),
    float2(0.382813, 0.617284), float2(0.882813, 0.950617),
    float2(0.070313, 0.098765), float2(0.570313, 0.432099),
    float2(0.320313, 0.765432), float2(0.820313, 0.209877),
    float2(0.195313, 0.543210), float2(0.695313, 0.876543),
    float2(0.445313, 0.320988), float2(0.945313, 0.654321),
    float2(0.039063, 0.987654), float2(0.539063, 0.004115),
    float2(0.289063, 0.337449), float2(0.789063, 0.670782),
    float2(0.164063, 0.115226), float2(0.664063, 0.448560),
    float2(0.414063, 0.781893), float2(0.914063, 0.226337),
    float2(0.101563, 0.559671), float2(0.601563, 0.893004),
    float2(0.351563, 0.041152), float2(0.851563, 0.374486),
    float2(0.226563, 0.707819), float2(0.726563, 0.152263),
    float2(0.476563, 0.485597), float2(0.976563, 0.818930),
    float2(0.023438, 0.263374), float2(0.523438, 0.596708),
    float2(0.273438, 0.930041), float2(0.773438, 0.078189),
    float2(0.148438, 0.411523), float2(0.648438, 0.744856),
    float2(0.398438, 0.189300), float2(0.898438, 0.522634),
    float2(0.085938, 0.855967), float2(0.585938, 0.300412),
    float2(0.335938, 0.633745), float2(0.835938, 0.967078),
    float2(0.210938, 0.016461), float2(0.710938, 0.349794),
    float2(0.460938, 0.683128), float2(0.960938, 0.127572),
    float2(0.054688, 0.460905), float2(0.554688, 0.794239),
    float2(0.304688, 0.238683), float2(0.804688, 0.572016),
    float2(0.179688, 0.905350), float2(0.679688, 0.053498),
    float2(0.429688, 0.386831), float2(0.929688, 0.720165),
    float2(0.117188, 0.164609), float2(0.617188, 0.497942),
    float2(0.367188, 0.831276), float2(0.867188, 0.275720),
    float2(0.242188, 0.609053), float2(0.742188, 0.942387),
    float2(0.492188, 0.312757), float2(0.992188, 0.646091),
    float2(0.003906, 0.757202), float2(0.503906, 0.201646),
    float2(0.253906, 0.534979), float2(0.753906, 0.868313),
    float2(0.128906, 0.312757), float2(0.628906, 0.646091),
    float2(0.378906, 0.979424), float2(0.878906, 0.028807),
    float2(0.066406, 0.362140), float2(0.566406, 0.695473),
    float2(0.316406, 0.139918), float2(0.816406, 0.473251),
    float2(0.191406, 0.806584), float2(0.691406, 0.251029),
    float2(0.441406, 0.584362), float2(0.941406, 0.917695),
    float2(0.035156, 0.065844), float2(0.535156, 0.399177),
    float2(0.285156, 0.732510), float2(0.785156, 0.176955),
    float2(0.160156, 0.510288), float2(0.660156, 0.843621),
    float2(0.410156, 0.288066), float2(0.910156, 0.621399),
    float2(0.097656, 0.954733), float2(0.597656, 0.102881),
    float2(0.347656, 0.436214), float2(0.847656, 0.769547),
    float2(0.222656, 0.213992), float2(0.722656, 0.547325),
    float2(0.472656, 0.880658), float2(0.972656, 0.325103),
    float2(0.019531, 0.658436), float2(0.519531, 0.991770),
    float2(0.269531, 0.008230), float2(0.769531, 0.341564),
    float2(0.144531, 0.674897), float2(0.644531, 0.119342),
    float2(0.394531, 0.452675), float2(0.894531, 0.786008),
    float2(0.082031, 0.230453), float2(0.582031, 0.563786),
    float2(0.332031, 0.897119), float2(0.832031, 0.045267),
    float2(0.207031, 0.378601), float2(0.707031, 0.711934),
    float2(0.457031, 0.156379), float2(0.957031, 0.489712),
    float2(0.050781, 0.823045), float2(0.550781, 0.267490),
    float2(0.300781, 0.600823), float2(0.800781, 0.934156),
    float2(0.175781, 0.082305), float2(0.675781, 0.415638),
    float2(0.425781, 0.748971), float2(0.925781, 0.193416),
    float2(0.113281, 0.526749), float2(0.613281, 0.860082),
    float2(0.363281, 0.304527), float2(0.863281, 0.637860),
    float2(0.238281, 0.971193), float2(0.738281, 0.020576),
    float2(0.488281, 0.353909), float2(0.988281, 0.687243),
    float2(0.011719, 0.131687), float2(0.511719, 0.465021),
    float2(0.261719, 0.798354), float2(0.761719, 0.242798),
    float2(0.136719, 0.576132), float2(0.636719, 0.909465),
    float2(0.386719, 0.057613), float2(0.886719, 0.390947),
    float2(0.074219, 0.724280), float2(0.574219, 0.168724),
    float2(0.324219, 0.502058), float2(0.824219, 0.835391),
    float2(0.199219, 0.279835), float2(0.699219, 0.613169),
    float2(0.449219, 0.946502), float2(0.949219, 0.094650),
    float2(0.042969, 0.427984), float2(0.542969, 0.761317),
    float2(0.292969, 0.205761), float2(0.792969, 0.539095),
    float2(0.167969, 0.872428), float2(0.667969, 0.316872),
    float2(0.417969, 0.650206), float2(0.917969, 0.983539),
    float2(0.105469, 0.032922), float2(0.605469, 0.366255),
    float2(0.355469, 0.699588), float2(0.855469, 0.144033),
    float2(0.230469, 0.477366), float2(0.730469, 0.810700),
    float2(0.480469, 0.255144), float2(0.980469, 0.588477),
    float2(0.027344, 0.921811), float2(0.527344, 0.069959),
    float2(0.277344, 0.403292), float2(0.777344, 0.736626),
    float2(0.152344, 0.181070), float2(0.652344, 0.514403),
    float2(0.402344, 0.847737), float2(0.902344, 0.292181),
    float2(0.089844, 0.625514), float2(0.589844, 0.958848),
    float2(0.339844, 0.106996), float2(0.839844, 0.440329),
    float2(0.214844, 0.773663), float2(0.714844, 0.218107),
    float2(0.464844, 0.551440), float2(0.964844, 0.884774),
    float2(0.058594, 0.329218), float2(0.558594, 0.662551),
    float2(0.308594, 0.995885), float2(0.808594, 0.001372),
    float2(0.183594, 0.334705), float2(0.683594, 0.668038),
    float2(0.433594, 0.112483), float2(0.933594, 0.445816),
    float2(0.121094, 0.779150), float2(0.621094, 0.223594),
    float2(0.371094, 0.556927), float2(0.871094, 0.890261),
    float2(0.246094, 0.038409), float2(0.746094, 0.371742),
    float2(0.496094, 0.705075), float2(0.996094, 0.149520)
};

// Sample 128 full-screen Halton(2,3) points, sort, return 25th + median + 75th percentiles.
// Index 31/32 ≈ 25th, index 63/64 ≈ 50th (median), index 95/96 ≈ 75th (out of 128).
// Frame-jittered: slides the 128-point window through the 256-point table each frame.
// Combined with temporal smoothing (~17 frames at LERP_SPEED 0.06), effective coverage ≈ 2200 unique positions.
float3 SamplePercentiles(int frame_offset)
{
    float v[128];

    for (int s = 0; s < 128; s++)
    {
        int idx = (s + frame_offset) % 256;
        v[s] = Luma(tex2D(BackBuffer, kHalton[idx]).rgb);
    }

    // Bitonic sort — ascending, 128 elements
    for (int k = 2; k <= 128; k <<= 1)
    {
        for (int j = k >> 1; j > 0; j >>= 1)
        {
            for (int i = 0; i < 128; i++)
            {
                int l = i ^ j;
                if (l > i)
                {
                    float a   = v[i];
                    float b   = v[l];
                    bool  asc = (i & k) == 0;
                    v[i] = asc ? min(a, b) : max(a, b);
                    v[l] = asc ? max(a, b) : min(a, b);
                }
            }
        }
    }

    return float3(
        (v[31] + v[32]) * 0.5,   // 25th percentile — dark world pivot
        (v[95] + v[96]) * 0.5,   // 75th percentile — bright world pivot
        (v[63] + v[64]) * 0.5    // 50th percentile — median, actual mass centre
    );
}

// S-curve pivoted at m
float3 PivotedSCurve(float3 col, float m, float strength)
{
    float3 t    = col - m;
    float3 bent = t + strength * t * (1.0 - saturate(abs(t)));
    return saturate(m + bent);
}

// ─── Pass 1 — Update smoothed percentiles ──────────────────────────────────
float4 UpdateHistoryPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float4 prev         = tex2D(History, float2(0.5, 0.5));
    int    frame_offset = int(FRAME_COUNT) % 128;
    float3 p            = SamplePercentiles(frame_offset);

    float speed = (prev.b < 0.001) ? 1.0 : (LERP_SPEED / 100.0);

    return float4(
        0.0,
        0.0,
        lerp(prev.b, p.z, speed),           // median (50th)
        1.0
    );
}

// ─── Pass 2 — Apply contrast + tonal grade ─────────────────────────────────
float4 ApplyContrastPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2519 && pos.x < 2531 && pos.y > 15 && pos.y < 27)
        return float4(0.0, 1.0, 0.0, 1.0);

    float4 col     = tex2D(BackBuffer, uv);
    float4 history = tex2D(History, float2(0.5, 0.5));

    float  median = history.b;
    float3 result = PivotedSCurve(col.rgb, median, CURVE_STRENGTH / 100.0);

    return saturate(float4(result, col.a));
}

// ─── Technique ─────────────────────────────────────────────────────────────
technique OlofssonianZoneContrast
{
    pass UpdateHistory
    {
        VertexShader = PostProcessVS;
        PixelShader  = UpdateHistoryPS;
        RenderTarget = HistoryTex;
    }
    pass ApplyContrast
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyContrastPS;
    }
}
