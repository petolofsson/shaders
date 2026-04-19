// veil.fx — Veiling glare: atmospheric contrast reduction
//
// NOT bloom — the opposite: compresses local contrast by blending a blurred
// copy of the scene onto itself.
//   - Darks lift (bright neighbours bleed in)
//   - Brights pull down (dark neighbours pull the average down)
//   - Result: reduced local contrast, sense of air and haze
//
// Three passes:
//   Pass 1: Kawase downsample BackBuffer → VeilDownTex (half res)
//   Pass 2: Kawase upsample VeilDownTex → VeilUpTex (half res)
//   Pass 3: Lerp veil onto scene with luma + sky gates

// ─── Tuning ────────────────────────────────────────────────────────────────

#define VEIL_STRENGTH  0.10    // 0–1; lerp toward blurred scene (0.20 = heavy haze)
#define VEIL_WARMTH    0.5     // 0 = neutral, 1 = warm tint on veil layer

// ─── Internal constants ────────────────────────────────────────────────────

#define VEIL_RADIUS    (BUFFER_WIDTH * 0.001465)
#define VEIL_LUMA_CAP  0.82

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

// ─── Kawase helpers ────────────────────────────────────────────────────────

float3 KawaseDown(sampler2D tex, float2 uv, float2 px)
{
    float3 c = 0;
    c += tex2D(tex, uv + float2(-px.x,  px.y) * 0.5).rgb;
    c += tex2D(tex, uv + float2( px.x,  px.y) * 0.5).rgb;
    c += tex2D(tex, uv + float2(-px.x, -px.y) * 0.5).rgb;
    c += tex2D(tex, uv + float2( px.x, -px.y) * 0.5).rgb;
    return c * 0.25;
}

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

// ─── Pass 1 — Downsample ───────────────────────────────────────────────────

float4 DownPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 px = float2(VEIL_RADIUS / BUFFER_WIDTH, VEIL_RADIUS / BUFFER_HEIGHT);
    return float4(KawaseDown(BackBuffer, uv, px), 1.0);
}

// ─── Pass 2 — Upsample ─────────────────────────────────────────────────────

float4 UpPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 px = float2(VEIL_RADIUS * 2.0 / BUFFER_WIDTH, VEIL_RADIUS * 2.0 / BUFFER_HEIGHT);
    return float4(KawaseUp(VeilDown, uv, px), 1.0);
}

// ─── Pass 3 — Composite ────────────────────────────────────────────────────

float4 ApplyPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    if (pos.x > 2414 && pos.x < 2426 && pos.y > 15 && pos.y < 27)
        return float4(0.4, 0.6, 1.0, 1.0);

    float4 col  = tex2D(BackBuffer, uv);
    float3 veil = tex2D(VeilUp, uv).rgb;

    // Optional warm tint — luma-preserving so brightness stays flat
    float3 warm_tint = lerp(float3(1.0, 1.0, 1.0), float3(1.02, 1.00, 0.97), VEIL_WARMTH);
    float  lum_pre   = dot(veil, float3(0.2126, 0.7152, 0.0722));
    veil            *= warm_tint;
    float  lum_post  = dot(veil, float3(0.2126, 0.7152, 0.0722));
    veil            *= min(lum_pre / max(lum_post, 1e-5), 1.0);

    // Soft ceiling — prevents overcast sky from washing the veil layer
    veil = min(veil, float3(0.92, 0.92, 0.92));

    // White gate — prevents glow on very bright surfaces
    float veil_luma  = dot(col.rgb, float3(0.2126, 0.7152, 0.0722));
    float white_gate = 1.0 - smoothstep(VEIL_LUMA_CAP, 0.97, veil_luma);

    // Sky gate — blue-dominant pixels skip veil to prevent teal tint
    float sky_dom = saturate((col.b - max(col.r, col.g)) * 8.0);
    float not_sky = 1.0 - sky_dom;

    float3 result = lerp(col.rgb, veil, VEIL_STRENGTH * white_gate * not_sky);
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
