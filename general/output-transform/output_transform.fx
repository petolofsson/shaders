// output_transform.fx — Display Rendering Transform (linear → display)
//
// SKELETON — Step 4 of the professional pipeline.
//
// Current: tonal range + gamut compression + re-gamma encode.
// TODO: Replace simple re-gamma with a proper DRT (OpenDRT or ACES RRT+ODT)
//       for better highlight rolloff and more natural tone mapping.
// TODO: Add display target selection (Rec.709 SDR / HDR10).
//
// Receives linear-light RGB from color_grade.
// Outputs gamma-encoded sRGB for display.

#define BLACK_POINT  0.035
#define WHITE_POINT  0.97
#define SAT_MAX      0.85
#define SAT_BLEND    0.15

// ─── Textures ──────────────────────────────────────────────────────────────

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer { Texture = BackBufferTex; };

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

// ─── Pixel shader ──────────────────────────────────────────────────────────

float4 OutputTransformPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2549 && pos.x < 2561 && pos.y > 15 && pos.y < 27)
        return float4(0.45, 0.0, 0.0, 1.0);

    float4 col    = tex2D(BackBuffer, uv);
    float3 result = col.rgb;

    // ── Tonal range ───────────────────────────────────────────────────────────
    result = result * (WHITE_POINT - BLACK_POINT) + BLACK_POINT;

    // ── Gamut compression ─────────────────────────────────────────────────────
    float luma_gc = Luma(result);
    float under   = saturate(-min(result.r, min(result.g, result.b)) * 10.0);
    result        = lerp(result, float3(luma_gc, luma_gc, luma_gc), under);

    float gc_max  = max(result.r, max(result.g, result.b));
    float gc_min  = min(result.r, min(result.g, result.b));
    float sat_gc  = (gc_max > 0.001) ? (gc_max - gc_min) / gc_max : 0.0;
    float excess  = max(0.0, sat_gc - SAT_MAX) / (1.0 - SAT_MAX);
    float gc_amt  = excess * excess * SAT_BLEND;
    result        = result + (gc_max - result) * gc_amt;

    // ── Re-gamma encode — bypassed, input is already gamma-encoded ────────────
    // TODO: re-enable when primary_correction's pow(2.2) de-gamma is active
    // result = pow(max(result, 0.0), 1.0 / 2.2);

    return saturate(float4(result, col.a));
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique OutputTransform
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = OutputTransformPS;
    }
}
