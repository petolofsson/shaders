// primary_correction.fx — Input normalization (sRGB → linear working space)
//
// SKELETON — Step 1 of the professional pipeline.
//
// Current: de-gamma (sRGB → linear) + white balance + exposure.
// TODO: Add inverse tone mapping to recover highlight energy compressed
//       by the game's tone mapper (Reinhard/ACES approximation).
// TODO: Add IDT (Input Device Transform) per game if needed.
//
// Everything after this shader runs in linear light until output_transform.

#define WB_R     1.00   // R multiplier — >1.0 warmer, <1.0 cooler
#define WB_G     1.00
#define WB_B     1.00
#define EXPOSURE 0.00   // Stops — 0 = no change, +1 = one stop brighter

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

// ─── Pixel shader ──────────────────────────────────────────────────────────

float4 PrimaryCorrectionPS(float4 pos : SV_Position,
                           float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2474 && pos.x < 2486 && pos.y > 15 && pos.y < 27)
        return float4(1.0, 1.0, 1.0, 1.0);

    float4 col = tex2D(BackBuffer, uv);

    // De-gamma bypassed — intermediate shaders not yet tuned for linear space
    // TODO: re-enable pow(2.2) when full chain is linear-space aware
    float3 c = col.rgb * float3(WB_R, WB_G, WB_B) * pow(2.0, EXPOSURE);

    return float4(c, col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique PrimaryCorrection
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = PrimaryCorrectionPS;
    }
}
