// corrective_render_chain.fx — Technical correction + display transform (game-agnostic)
//
// All passes share CorrectiveBuf (RGBA16F) — no UNORM clamping between stages.
//
//   Pass 1  ComputeLowFreq      BackBuffer    → LowFreqTex       1/8 res downsample
//   Pass 2  IlluminantEstimate  LowFreqTex    → IlluminantTex    Shades of Grey (Minkowski p=6) per 4×4 zone
//   Pass 3  ApplyAdaptation     BackBuffer    → CorrectiveBuf    CAT16 illuminant correction
//   Pass 4  CopyBufToSrc        CorrectiveBuf → CorrectiveSrcTex
//   Pass 5  OutputTransform     CorrectiveSrc → BackBuffer       OKLab Hermite S-curve + scene-adaptive grey

#include "creative_values.fx"

#define YOUVAN_LERP_SPEED    4.3
#define MINKOWSKI_P          6.0

#define OT_SAT_MAX         85
#define OT_SAT_BLEND       15

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

texture2D CorrectiveBuf { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 1; };
sampler2D CorrectiveSamp
{
    Texture   = CorrectiveBuf;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D CorrectiveSrcTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 1; };
sampler2D CorrectiveSrc
{
    Texture   = CorrectiveSrcTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D LowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; MipLevels = 1; };
