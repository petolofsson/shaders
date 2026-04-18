// gzw_foliage_pass.fx — Foliage color split + warm bloom + silver rim
//
// Consolidates all foliage work into one pass (moved from olofssonian_color_grade.fx):
//   - Color split: bright leaves → warm yellow-green, dark leaves → cool teal-green
//   - Warm bloom: soft glow on lit foliage surfaces
//   - Silver rim: cool blue-white specular on lit leaf edges
//   - Shadow rim: internal leaf gradient (dark core, brighter edge)
//
// Passes:
//   Pass 0 (Extract): warm-bright pixel extraction → WarmBloomTex (half-res)
//   Pass 1 (Apply):   foliage split → bloom composite → silver/shadow rim

// ─── Tuning ────────────────────────────────────────────────────────────────

// Foliage color split
#define FOLIAGE_SENS  2.2    // green dominance sensitivity
#define LEAF_SPLIT    0.38   // luma threshold — bright vs dark leaf
#define LEAF_WARM     0.36   // warm push on bright leaves (yellow-green)
#define LEAF_COOL     0.32   // cool pull on dark leaves (teal-green)

// Warm bloom
#define BLOOM_RADIUS       (BUFFER_WIDTH * 0.00293)
#define BLOOM_STRENGTH    0.50
#define EXTRACT_POWER     2.80
#define WARM_HUE_LO       0.05
#define WARM_HUE_HI       0.35
#define WARM_SAT_LO       0.12
#define WARM_LUMA_LO      0.38
#define KELVIN_R          1.06
#define KELVIN_G          1.00
#define KELVIN_B          0.78

// Silver rim
#define SILVER_RADIUS     (BUFFER_WIDTH * 0.000781)
#define SILVER_STRENGTH   0.60
#define SILVER_LIFT       1.45
#define SILVER_LUMA_LO    0.48

// Shadow rim
#define SHADOW_RIM_STRENGTH  0.35
#define SHADOW_RIM_LUMA_HI   0.52
#define SHADOW_RIM_CONTRAST  0.10

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

