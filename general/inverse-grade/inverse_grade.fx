// inverse_grade.fx — Adaptive inverse S-curve pre-grade
//
// Reads the scene's luminance histogram (LumHistTex, written by frame_analysis)
// and applies an adaptive inverse S-curve anchored at the scene median (p50).
// Expands shadows down and highlights up — opposite of the game's baked S-curve.
// Strength, pivot, and shape all adapt per-frame from the histogram.
// Output is a flatter, log-like signal for re-grading by corrective_render_chain.
//
// Pass 1  InverseGrade   BackBuffer → BackBuffer
//
// Shared texture contract:
//   LumHistTex { Width=64; Height=1; Format=R32F } — declared in frame_analysis (WRITER)

#define IG_MAX  0.35  // maximum inverse-grade strength

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

texture2D LumHistTex { Width = 64; Height = 1; Format = R32F; MipLevels = 1; };
sampler2D LumHistSamp
{
    Texture   = LumHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
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

// ─── Helpers ───────────────────────────────────────────────────────────────

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// Inverse S-curve anchored at pivot — expands range away from pivot in both directions.
// Below pivot: compresses toward 0 (undoes shadow lift).
// Above pivot: expands toward/past 1.0 (undoes highlight compression).
float InverseS(float x, float pivot, float strength)
{
    float d = x - pivot;
    float lo_range = max(pivot, 0.001);
    float hi_range = max(1.0 - pivot, 0.001);
    float norm     = (d < 0.0) ? saturate(-d / lo_range) : saturate(d / hi_range);

    // Inverse power: expands away from pivot (1/(1+s) < 1 → convex, pushes outward)
    float expanded = pow(norm, 1.0 / (1.0 + strength));

    // Highlights allowed to exceed 1.0 — recovered in RGBA16F corrective buffer
    float out_range = (d < 0.0) ? lo_range : hi_range * (1.0 + strength * 0.4);

    return pivot + (d < 0.0 ? -1.0 : 1.0) * expanded * out_range;
}

// ─── Pass 1 — Inverse grade ────────────────────────────────────────────────

float4 InverseGradePS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;

    // CDF walk — p25/p50/p75 from luminance histogram
    float cumul = 0.0;
    float p25 = 0.25, p50 = 0.50, p75 = 0.75;
    float lk25 = 0.0, lk50 = 0.0, lk75 = 0.0;

    [loop] for (int b = 0; b < 64; b++)
    {
        float bv  = float(b) / 64.0;
        float frc = tex2Dlod(LumHistSamp, float4((float(b) + 0.5) / 64.0, 0.5, 0, 0)).r;
        cumul += frc;

        float at25 = step(0.25, cumul) * (1.0 - lk25);
        float at50 = step(0.50, cumul) * (1.0 - lk50);
        float at75 = step(0.75, cumul) * (1.0 - lk75);
        p25  = lerp(p25,  bv, at25);
        p50  = lerp(p50,  bv, at50);
        p75  = lerp(p75,  bv, at75);
        lk25 = saturate(lk25 + at25);
        lk50 = saturate(lk50 + at50);
        lk75 = saturate(lk75 + at75);
    }

    float iqr      = saturate(p75 - p25);
    float strength = saturate(smoothstep(0.15, 0.50, iqr) * IG_MAX);

    // Apply inverse S on luma, scale RGB to preserve hue
    float luma_in  = Luma(col.rgb);
    float luma_out = InverseS(luma_in, p50, strength);
    float scale    = (luma_in > 0.001) ? luma_out / luma_in : 1.0;
    float3 rgb_out = lerp(col.rgb, col.rgb * scale, strength);

    return float4(rgb_out, col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique InverseGrade
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = InverseGradePS;
    }
}
