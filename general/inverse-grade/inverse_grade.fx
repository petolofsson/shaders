// inverse_grade.fx — Adaptive blind inverse tone mapping pre-grade
//
// Reads the scene's luminance histogram (LumHistTex, written by frame_analysis)
// and applies an adaptive inverse S-curve anchored at the scene median (p50).
// Expands shadows down and highlights up — opposite of the game's baked S-curve.
// Shoulder compression is detected from p75 and corrected with a boost above p75.
// Output is a flatter, log-like signal for re-grading by corrective_render_chain.
//
// Pass 1  InverseGrade   BackBuffer → BackBuffer
//
// Shared texture contract:
//   LumHistTex { Width=64; Height=1; Format=R32F } — declared in frame_analysis (WRITER)

#define IG_MAX  0.35  // maximum inverse-grade strength

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

texture2D PercTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D PercSamp
{
    Texture   = PercTex;
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

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// Inverse S-curve anchored at pivot. shoulder_boost increases expansion
// above p75 when the game has compressed the highlight shoulder.
float InverseS(float x, float pivot, float strength, float p75, float shoulder_boost)
{
    float d       = x - pivot;
    float lo_range = max(pivot, 0.001);
    float hi_range = max(1.0 - pivot, 0.001);
    float norm     = (d < 0.0) ? saturate(-d / lo_range) : saturate(d / hi_range);

    float above_p75   = (d > 0.0) ? saturate((x - p75) / max(1.0 - p75, 0.001)) : 0.0;
    float eff_strength = strength * (1.0 + shoulder_boost * above_p75 * 1.5);

    float expanded  = pow(norm, 1.0 / (1.0 + eff_strength));
    float out_range = (d < 0.0) ? lo_range : hi_range;

    return pivot + (d < 0.0 ? -1.0 : 1.0) * expanded * out_range;
}

// ─── Pass 1 — Inverse grade ────────────────────────────────────────────────

float4 InverseGradePS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;

    // Percentile fetch — p25/p50/p75/iqr from shared 1×1 cache (written by frame_analysis)
    float4 perc    = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));
    float p25      = perc.r, p50 = perc.g, p75 = perc.b, iqr = perc.a;
    float strength = saturate(smoothstep(0.15, 0.50, iqr) * IG_MAX);

    // Shoulder boost — heavy game compression above p75 gets extra expansion
    float shoulder_gap   = max(1.0 - p75, 0.001);
    float midtone_gap    = max(p75 - p50, 0.001);
    float shoulder_boost = saturate(1.0 - shoulder_gap / midtone_gap);

    // Channel steering — preserve highlight gradient near 8-bit clip boundary
    float3 rgb      = col.rgb;
    float  ch_max   = max(rgb.r, max(rgb.g, rgb.b));
    float  steer    = smoothstep(0.90, 1.0, ch_max);
    float  lum_steer = Luma(rgb);
    rgb = lerp(rgb, float3(lum_steer, lum_steer, lum_steer), steer * 0.4);

    // Triangle dither — breaks 8-bit banding during shadow expansion
    float h      = frac(sin(dot(pos.xy, float2(127.1, 311.7))) * 43758.5453);
    float dither = (h < 0.5 ? sqrt(2.0 * h) - 1.0 : 1.0 - sqrt(2.0 * (1.0 - h))) / 255.0;
    rgb = saturate(rgb + dither);

    // Apply inverse S on luma, scale RGB to preserve hue
    float luma_in  = Luma(rgb);
    float luma_out = InverseS(luma_in, p50, strength, p75, shoulder_boost);
    float scale    = (luma_in > 0.001) ? luma_out / luma_in : 1.0;
    float3 rgb_out = lerp(col.rgb, rgb * scale, strength);

    return float4(rgb_out, col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique InverseGrade
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = InverseGradePS;
    }
}
