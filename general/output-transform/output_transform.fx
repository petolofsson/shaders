// output_transform.fx — Display Rendering Transform
//
// Per-channel OpenDRT-style tone curve:
//   f(x) = A * x^c / (x^c + K)
//   A and K derived from two constraints:
//     - f(0.18) = 0.18  (scene grey maps to display grey)
//     - f(1.0)  = 1.0   (scene white maps to display white)
//   Result: smooth toe, slight midtone lift, soft highlight shoulder.
//   Per-channel processing means saturated highlights naturally shift
//   toward pastel/white — no hard clip.
//
// Also applies gamut compression for out-of-gamut negatives.

// ─── Tuning ────────────────────────────────────────────────────────────────

#define CONTRAST         1.35   // curve contrast — affects toe and shoulder steepness
#define CHROMA_COMPRESS  0.40   // 0–1; highlight desaturation strength (0 = none)
#define BLACK_POINT      3.5    // 0–100; black floor lift
#define SAT_MAX          85     // 0–100; gamut compression threshold
#define SAT_BLEND        15     // 0–100; gamut compression strength

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

// ─── OKLab color space (Björn Ottosson, 2020) ──────────────────────────────
// Perceptually uniform: L = lightness, a = red-green, b = blue-yellow.
// Chroma compression in OKLab preserves hue; RGB-space compression does not.

float3 RGBtoOKLab(float3 c)
{
    float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    l = pow(max(l, 0.0), 1.0 / 3.0);
    m = pow(max(m, 0.0), 1.0 / 3.0);
    s = pow(max(s, 0.0), 1.0 / 3.0);
    return float3(
         0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
         1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
         0.0259040371 * l + 0.4072426305 * m - 0.4327467890 * s
    );
}

float3 OKLabtoRGB(float3 c)
{
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    l = l * l * l;  m = m * m * m;  s = s * s * s;
    return float3(
        +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    );
}

// ─── OpenDRT tone curve ─────────────────────────────────────────────────────
// Applied per-channel. Constants K and A solved analytically:
//   grey = 0.18, gc = grey^CONTRAST
//   K = gc*(1-grey)/(grey-gc),  A = 1+K

float3 OpenDRT(float3 x)
{
    const float grey = 0.18;
    float gc = pow(grey, CONTRAST);
    float K  = gc * (1.0 - grey) / (grey - gc);
    float A  = 1.0 + K;

    float3 xc = pow(max(x, 0.0), CONTRAST);
    return A * xc / (xc + K);
}

// ─── Pixel shader ──────────────────────────────────────────────────────────

float4 OutputTransformPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2548 && pos.x < 2560 && pos.y > 15 && pos.y < 27)
        return float4(0.45, 0.0, 0.0, 1.0);

    float4 col    = tex2D(BackBuffer, uv);
    float3 result = col.rgb;

    // ── Gamut compression (linear space, before tone curve) ──────────────────
    float luma_gc = Luma(result);
    float under   = saturate(-min(result.r, min(result.g, result.b)) * 10.0);
    result        = lerp(result, float3(luma_gc, luma_gc, luma_gc), under);

    float gc_max  = max(result.r, max(result.g, result.b));
    float gc_min  = min(result.r, min(result.g, result.b));
    float sat_gc  = (gc_max > 0.001) ? (gc_max - gc_min) / gc_max : 0.0;
    float excess  = max(0.0, sat_gc - SAT_MAX / 100.0) / (1.0 - SAT_MAX / 100.0);
    float gc_amt  = excess * excess * (SAT_BLEND / 100.0);
    result        = result + (gc_max - result) * gc_amt;

    // ── Black lift ────────────────────────────────────────────────────────────
    result = result * (1.0 - BLACK_POINT / 100.0) + BLACK_POINT / 100.0;

    // ── OpenDRT per-channel tone curve ────────────────────────────────────────
    result = OpenDRT(result);

    // ── Highlight chroma compression (OKLab) ──────────────────────────────────
    // Compress a/b channels in perceptually uniform space — hue is preserved
    // under rolloff. RGB-space blend-to-grey shifts hue; this does not.
    float3 lab    = RGBtoOKLab(result);
    float hl_gate = smoothstep(0.65, 1.0, lab.x);
    lab.yz       *= (1.0 - hl_gate * CHROMA_COMPRESS);
    result        = OKLabtoRGB(lab);

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
