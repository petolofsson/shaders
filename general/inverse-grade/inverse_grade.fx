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

#include "creative_values.fx"
#define IG_MAX  (INVERSE_STRENGTH / 100.0)

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

float3 LinearRGB_to_OKLab(float3 c)
{
    float l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
    float m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
    float s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
    float l_ = pow(max(l, 0.0), 1.0/3.0);
    float m_ = pow(max(m, 0.0), 1.0/3.0);
    float s_ = pow(max(s, 0.0), 1.0/3.0);
    return float3(
        0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_,
        1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_,
        0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_
    );
}

float3 OKLab_to_LinearRGB(float3 lab)
{
    float l_ = lab.x + 0.3963377774*lab.y + 0.2158037573*lab.z;
    float m_ = lab.x - 0.1055613458*lab.y - 0.0638541728*lab.z;
    float s_ = lab.x - 0.0894841775*lab.y - 1.2914855480*lab.z;
    float l  = l_*l_*l_;
    float m  = m_*m_*m_;
    float s  = s_*s_*s_;
    return float3(
        +4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
        -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
        -0.0041960863*l - 0.7034186147*m + 1.7076147010*s
    );
}

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

    // Triangle dither — sine-free hash avoids NaN on large pixel coords (SPIR-V OpSin UB)
    float2 hpos  = frac(pos.xy * float2(0.1031, 0.1030));
    hpos        += dot(hpos, hpos.yx + 33.33);
    float h      = frac((hpos.x + hpos.y) * hpos.x);
    float dither = (h < 0.5 ? sqrt(2.0 * h) - 1.0 : 1.0 - sqrt(2.0 * (1.0 - h))) / 255.0;
    rgb = saturate(rgb + dither);

    // OKLab inverse grade — expand L, recover chroma proportionally
    float3 lab   = LinearRGB_to_OKLab(rgb);
    float  L_in  = lab.x;
    float  L_out = InverseS(L_in, p50, strength, p75, shoulder_boost);
    float  expansion = L_out / max(L_in, 0.001);
    lab.x   = L_out;
    lab.yz *= lerp(1.0, expansion, 0.5);

    float3 rgb_out = lerp(col.rgb, max(OKLab_to_LinearRGB(lab), 0.0), strength);

    // Debug indicator — teal (slot 1)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 106) && pos.x < float(BUFFER_WIDTH - 94))
        return float4(0.0, 0.85, 0.75, 1.0);

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
