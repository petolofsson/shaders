// pro_mist.fx — Black Pro-Mist diffusion filter
//
// Simulates optical softening of a Black Pro-Mist glass filter:
// highlights scatter into surroundings without bilateral suppression.
// Bright pixels contribute more to the scatter (luminance-weighted),
// making highlight bleed a feature, not an artefact.
//
// Two passes:
//   Pass 1: Luminance-weighted horizontal 9-tap Gaussian → DiffuseTex
//   Pass 2: Luminance-weighted vertical 9-tap Gaussian + composite → BackBuffer
//
// Contrast adaptation reads iqr from shared PercTex (no separate CDF walk).
//
// Shared texture contract:
//   PercTex { Width=1; Height=1; Format=RGBA16F } — written by frame_analysis
//   r=p25, g=p50, b=p75, a=iqr

#include "creative_values.fx"

#define LUM_BOOST         3.5    // extra scatter weight per unit source luminance
#define DIFFUSE_LUMA_LO   0.55   // gate: below this luma effect fades to zero
#define DIFFUSE_LUMA_HI   0.65   // gate: above this luma full effect
#define DIFFUSE_LUMA_CAP  0.95   // gate: fades back toward clip

#define GW0 0.2270
#define GW1 0.1945
#define GW2 0.1216
#define GW3 0.0540
#define GW4 0.0162

// ─── Shared percentile cache ───────────────────────────────────────────────

texture2D PercTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D PercSamp
{
    Texture   = PercTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Textures ─────────────────────────────────────────────────────────────

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D DiffuseTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 1; };
sampler2D DiffuseSamp
{
    Texture   = DiffuseTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// ─── Vertex shader ────────────────────────────────────────────────────────

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ─── Pass 1 — Luminance-weighted horizontal scatter ───────────────────────

float4 DiffuseHPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float  r   = DIFFUSE_RADIUS / 4.0;
    float3 acc = tex2Dlod(BackBuffer, float4(uv, 0, 0)).rgb * GW0;
    float  w   = GW0;

    float3 tp1 = tex2Dlod(BackBuffer, float4(uv + float2(r,     0), 0, 0)).rgb;
    float3 tn1 = tex2Dlod(BackBuffer, float4(uv - float2(r,     0), 0, 0)).rgb;
    float3 tp2 = tex2Dlod(BackBuffer, float4(uv + float2(r*2.0, 0), 0, 0)).rgb;
    float3 tn2 = tex2Dlod(BackBuffer, float4(uv - float2(r*2.0, 0), 0, 0)).rgb;
    float3 tp3 = tex2Dlod(BackBuffer, float4(uv + float2(r*3.0, 0), 0, 0)).rgb;
    float3 tn3 = tex2Dlod(BackBuffer, float4(uv - float2(r*3.0, 0), 0, 0)).rgb;
    float3 tp4 = tex2Dlod(BackBuffer, float4(uv + float2(r*4.0, 0), 0, 0)).rgb;
    float3 tn4 = tex2Dlod(BackBuffer, float4(uv - float2(r*4.0, 0), 0, 0)).rgb;

    float wp1 = GW1*(1.0+Luma(tp1)*LUM_BOOST); float wn1 = GW1*(1.0+Luma(tn1)*LUM_BOOST);
    float wp2 = GW2*(1.0+Luma(tp2)*LUM_BOOST); float wn2 = GW2*(1.0+Luma(tn2)*LUM_BOOST);
    float wp3 = GW3*(1.0+Luma(tp3)*LUM_BOOST); float wn3 = GW3*(1.0+Luma(tn3)*LUM_BOOST);
    float wp4 = GW4*(1.0+Luma(tp4)*LUM_BOOST); float wn4 = GW4*(1.0+Luma(tn4)*LUM_BOOST);

    acc += tp1*wp1 + tn1*wn1 + tp2*wp2 + tn2*wn2
         + tp3*wp3 + tn3*wn3 + tp4*wp4 + tn4*wn4;
    w   += wp1+wn1 + wp2+wn2 + wp3+wn3 + wp4+wn4;

    return float4(acc / w, 1.0);
}

