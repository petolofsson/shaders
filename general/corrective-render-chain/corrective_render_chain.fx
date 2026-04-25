// corrective_render_chain.fx — Technical correction + display transform (game-agnostic)
//
// All passes share CorrectiveBuf (RGBA16F) — no UNORM clamping between stages.
//
//   Pass 1  WhiteBalance       BackBuffer    → CorrectiveBuf    WB_R/G/B only
//   Pass 2  ComputeLowFreq     CorrectiveBuf → LowFreqTex       1/8 res downsample
//   Pass 3  IlluminantEstimate LowFreqTex    → IlluminantTex    Shades of Grey (Minkowski p=6) per 4×4 zone
//   Pass 4  CopyBufToSrc       CorrectiveBuf → CorrectiveSrcTex
//   Pass 5  ApplyAdaptation    CorrectiveSrc → CorrectiveBuf    CAT16 illuminant correction
//   Pass 6  CopyBufToSrc       CorrectiveBuf → CorrectiveSrcTex
//   Pass 7  OutputTransform    CorrectiveSrc → BackBuffer       OKLab tone curve + scene-adaptive grey

#include "creative_values.fx"

#define WB_R  100
#define WB_G  100
#define WB_B  100

#define YOUVAN_LERP_SPEED    4.3
#define MINKOWSKI_P          6.0

#define OT_CHROMA_COMPRESS 0.0
#define OT_BLACK_POINT     0
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

// Pass 1 — White balance
float4 WhiteBalancePS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;
    float3 c = col.rgb * float3(WB_R / 100.0, WB_G / 100.0, WB_B / 100.0);
    return float4(c, col.a);
}

// Passes 4, 6 — Snapshot CorrectiveBuf → CorrectiveSrcTex
float4 CopyBufToSrcPS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    return tex2D(CorrectiveSamp, uv);
}

// Pass 2 — 1/8 res downsample for illuminant estimation
float4 ComputeLowFreqPS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    float2 px = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float3 rgb = 0.0;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2(-1.5, -1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2( 1.5, -1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2(-1.5,  1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2( 1.5,  1.5) * px, 0, 0)).rgb;
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

// Pass 5 — CAT16 chromatic adaptation toward neutral grey
float4 ApplyAdaptationPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;

    float3 illuminant = tex2D(IlluminantSamp, uv).rgb;
    float  grey       = Luma(illuminant);

    float3 lms_illum = mul(M_CAT16, illuminant);
    float3 lms_pixel = mul(M_CAT16, col.rgb);
    float3 scale     = float3(grey, grey, grey) / max(abs(lms_illum), 0.001);
    scale            = clamp(scale, 0.1, 10.0);
    float3 adapted   = mul(M_CAT16_inv, lms_pixel * scale);

    float3 result = lerp(col.rgb, adapted, YOUVAN_STRENGTH / 100.0);
    return float4(result, col.a);
}

// Pass 7 — Output transform: scene-adaptive OKLab tone curve → BackBuffer
float4 OutputTransformPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col    = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;

    float3 result    = col.rgb;
    float  opendrt_t = OPENDRT_STRENGTH / 100.0;

    // Gamut compression — only active with tone curve
    float luma_gc = Luma(result);
    float under   = saturate(-min(result.r, min(result.g, result.b)) * 10.0) * opendrt_t;
    result        = lerp(result, float3(luma_gc, luma_gc, luma_gc), under);

    float gc_max = max(result.r, max(result.g, result.b));
    float gc_min = min(result.r, min(result.g, result.b));
    float sat_gc = (gc_max > 0.001) ? (gc_max - gc_min) / gc_max : 0.0;
    float excess = max(0.0, sat_gc - OT_SAT_MAX / 100.0) / (1.0 - OT_SAT_MAX / 100.0);
    float gc_amt = excess * excess * (OT_SAT_BLEND / 100.0) * opendrt_t;
    result       = result + (gc_max - result) * gc_amt;

    // Black lift
    result = result * (1.0 - OT_BLACK_POINT / 100.0) + OT_BLACK_POINT / 100.0;

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
    float3 lab_in      = RGBtoOKLab(result);
    float  L_before    = max(lab_in.x, 0.0);
    float  L_mapped    = HermiteContrast(L_before, grey, opendrt_t);
    float  chroma_comp = (L_before > 0.001) ? pow(L_mapped / L_before, 0.5) : 1.0;
    result = OKLabtoRGB(float3(L_mapped, lab_in.yz * chroma_comp));

    // Highlight chroma rolloff (OKLab)
    float3 lab    = RGBtoOKLab(result);
    float hl_gate = smoothstep(0.65, 1.0, lab.x);
    lab.yz       *= (1.0 - hl_gate * OT_CHROMA_COMPRESS);
    result        = OKLabtoRGB(lab);

    // Debug indicator — green (slot 2)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 50) && pos.x < float(BUFFER_WIDTH - 38))
        return float4(0.1, 0.90, 0.1, 1.0);
    return saturate(float4(result, col.a));
}

// ─── Technique ───────────────────────────────────────────────────────────────

technique OlofssonianRenderChain
{
    pass WhiteBalance
    {
        VertexShader = PostProcessVS;
        PixelShader  = WhiteBalancePS;
        RenderTarget = CorrectiveBuf;
    }
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
    pass CopyBufToSrc0
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyBufToSrcPS;
        RenderTarget = CorrectiveSrcTex;
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
