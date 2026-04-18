// gzw_halation.fx — Film halation: red/amber bleed from overexposed highlights
//
// Simulates light scattering back through the film base after overexposing the
// red-sensitive emulsion layer. Produces warm red-orange halos around bright
// highlights: lamp posts, sky patches, sun, bare concrete in direct light.
//
// Physical basis: Kodak Vision3 / ECN-2 process.
//   - Red layer sits deepest in the emulsion stack — re-exposed first on return trip
//   - Green layer gets partial re-exposure if source is bright enough
//   - Blue layer is essentially never reached
//   - Result: red-to-amber color, NOT white, NOT neutral
//   - Falloff is exponential (diffuse backing scatter), NOT Gaussian
//
// Four passes:
//   Pass 0 (Extract): Red-weighted bright pass + soft knee → HalationTex (half-res)
//                     Warm-green foliage hues excluded (foliage_light handles those)
//   Pass 1 (BlurH):   Horizontal exponential blur → HalationBlurHTex (half-res)
//   Pass 2 (BlurV):   Vertical exponential blur   → HalationBlurVTex (half-res)
//   Pass 3 (Apply):   Energy-normalized additive composite — single sample, full-res
//
// Blur fully contained at half-res. Pass 3 is one sample + math. ~75% cheaper than
// running the vertical blur at full resolution.
//
// Energy normalization (hotgluebanjo Proosa method):
//   halated = scene + halo * tint * strength
//   result  = halated / (tint * strength + 1.0)
//   → redistributes energy rather than adding it; highlights don't clip to white

// ─── Tuning ────────────────────────────────────────────────────────────────

#define HALATION_SIGMA      (BUFFER_WIDTH * 0.0120)    // blur spread — constant screen fraction (≈30px @ 2560)
#define HALATION_TAPS       20     // blur taps per direction on half-res texture
#define HALATION_THRESH     0.72   // bright-pass threshold (gamma space, 0–1)
#define HALATION_KNEE       0.18   // soft knee width around threshold
#define HALATION_STRENGTH   0.30   // overall halo intensity
#define HALATION_GREEN      0.18   // green channel contribution (amber warmth)
#define HALATION_BLUE       0.02   // blue channel contribution (minimal, physical)

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

texture2D HalationTex
{
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
};
sampler2D HalationSampler
{
    Texture   = HalationTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D HalationBlurHTex
{
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
};
sampler2D HalationBlurHSampler
{
    Texture   = HalationBlurHTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D HalationBlurVTex
{
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
};
sampler2D HalationBlurVSampler
{
    Texture   = HalationBlurVTex;
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

float3 RGBtoHSV(float3 c)
{
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float  d = q.x - min(q.w, q.y);
    float  e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// ─── Pass 0: Bright-pass extraction → HalationTex (half-res) ───────────────

float4 ExtractPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);

    // Red-weighted luma — film base weighting approximates red-layer sensitivity
    // (0.833, 0.083, 0.083) normalized from (1.0, 0.1, 0.1)
    float luma_w = dot(col.rgb, float3(0.833, 0.083, 0.083));

    // Soft knee threshold — only genuine overexposed highlights survive
    // Quadratic: hottest overexposed pixels produce most halation, barely-threshold far less
    float ramp = smoothstep(HALATION_THRESH - HALATION_KNEE,
                            HALATION_THRESH + HALATION_KNEE, luma_w);
          ramp = ramp * ramp;

    float3 hsv = RGBtoHSV(col.rgb);

    // Exclude green foliage hues — green in HSV is ~0.25–0.42 (90°–150°)
    float foliage_hue  = smoothstep(0.25, 0.30, hsv.x)
                       * (1.0 - smoothstep(0.38, 0.43, hsv.x));
    float foliage_gate = 1.0 - foliage_hue * smoothstep(0.12, 0.25, hsv.y);

    // No saturation gate — halation is brightness-driven, not color-driven.
    // Neutral white lamps are legitimate halation sources. Threshold handles selectivity.

    return float4(col.rgb * ramp * foliage_gate, 1.0);
}

// ─── Pass 1: Horizontal exponential blur → HalationBlurHTex (half-res) ─────

float4 BlurHPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float  sigma = HALATION_SIGMA;
    float  step  = 1.0 / BUFFER_WIDTH;

    float3 sum  = float3(0.0, 0.0, 0.0);
    float  wsum = 0.0;

    [loop]
    for (int i = -HALATION_TAPS; i <= HALATION_TAPS; i++)
    {
        float w = exp(-abs(float(i)) / sigma);
        sum  += tex2D(HalationSampler, uv + float2(float(i) * step, 0.0)).rgb * w;
        wsum += w;
    }

    return float4(sum / wsum, 1.0);
}

// ─── Pass 2: Vertical exponential blur → HalationBlurVTex (half-res) ────────

float4 BlurVPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float  sigma = HALATION_SIGMA;
    float  step  = 1.0 / BUFFER_HEIGHT;

    float3 sum  = float3(0.0, 0.0, 0.0);
    float  wsum = 0.0;

    [loop]
    for (int i = -HALATION_TAPS; i <= HALATION_TAPS; i++)
    {
        float w = exp(-abs(float(i)) / sigma);
        sum  += tex2D(HalationBlurHSampler, uv + float2(0.0, float(i) * step)).rgb * w;
        wsum += w;
    }

    return float4(sum / wsum, 1.0);
}

// ─── Pass 3: Energy-normalized composite — single sample, full-res ──────────

float4 ApplyPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 blurred = tex2D(HalationBlurVSampler, uv).rgb;

    float3 halo_tint = float3(1.0, HALATION_GREEN, HALATION_BLUE);

    float4 col    = tex2D(BackBuffer, uv);
    float3 halo   = blurred * halo_tint * HALATION_STRENGTH;
    float  norm   = HALATION_STRENGTH + 1.0;
    float3 result = (col.rgb + halo) / norm;

    return float4(saturate(result), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique Halation
{
    pass Extract
    {
        VertexShader = PostProcessVS;
        PixelShader  = ExtractPS;
        RenderTarget = HalationTex;
    }
    pass BlurH
    {
        VertexShader = PostProcessVS;
        PixelShader  = BlurHPS;
        RenderTarget = HalationBlurHTex;
    }
    pass BlurV
    {
        VertexShader = PostProcessVS;
        PixelShader  = BlurVPS;
        RenderTarget = HalationBlurVTex;
    }
    pass Apply
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyPS;
    }
}
