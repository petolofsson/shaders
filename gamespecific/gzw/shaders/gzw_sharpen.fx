// gzw_sharpen.fx — Adaptive selective sharpening
//
// Sharpens naturally sharp chromatic edges while leaving diffused/soft/neutral areas alone.
// Three-way gating:
//   luma_w     — bright surfaces get more sharpening, dark shadows stay soft
//   contrast_w — only fires where local contrast is meaningful
//                (low contrast = diffused/misty area → gate closes)
//   sat_w      — only fires on chromatic pixels (foliage, bark, surfaces with real color)
//                skips neutral concrete, sky, roads
//
// Place in chain: after veil, before ca and vignette.

// ─── Tuning ────────────────────────────────────────────────────────────────

#define SHARPEN_STRENGTH  0.28   // sharpening amount (0=off, 0.5=moderate, 1.0=heavy)
#define SHARPEN_LUMA_LO   0.18   // luma below this gets no sharpening — darks stay soft
#define CONTRAST_LO       0.05   // local contrast floor — below = diffused/mist, skip
#define CONTRAST_HI       0.15   // local contrast ceiling — above = full sharpening

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

// ─── Pixel shader ──────────────────────────────────────────────────────────

float4 SharpenPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 px = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);

    float4 col = tex2D(BackBuffer, uv);
    float3 c   = col.rgb;
    float3 n   = tex2D(BackBuffer, uv + float2( 0.0,  -px.y)).rgb;
    float3 s   = tex2D(BackBuffer, uv + float2( 0.0,   px.y)).rgb;
    float3 e   = tex2D(BackBuffer, uv + float2( px.x,  0.0 )).rgb;
    float3 w   = tex2D(BackBuffer, uv + float2(-px.x,  0.0 )).rgb;

    // Unsharp mask — high-frequency detail layer
    float3 blur   = (n + s + e + w) * 0.25;
    float3 detail = c - blur;

    // Local contrast — max luma difference to any cardinal neighbor
    // Low = area was diffused by promist or is naturally soft (mist, sky gradient)
    // High = genuine edge — foliage detail, bark, surface texture
    float lc  = Luma(c);
    float diff = max(max(abs(lc - Luma(n)), abs(lc - Luma(s))),
                     max(abs(lc - Luma(e)), abs(lc - Luma(w))));

    // Contrast gate — closes on diffused/soft areas, opens on sharp edges
    float contrast_w = smoothstep(CONTRAST_LO, CONTRAST_HI, diff);

    // Luma gate — quadratic, concentrates sharpening on bright surfaces
    float luma_raw = saturate((lc - SHARPEN_LUMA_LO) / (1.0 - SHARPEN_LUMA_LO));
    float luma_w   = luma_raw * luma_raw;

    // Saturation gate — skips neutral concrete, sky, roads; fires on foliage/bark/surfaces
    float ch_max = max(c.r, max(c.g, c.b));
    float ch_min = min(c.r, min(c.g, c.b));
    float sat    = (ch_max > 0.001) ? (ch_max - ch_min) / ch_max : 0.0;
    float sat_w  = smoothstep(0.08, 0.22, sat);

    float3 result = saturate(c + detail * SHARPEN_STRENGTH * luma_w * contrast_w * sat_w);

    return float4(result, col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique Sharpen
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = SharpenPS;
    }
}