sampler2D LowFreqSamp
{
    Texture   = LowFreqTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D IlluminantTex { Width = 4; Height = 4; Format = RGBA16F; MipLevels = 1; };
sampler2D IlluminantSamp
{
    Texture   = IlluminantTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D LumHistTex { Width = 64; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumHistSamp
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Vertex shader ───────────────────────────────────────────────────────────

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ─── CAT16 matrices ───────────────────────────────────────────────────────────

static const float3x3 M_CAT16 = float3x3(
     0.401288,  0.650173, -0.051461,
    -0.250268,  1.204414,  0.045854,
    -0.002079,  0.048952,  0.953127
);

static const float3x3 M_CAT16_inv = float3x3(
     1.862068, -1.011255,  0.149187,
     0.387526,  0.621447, -0.008974,
    -0.015842, -0.034123,  1.049964
);

// ─── OKLab helpers ───────────────────────────────────────────────────────────

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

// Hermite S-curve anchored at scene-adaptive grey point — display-referred [0,1] → [0,1]
float HermiteContrast(float L, float grey, float strength)
{
    float bias     = 0.5 - grey;
    float centered = saturate(L + bias);
    float curve    = smoothstep(0.0, 1.0, centered);
    return saturate(lerp(centered, curve, strength) - bias);
}

// ═══ Pixel shaders ════════════════════════════════════════════════════════════

// Pass 4 — Snapshot CorrectiveBuf → CorrectiveSrcTex
float4 CopyBufToSrcPS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    return tex2D(CorrectiveSamp, uv);
}

// Pass 1 — 1/8 res downsample for illuminant estimation
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

// Pass 3 — Shades of Grey (Minkowski p=6) illuminant estimator: per 4×4 spatial zone, EMA smoothing
float4 IlluminantEstimatePS(float4 pos : SV_Position,
                            float2 uv  : TEXCOORD0) : SV_Target
{
    int zone_x = int(pos.x);
    int zone_y = int(pos.y);
    if (zone_x >= 4 || zone_y >= 4) return float4(0, 0, 0, 0);

    float u_lo = float(zone_x) / 4.0;
    float v_lo = float(zone_y) / 4.0;

    float3 acc = 0.0;

    [loop] for (int sy = 0; sy < 10; sy++)
    [loop] for (int sx = 0; sx < 10; sx++)
    {
        float2 suv = float2(u_lo + (sx + 0.5) / 40.0,
                            v_lo + (sy + 0.5) / 40.0);
        float3 rgb = tex2Dlod(LowFreqSamp, float4(suv, 0, 0)).rgb;
        acc += pow(max(rgb, 0.0), MINKOWSKI_P);
    }

    float3 illum   = pow(acc / 100.0, 1.0 / MINKOWSKI_P);
    float2 zone_uv = float2((float(zone_x) + 0.5) / 4.0, (float(zone_y) + 0.5) / 4.0);
    float4 prev    = tex2Dlod(IlluminantSamp, float4(zone_uv, 0, 0));
    float  speed   = (prev.a < 0.001) ? 1.0 : (YOUVAN_LERP_SPEED / 100.0) * (frametime / 10.0);

    return float4(lerp(prev.rgb, illum, speed), lerp(prev.a, 1.0, speed));
}

// Pass 5 — Passthrough (YOUVAN disabled pending inverse-grade rewrite)
float4 ApplyAdaptationPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    return tex2D(BackBuffer, uv);
}

// Pass 7 — Output transform: scene-adaptive OKLab tone curve → BackBuffer
float4 OutputTransformPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col    = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;

    float3 rgb_out    = col.rgb;

    // Tonal IQR from pre-correction histogram — wide range → less curve, flat → more
    float lum_cumul = 0.0, lum_p25 = 0.25, lum_p75 = 0.75;
    float lum_lock25 = 0.0, lum_lock75 = 0.0;
    [loop] for (int lb = 0; lb < 64; lb++)
    {
        float lum_frac = tex2Dlod(LumHistSamp, float4((float(lb) + 0.5) / 64.0, 0.5, 0, 0)).r;
        lum_cumul += lum_frac;
        float at25 = step(0.25, lum_cumul) * (1.0 - lum_lock25);
        float at75 = step(0.75, lum_cumul) * (1.0 - lum_lock75);
        lum_p25    = lerp(lum_p25, float(lb) / 64.0, at25);
        lum_p75    = lerp(lum_p75, float(lb) / 64.0, at75);
        lum_lock25 = saturate(lum_lock25 + at25);
        lum_lock75 = saturate(lum_lock75 + at75);
    }
    float lum_iqr  = saturate(lum_p75 - lum_p25);
    float hermite_t = (HERMITE_STRENGTH / 100.0) * (1.0 - lum_iqr * 0.5);

    // Gamut compression — only active with tone curve
    float luma_gc = Luma(rgb_out);
    float under   = saturate(-min(rgb_out.r, min(rgb_out.g, rgb_out.b)) * 10.0) * hermite_t;
    rgb_out       = lerp(rgb_out, float3(luma_gc, luma_gc, luma_gc), under);

    float gc_max = max(rgb_out.r, max(rgb_out.g, rgb_out.b));
    float gc_min = min(rgb_out.r, min(rgb_out.g, rgb_out.b));
    float sat_gc = (gc_max > 0.001) ? (gc_max - gc_min) / gc_max : 0.0;
    float excess = max(0.0, sat_gc - OT_SAT_MAX / 100.0) / (1.0 - OT_SAT_MAX / 100.0);
    float gc_amt = excess * excess * (OT_SAT_BLEND / 100.0) * hermite_t;
    rgb_out      = rgb_out + (gc_max - rgb_out) * gc_amt;

    // Scene-adaptive grey point — averaged from IlluminantTex (EMA-smoothed), in OKLab L space
    float grey_linear = 0.0;
    [loop] for (int zy = 0; zy < 4; zy++)
    [loop] for (int zx = 0; zx < 4; zx++)
    {
        float3 illum = tex2Dlod(IlluminantSamp,
            float4((zx + 0.5) / 4.0, (zy + 0.5) / 4.0, 0, 0)).rgb;
        grey_linear += Luma(illum);
    }
    grey_linear = clamp(grey_linear / 16.0, 0.05, 0.55);
    float grey  = RGBtoOKLab(float3(grey_linear, grey_linear, grey_linear)).x;

    // Tone curve on OKLab L + Hunt-effect chroma compensation
    float3 lab_in      = RGBtoOKLab(rgb_out);
    float  L_before    = max(lab_in.x, 0.0);
    float  L_mapped    = HermiteContrast(L_before, grey, hermite_t);
    float  chroma_comp = (L_before > 0.001) ? max(pow(L_mapped / L_before, 0.5), 1.0) : 1.0;
    rgb_out = OKLabtoRGB(float3(L_mapped, lab_in.yz * chroma_comp));

    // Debug indicator — green (slot 2)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 50) && pos.x < float(BUFFER_WIDTH - 38))
        return float4(0.1, 0.90, 0.1, 1.0);
    return saturate(float4(rgb_out, col.a));
}

// ─── Technique ───────────────────────────────────────────────────────────────

technique OlofssonianRenderChain
{
    pass ComputeLowFreq
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeLowFreqPS;
        RenderTarget = LowFreqTex;
    }
    pass IlluminantEstimate
    {
        VertexShader = PostProcessVS;
        PixelShader  = IlluminantEstimatePS;
        RenderTarget = IlluminantTex;
    }
    pass ApplyAdaptation
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyAdaptationPS;
        RenderTarget = CorrectiveBuf;
    }
    pass CopyBufToSrc1
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyBufToSrcPS;
        RenderTarget = CorrectiveSrcTex;
    }
    pass OutputTransform
    {
        VertexShader = PostProcessVS;
        PixelShader  = OutputTransformPS;
    }
}
