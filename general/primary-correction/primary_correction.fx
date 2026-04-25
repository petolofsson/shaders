// primary_correction.fx — Exposure normalization (game-agnostic)
//
// Single job: scale scene exposure so p95 lands at TARGET_P95.
// Pure multiplicative gain — no black-point subtraction, no contrast.
// White balance (WB_R/G/B): neutral by default.

#define WB_R        100    // 0–200; 100 = neutral
#define WB_G        100
#define WB_B        100
#define TARGET_P95  1.0
#define LERP_SPEED  3      // % per frame temporal smoothing — prevents flicker

// ─── Scene stats — 1×1 RGBA16F: .r = p95 ─────────────────────────────────

texture2D ITMTex { Width = 1; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D ITMSamp
{
    Texture   = ITMTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer
{
    Texture   = BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ─── Pass 1 — Compute p95 from BackBuffer ─────────────────────────────────

float4 ComputeStatsPS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    float4 prev = tex2Dlod(ITMSamp, float4(0.5, 0.5, 0, 0));

    float lo = 0.0, hi = 1.0;
    [loop]
    for (int i = 0; i < 8; i++)
    {
        float mid = (lo + hi) * 0.5;
        float below = 0.0;
        [loop]
        for (int y = 0; y < 8; y++)
        [loop]
        for (int x = 0; x < 8; x++)
        {
            float luma = Luma(tex2Dlod(BackBuffer,
                float4((x + 0.5) / 8.0, (y + 0.5) / 8.0, 0, 0)).rgb);
            below += (luma < mid) ? 1.0 : 0.0;
        }
        if (below / 64.0 < 0.95) lo = mid; else hi = mid;
    }
    float p95 = (lo + hi) * 0.5;

    float speed = (prev.b < 0.5) ? 1.0 : LERP_SPEED / 100.0;
    return float4(lerp(prev.r, p95, speed), 0.0, 1.0, 1.0);
}

// ─── Pass 2 — Exposure gain: scale so p95 → TARGET_P95 ───────────────────

float4 PrimaryCorrectionPS(float4 pos : SV_Position,
                           float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);

    if (pos.y < 1.0) return col;  // data highway — must not be modified

    float p95 = tex2D(ITMSamp, float2(0.5, 0.5)).r;
    float ae  = TARGET_P95 / max(p95, 0.01);

    float3 c = col.rgb * float3(WB_R / 100.0, WB_G / 100.0, WB_B / 100.0);
    return float4(c * ae, col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique PrimaryCorrection
{
    pass ComputeStats
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeStatsPS;
        RenderTarget = ITMTex;
    }
    pass Apply
    {
        VertexShader = PostProcessVS;
        PixelShader  = PrimaryCorrectionPS;
    }
}