// ─── Pass 2 — Luminance-weighted vertical scatter + composite ─────────────

float4 DiffuseVPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 base = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return base;

    float  r   = DIFFUSE_RADIUS / 4.0;
    float3 acc = tex2Dlod(DiffuseSamp, float4(uv, 0, 0)).rgb * GW0;
    float  w   = GW0;

    float3 tp1 = tex2Dlod(DiffuseSamp, float4(uv + float2(0, r),     0, 0)).rgb;
    float3 tn1 = tex2Dlod(DiffuseSamp, float4(uv - float2(0, r),     0, 0)).rgb;
    float3 tp2 = tex2Dlod(DiffuseSamp, float4(uv + float2(0, r*2.0), 0, 0)).rgb;
    float3 tn2 = tex2Dlod(DiffuseSamp, float4(uv - float2(0, r*2.0), 0, 0)).rgb;
    float3 tp3 = tex2Dlod(DiffuseSamp, float4(uv + float2(0, r*3.0), 0, 0)).rgb;
    float3 tn3 = tex2Dlod(DiffuseSamp, float4(uv - float2(0, r*3.0), 0, 0)).rgb;
    float3 tp4 = tex2Dlod(DiffuseSamp, float4(uv + float2(0, r*4.0), 0, 0)).rgb;
    float3 tn4 = tex2Dlod(DiffuseSamp, float4(uv - float2(0, r*4.0), 0, 0)).rgb;

    float wp1 = GW1*(1.0+Luma(tp1)*LUM_BOOST); float wn1 = GW1*(1.0+Luma(tn1)*LUM_BOOST);
    float wp2 = GW2*(1.0+Luma(tp2)*LUM_BOOST); float wn2 = GW2*(1.0+Luma(tn2)*LUM_BOOST);
    float wp3 = GW3*(1.0+Luma(tp3)*LUM_BOOST); float wn3 = GW3*(1.0+Luma(tn3)*LUM_BOOST);
    float wp4 = GW4*(1.0+Luma(tp4)*LUM_BOOST); float wn4 = GW4*(1.0+Luma(tn4)*LUM_BOOST);

    acc += tp1*wp1 + tn1*wn1 + tp2*wp2 + tn2*wn2
         + tp3*wp3 + tn3*wn3 + tp4*wp4 + tn4*wn4;
    w   += wp1+wn1 + wp2+wn2 + wp3+wn3 + wp4+wn4;
    float3 diffused = acc / w;

    float luma_in   = Luma(base.rgb);
    float luma_gate = smoothstep(DIFFUSE_LUMA_LO, DIFFUSE_LUMA_HI, luma_in)
                    * (1.0 - smoothstep(DIFFUSE_LUMA_CAP, 1.0, luma_in));

    float iqr       = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0)).a;
    float adapt_str = DIFFUSE_STRENGTH * lerp(0.7, 1.3, saturate(iqr / 0.5));

    // Debug indicator — magenta (slot 4)
    if (pos.y >= 10 && pos.y < 22 && pos.x >= float(BUFFER_WIDTH - 22) && pos.x < float(BUFFER_WIDTH - 10))
        return float4(0.9, 0.1, 0.9, 1.0);

    float3 result = lerp(base.rgb, diffused, adapt_str * luma_gate);
    float3 detail = base.rgb - diffused;
    float  bell   = luma_in * (1.0 - luma_in) * 4.0;
    result       += (CLARITY_STRENGTH / 100.0) * detail * bell;
    return float4(saturate(result), base.a);
}

// ─── Technique ────────────────────────────────────────────────────────────

technique ProMist
{
    pass DiffuseH
    {
        VertexShader = PostProcessVS;
        PixelShader  = DiffuseHPS;
        RenderTarget = DiffuseTex;
    }
    pass DiffuseV
    {
        VertexShader = PostProcessVS;
        PixelShader  = DiffuseVPS;
    }
}
