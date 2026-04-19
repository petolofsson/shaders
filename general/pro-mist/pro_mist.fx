// pro_mist.fx — Black Pro-Mist diffusion filter
//
// Mimics the Black Pro-Mist optical filter: highlights bloom softly into
// surrounding areas, breaking the pixel-perfect edge of game graphics.
//
// Technique: separable 13-tap Gaussian blur screened over original,
// gated by a luminance mask so only highlights glow.
// Shadows are lifted slightly by the additive blend (filmic veil effect).
//
// Two passes:
//   Pass 1 — HBlur: horizontal Gaussian → BlurTex
//   Pass 2 — VBlur + Composite: vertical Gaussian on BlurTex,
//             then additive screen over BackBuffer weighted by highlight mask.
//
// Notes from coder: from notes_from_coder.md Step 3 (Look Creation).

// ─── Tuning ────────────────────────────────────────────────────────────────

#define MIST_STRENGTH    18     // 0–100; glow intensity — 0 = bypass, 30 = heavy
#define HIGHLIGHT_START  55     // 0–100; luma below this gets no glow
#define HIGHLIGHT_PEAK   85     // 0–100; luma above this gets full glow weight
#define BLUR_STEP_U      (8.0 / 2560.0)  // horizontal tap spacing in UV
#define BLUR_STEP_V      (8.0 / 1440.0)  // vertical tap spacing in UV

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

texture2D BlurTex { Width = 2560; Height = 1440; Format = RGBA16F; MipLevels = 1; };
sampler2D BlurSampler
{
    Texture   = BlurTex;
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

// 13-tap Gaussian weights (sigma=2.5 tap-widths), centre-out
// w[0]=centre, w[1..6]=progressively smaller
static const float kGauss[7] = {
    0.2261, 0.1932, 0.1192, 0.0535, 0.0174, 0.0041, 0.0007
};

// ─── Pass 1 — Horizontal Gaussian blur ─────────────────────────────────────

float4 HBlurPS(float4 pos : SV_Position,
               float2 uv  : TEXCOORD0) : SV_Target
{
    float3 col = tex2Dlod(BackBuffer, float4(uv, 0, 0)).rgb * kGauss[0];

    [loop]
    for (int i = 1; i <= 6; i++)
    {
        float du = float(i) * BLUR_STEP_U;
        col += tex2Dlod(BackBuffer, float4(uv + float2( du, 0), 0, 0)).rgb * kGauss[i];
        col += tex2Dlod(BackBuffer, float4(uv - float2( du, 0), 0, 0)).rgb * kGauss[i];
    }

    return float4(col, 1.0);
}

// ─── Pass 2 — Vertical blur + composite ────────────────────────────────────

float4 VBlurCompositePS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2444 && pos.x < 2456 && pos.y > 15 && pos.y < 27)
        return float4(0.1, 0.1, 0.6, 1.0);

    float4 orig  = tex2D(BackBuffer, uv);

    // Vertical pass on BlurTex (already H-blurred)
    float3 blur = tex2D(BlurSampler, uv).rgb * kGauss[0];
    for (int i = 1; i <= 6; i++)
    {
        float dv = float(i) * BLUR_STEP_V;
        blur += tex2D(BlurSampler, uv + float2(0,  dv)).rgb * kGauss[i];
        blur += tex2D(BlurSampler, uv - float2(0,  dv)).rgb * kGauss[i];
    }

    // Highlight luminance mask — only bright pixels emit glow
    float orig_luma = Luma(orig.rgb);
    float mask      = smoothstep(HIGHLIGHT_START / 100.0, HIGHLIGHT_PEAK / 100.0, orig_luma);

    // Additive screen blend: glow adds to highlights, lifts shadows very slightly
    float3 glow   = blur * mask * (MIST_STRENGTH / 100.0);
    float3 result = orig.rgb + glow - orig.rgb * glow;   // screen blend formula

    return float4(saturate(result), orig.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique ProMist
{
    pass HBlur
    {
        VertexShader = PostProcessVS;
        PixelShader  = HBlurPS;
        RenderTarget = BlurTex;
    }
    pass VBlurComposite
    {
        VertexShader = PostProcessVS;
        PixelShader  = VBlurCompositePS;
    }
}
