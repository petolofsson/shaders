// film_grain.fx — Luminance-weighted film grain
//
// Adds frame-varying pseudo-random grain weighted by mid-tone luminance.
// Grain is strongest at luma=0.5 (mid-tones), fading to zero at pure
// black and pure white — matching the grain distribution of real film.
//
// Temporal variation: FRAME_COUNT seeds the hash so grain animates
// every frame (looks like film, not static digital noise).
//
// Notes from coder: from notes_from_coder.md Step 5 (Output / Dither).
// Hides 8-bit banding introduced by stretching/compressing the signal
// through the grade chain above. Use after output_transform when added.

// ─── Tuning ────────────────────────────────────────────────────────────────

#define GRAIN_STRENGTH   3.5    // 0–100; peak noise amplitude — subtle: 2–4
#define GRAIN_SIZE       1.0    // pixel clump size; 1 = per-pixel, 2 = 2×2

uniform int FRAME_COUNT < source = "framecount"; >;

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

// High-quality hash — better distribution than sin-based rand
float Hash(float2 p)
{
    p = frac(p * float2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return frac((p.x + p.y) * p.x);
}

// ─── Pixel shader ──────────────────────────────────────────────────────────

float4 FilmGrainPS(float4 pos : SV_Position,
                   float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2429 && pos.x < 2441 && pos.y > 15 && pos.y < 27)
        return float4(0.2, 0.0, 0.2, 1.0);

    float4 col = tex2D(BackBuffer, uv);

    // Grain cell — floor snaps to grain-size grid
    float2 grain_pos = floor(pos.xy / GRAIN_SIZE) + float(FRAME_COUNT % 1000) * 1.618;
    float  noise     = Hash(grain_pos) * 2.0 - 1.0;   // [-1, 1]

    // Luminance-dependent weight: peaks at mid-tone (luma=0.5), zero at 0 and 1
    float luma   = Luma(col.rgb);
    float weight = 4.0 * luma * (1.0 - luma);

    float3 result = col.rgb + noise * weight * (GRAIN_STRENGTH / 100.0);
    return float4(saturate(result), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique FilmGrain
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = FilmGrainPS;
    }
}
