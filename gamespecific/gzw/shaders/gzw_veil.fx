// gzw_veil.fx — Veiling glare: humid air contrast reduction
//
// Simulates optical degradation from moisture/haze in the air.
// NOT bloom (which brightens highlights) — this compresses local contrast globally:
//   - Darks lift slightly (bright neighbours bleed in via blur)
//   - Brights pull down slightly (dark neighbours pull blur average down)
//   - Result: reduced local contrast, smeared edges, foggy/humid quality
//
// Technique: Dual Kawase blur at half-res (3 down + 3 up passes) → lerp onto scene
// Warm-green tint on veil layer matches jungle atmospheric scatter.
//
// Place in chain: after promist, before vignette and grain.
// NOTE: if promist feels too soft after adding this, reduce DIFFUSE_STRENGTH there.

// ─── Tuning ────────────────────────────────────────────────────────────────

#define VEIL_STRENGTH   0.17    // lerp toward blurred scene (0=off, 0.20=heavy haze)
#define VEIL_RADIUS     (BUFFER_WIDTH * 0.001465)   // Kawase tap scale — constant screen fraction (≈3.75px @ 2560)
#define VEIL_LUMA_CAP   0.82    // veil fades out above here — prevents glow on white surfaces
#define VEIL_TINT_R     1.02    // warm-green tint on veil layer
#define VEIL_TINT_G     1.00
#define VEIL_TINT_B     0.97

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

texture2D VeilDownTex
{
    Width  = BUFFER_WIDTH  / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler2D VeilDown
{
    Texture   = VeilDownTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D VeilUpTex
{
    Width  = BUFFER_WIDTH  / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler2D VeilUp
{
    Texture   = VeilUpTex;
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

// ─── Dual Kawase helpers ────────────────────────────────────────────────────

// Downsample pass: average 4 bilinear taps around pixel centre
float3 KawaseDown(sampler2D tex, float2 uv, float2 px)
{
    float3 c = 0;
    c += tex2D(tex, uv + float2(-px.x,  px.y) * 0.5).rgb;
    c += tex2D(tex, uv + float2( px.x,  px.y) * 0.5).rgb;
    c += tex2D(tex, uv + float2(-px.x, -px.y) * 0.5).rgb;
    c += tex2D(tex, uv + float2( px.x, -px.y) * 0.5).rgb;
    return c * 0.25;
}

// Upsample pass: 8-tap tent filter for smooth reconstruction
float3 KawaseUp(sampler2D tex, float2 uv, float2 px)
{
    float3 c = 0;
    c += tex2D(tex, uv + float2(-px.x * 2.0,  0.0      )).rgb * 1.0;
    c += tex2D(tex, uv + float2(-px.x,         px.y     )).rgb * 2.0;
    c += tex2D(tex, uv + float2( 0.0,          px.y*2.0 )).rgb * 1.0;
    c += tex2D(tex, uv + float2( px.x,         px.y     )).rgb * 2.0;
    c += tex2D(tex, uv + float2( px.x * 2.0,  0.0      )).rgb * 1.0;
    c += tex2D(tex, uv + float2( px.x,        -px.y     )).rgb * 2.0;
    c += tex2D(tex, uv + float2( 0.0,         -px.y*2.0 )).rgb * 1.0;
    c += tex2D(tex, uv + float2(-px.x,        -px.y     )).rgb * 2.0;
    return c / 12.0;
}

// ─── Pass 0: Downsample BackBuffer → VeilDownTex ────────────────────────────

float4 DownPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 px = float2(VEIL_RADIUS / BUFFER_WIDTH, VEIL_RADIUS / BUFFER_HEIGHT);
    return float4(KawaseDown(BackBuffer, uv, px), 1.0);
}

// ─── Pass 1: Upsample + blur VeilDownTex → VeilUpTex ───────────────────────

float4 UpPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // Half-res texel size scaled by radius
    float2 px = float2(VEIL_RADIUS * 2.0 / BUFFER_WIDTH, VEIL_RADIUS * 2.0 / BUFFER_HEIGHT);
    return float4(KawaseUp(VeilDown, uv, px), 1.0);
}

// ─── Pass 2: Composite — lerp veil onto scene ───────────────────────────────

float4 ApplyPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col  = tex2D(BackBuffer, uv);
    float3 veil = tex2D(VeilUp, uv).rgb;

    // Warm-green tint on veil layer — jungle atmospheric scatter
    // Luma-preserving: tint shifts hue, doesn't change overall brightness
    float3 tint     = float3(VEIL_TINT_R, VEIL_TINT_G, VEIL_TINT_B);
    float  lum_pre  = dot(veil, float3(0.2126, 0.7152, 0.0722));
    veil           *= tint;
    float  lum_post = dot(veil, float3(0.2126, 0.7152, 0.0722));
    veil           *= min(lum_pre / max(lum_post, 1e-5), 1.0);  // clamp: no upward push above original

    // Soft ceiling — prevents overcast/rain sky from washing the veil layer
    veil = min(veil, float3(0.92, 0.92, 0.92));

    // NVG gate — NVG green has near-zero blue, suppress veil spread on NVG pixels
    float not_nvg = smoothstep(0.05, 0.18, col.b);

    // White gate — prevents glow on bright surfaces (concrete, buildings)
    float veil_luma = dot(col.rgb, float3(0.2126, 0.7152, 0.0722));
    float white_gate = 1.0 - smoothstep(VEIL_LUMA_CAP, 0.97, veil_luma);

    // Sky gate — blue-dominant pixels (sky) skip veil to prevent teal tint
    float sky_dom = saturate((col.b - max(col.r, col.g)) * 8.0);
    float not_sky = 1.0 - sky_dom;

    // Contrast-reducing lerp: blending blurred scene lifts darks, pulls brights
    float3 result = lerp(col.rgb, veil, VEIL_STRENGTH * not_nvg * white_gate * not_sky);

    return float4(saturate(result), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique Veil
{
    pass Down
    {
        VertexShader = PostProcessVS;
        PixelShader  = DownPS;
        RenderTarget = VeilDownTex;
    }
    pass Up
    {
        VertexShader = PostProcessVS;
        PixelShader  = UpPS;
        RenderTarget = VeilUpTex;
    }
    pass Apply
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyPS;
    }
}