texture2D WarmBloomTex
{
    Width  = BUFFER_WIDTH  / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler2D WarmBloom
{
    Texture   = WarmBloomTex;
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

// ─── Pass 0: Warm-bright extraction → WarmBloomTex ─────────────────────────

float4 ExtractPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    float3 hsv = RGBtoHSV(col.rgb);

    float hue_w = smoothstep(WARM_HUE_LO,            WARM_HUE_LO + 0.05, hsv.x)
                * (1.0 - smoothstep(WARM_HUE_HI - 0.05, WARM_HUE_HI,     hsv.x));

    float sat_w  = smoothstep(WARM_SAT_LO,   WARM_SAT_LO + 0.12,  hsv.y);
    float luma_w = smoothstep(WARM_LUMA_LO,  WARM_LUMA_LO + 0.15, hsv.z);
    float not_nvg = smoothstep(0.05, 0.18, col.b);

    float mask = hue_w * sat_w * luma_w * not_nvg;

    float luma      = Luma(col.rgb);
    float l_bright  = pow(max(luma, 0.0), EXTRACT_POWER);
    float3 extracted = col.rgb * (l_bright / max(luma, 1e-5)) * mask;

    return float4(saturate(extracted), 1.0);
}

// ─── Pass 1: Foliage split → bloom composite → silver/shadow rim ────────────

float4 ApplyPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col    = tex2D(BackBuffer, uv);
    float3 result = col.rgb;

    // ── Foliage color split ──────────────────────────────────────────────────
    // Bright leaves → warm yellow-green. Dark leaves → cool teal-green.
    // Keyed to green dominance + saturation gate — concrete/sky untouched.
    float ch_max    = max(result.r, max(result.g, result.b));
    float ch_min    = min(result.r, min(result.g, result.b));
    float sat_gate  = smoothstep(0.22, 0.40, (ch_max - ch_min) / max(ch_max, 0.001));
    float leaf_green = saturate((result.g - max(result.r, result.b)) * FOLIAGE_SENS) * sat_gate;
    float leaf_luma  = Luma(result);
    float leaf_bright = leaf_green * smoothstep(LEAF_SPLIT - 0.15, LEAF_SPLIT + 0.15, leaf_luma);
    float leaf_dark   = leaf_green * (1.0 - smoothstep(LEAF_SPLIT - 0.15, LEAF_SPLIT + 0.15, leaf_luma));

    result.r = saturate(result.r + leaf_bright * LEAF_WARM * 0.20);
    result.g = saturate(result.g + leaf_bright * LEAF_WARM * 0.50);
    result.b = saturate(result.b - leaf_bright * LEAF_WARM * 0.85);
    float3 desat = float3(leaf_luma, leaf_luma, leaf_luma);
    result.rgb = lerp(result.rgb, desat, leaf_dark * LEAF_COOL * 0.85);
    result.b   = saturate(result.b + leaf_dark * LEAF_COOL * 0.18);

    float lc = Luma(result);

    // ── Bloom composite ──────────────────────────────────────────────────────
    float2 px = float2(BLOOM_RADIUS / BUFFER_WIDTH, BLOOM_RADIUS / BUFFER_HEIGHT);
    float2 pd = px * 0.707;

    float3 bloom;
    bloom  = tex2D(WarmBloom, uv).rgb                              * 0.1830;
    bloom += tex2D(WarmBloom, uv + float2( px.x,  0.0)).rgb        * 0.1110;
    bloom += tex2D(WarmBloom, uv + float2(-px.x,  0.0)).rgb        * 0.1110;
    bloom += tex2D(WarmBloom, uv + float2( 0.0,  px.y)).rgb        * 0.1110;
    bloom += tex2D(WarmBloom, uv + float2( 0.0, -px.y)).rgb        * 0.1110;
    bloom += tex2D(WarmBloom, uv + float2( pd.x,  pd.y)).rgb       * 0.0676;
    bloom += tex2D(WarmBloom, uv + float2(-pd.x,  pd.y)).rgb       * 0.0676;
    bloom += tex2D(WarmBloom, uv + float2( pd.x, -pd.y)).rgb       * 0.0676;
    bloom += tex2D(WarmBloom, uv + float2(-pd.x, -pd.y)).rgb       * 0.0676;
    bloom += tex2D(WarmBloom, uv + float2( px.x * 2.0,  0.0)).rgb  * 0.0249;
    bloom += tex2D(WarmBloom, uv + float2(-px.x * 2.0,  0.0)).rgb  * 0.0249;
    bloom += tex2D(WarmBloom, uv + float2( 0.0,  px.y * 2.0)).rgb  * 0.0249;
    bloom += tex2D(WarmBloom, uv + float2( 0.0, -px.y * 2.0)).rgb  * 0.0249;

    float3 kelvin  = float3(KELVIN_R, KELVIN_G, KELVIN_B);
    float  bl_pre  = Luma(bloom);
    bloom         *= kelvin;
    float  bl_post = Luma(bloom);
    bloom         *= (bl_pre / max(bl_post, 1e-5));

    float3 screen = 1.0 - (1.0 - result) * (1.0 - bloom * BLOOM_STRENGTH);

    // ── Silver rim ───────────────────────────────────────────────────────────
    float2 sr = float2(SILVER_RADIUS / BUFFER_WIDTH, SILVER_RADIUS / BUFFER_HEIGHT);
    float ln0 = Luma(tex2D(BackBuffer, uv + float2( sr.x,  0.0)).rgb);
    float ln1 = Luma(tex2D(BackBuffer, uv + float2(-sr.x,  0.0)).rgb);
    float ln2 = Luma(tex2D(BackBuffer, uv + float2( 0.0,  sr.y)).rgb);
    float ln3 = Luma(tex2D(BackBuffer, uv + float2( 0.0, -sr.y)).rgb);
    float min_nb = min(min(ln0, ln1), min(ln2, ln3));

    float nb_contrast = smoothstep(0.25, 0.40, lc - min_nb);

    float3 hsv_s    = RGBtoHSV(result);
    float foliage_h = smoothstep(WARM_HUE_LO,            WARM_HUE_LO + 0.05, hsv_s.x)
                    * (1.0 - smoothstep(WARM_HUE_HI - 0.05, WARM_HUE_HI,     hsv_s.x));
    float foliage_s = smoothstep(0.15, 0.30, hsv_s.y);

    float silver_luma = smoothstep(SILVER_LUMA_LO, SILVER_LUMA_LO + 0.15, lc);
    float silver_mask = foliage_h * foliage_s * silver_luma * nb_contrast;

    float3 silver_col = float3(lc * 0.97, lc * 1.00, lc * 1.05) * SILVER_LIFT;
    float3 out_result = lerp(screen, saturate(silver_col), silver_mask * SILVER_STRENGTH);

    // ── Shadow rim ───────────────────────────────────────────────────────────
    float shadow_luma = smoothstep(SHADOW_RIM_LUMA_HI, SHADOW_RIM_LUMA_HI - 0.15, lc);
    float shadow_nb   = smoothstep(SHADOW_RIM_CONTRAST, SHADOW_RIM_CONTRAST + 0.12, lc - min_nb);
    float shadow_mask = foliage_h * foliage_s * shadow_luma * shadow_nb;
    out_result = saturate(out_result + out_result * shadow_mask * SHADOW_RIM_STRENGTH);

    out_result = min(out_result, float3(0.97, 0.95, 0.92));

    return float4(saturate(out_result), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique FoliagePass
{
    pass Extract
    {
        VertexShader = PostProcessVS;
        PixelShader  = ExtractPS;
        RenderTarget = WarmBloomTex;
    }
    pass Apply
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyPS;
    }
}
