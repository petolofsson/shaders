// youvan_orthonorm.fx — Dynamic color space orthonormalization
//
// Based on Youvan (2024): "Dynamic Orthonormalization of Color Spaces:
// A Matrix Algebra Approach for Enhanced Signal Separation."
//
// Removes game-engine color cast by mapping per-zone mean colors to
// their luma-equivalent neutral grays. Blue shadows, warm highlights,
// and cross-channel bleed are undone before the alpha shaders see the signal.
//
// Three passes:
//   Pass 1 — ZoneStats: sample 64 Halton points, classify into dark/mid/bright
//             luma zones, compute per-zone mean RGB. Temporal lerp into ZoneTex.
//   Pass 2 — ComputeMatrix: build 3x3 correction matrix B = M × A⁻¹ from zone
//             means. Stored in MatrixTex (3 pixels = 3 rows of B).
//   Pass 3 — ApplyOrtho: sample MatrixTex, apply B per-pixel with STRENGTH blend.
//
// Chain position: primary_correction → frame_analysis → youvan_orthonorm → alpha_zone

// ─── Tuning ────────────────────────────────────────────────────────────────

#define ORTHO_STRENGTH   10     // -100 to 100; 0 = bypass, positive = correct toward neutral, negative = exaggerate cast
#define LERP_SPEED       2      // 0–100; adaptation speed — slow keeps matrix stable
#define ZONE_DARK_MAX    33     // 0–100; luma threshold: dark zone upper bound
#define ZONE_BRIGHT_MIN  66     // 0–100; luma threshold: bright zone lower bound

uniform int FRAME_COUNT < source = "framecount"; >;

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

// Zone mean colors — 3×1 RGBA16F
//   x=0: dark zone  (luma < ZONE_DARK_MAX)
//   x=1: mid zone   (ZONE_DARK_MAX ≤ luma < ZONE_BRIGHT_MIN)
//   x=2: bright zone (luma ≥ ZONE_BRIGHT_MIN)
//   RGBA: mean_r, mean_g, mean_b, initialised_flag
texture2D ZoneTex { Width = 3; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D ZoneSampler
{
    Texture   = ZoneTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// Correction matrix rows — 3×1 RGBA32F
//   x=0: row 0 of B  (R = B[0][0], G = B[0][1], B = B[0][2])
//   x=1: row 1 of B
//   x=2: row 2 of B
texture2D MatrixTex { Width = 3; Height = 1; Format = RGBA32F; MipLevels = 1; };
sampler2D MatrixSampler
{
    Texture   = MatrixTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Halton(2,3) — 64 points ───────────────────────────────────────────────

static const float2 kHalton[64] = {
    float2(0.500000, 0.333333), float2(0.250000, 0.666667),
    float2(0.750000, 0.111111), float2(0.125000, 0.444444),
    float2(0.625000, 0.777778), float2(0.375000, 0.222222),
    float2(0.875000, 0.555556), float2(0.062500, 0.888889),
    float2(0.562500, 0.037037), float2(0.312500, 0.370370),
    float2(0.812500, 0.703704), float2(0.187500, 0.148148),
    float2(0.687500, 0.481481), float2(0.437500, 0.814815),
    float2(0.937500, 0.259259), float2(0.031250, 0.592593),
    float2(0.531250, 0.925926), float2(0.281250, 0.074074),
    float2(0.781250, 0.407407), float2(0.156250, 0.740741),
    float2(0.656250, 0.185185), float2(0.406250, 0.518519),
    float2(0.906250, 0.851852), float2(0.093750, 0.296296),
    float2(0.593750, 0.629630), float2(0.343750, 0.962963),
    float2(0.843750, 0.012346), float2(0.218750, 0.345679),
    float2(0.718750, 0.679012), float2(0.468750, 0.123457),
    float2(0.968750, 0.456790), float2(0.015625, 0.790123),
    float2(0.515625, 0.234568), float2(0.265625, 0.567901),
    float2(0.765625, 0.901235), float2(0.140625, 0.049383),
    float2(0.640625, 0.382716), float2(0.390625, 0.716049),
    float2(0.890625, 0.160494), float2(0.078125, 0.493827),
    float2(0.578125, 0.827160), float2(0.328125, 0.271605),
    float2(0.828125, 0.604938), float2(0.203125, 0.938272),
    float2(0.703125, 0.086420), float2(0.453125, 0.419753),
    float2(0.953125, 0.753086), float2(0.046875, 0.197531),
    float2(0.546875, 0.530864), float2(0.296875, 0.864198),
    float2(0.796875, 0.308642), float2(0.171875, 0.641975),
    float2(0.671875, 0.975309), float2(0.421875, 0.024691),
    float2(0.921875, 0.358025), float2(0.109375, 0.691358),
    float2(0.609375, 0.135802), float2(0.359375, 0.469136),
    float2(0.859375, 0.802469), float2(0.234375, 0.246914),
    float2(0.734375, 0.580247), float2(0.484375, 0.913580),
    float2(0.984375, 0.061728), float2(0.007812, 0.395062)
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

// Analytical 3×3 matrix inverse. Returns identity if singular.
float3x3 Invert3x3(float3x3 m)
{
    float a = m[0][0], b = m[0][1], c = m[0][2];
    float d = m[1][0], e = m[1][1], f = m[1][2];
    float g = m[2][0], h = m[2][1], i = m[2][2];

    float A =  e*i - f*h;
    float B = -(d*i - f*g);
    float C =  d*h - e*g;
    float D = -(b*i - c*h);
    float E =  a*i - c*g;
    float F = -(a*h - b*g);
    float G =  b*f - c*e;
    float H = -(a*f - c*d);
    float I =  a*e - b*d;

    float det = a*A + b*B + c*C;
    if (abs(det) < 1e-6)
        return float3x3(1,0,0, 0,1,0, 0,0,1);

    float inv_det = 1.0 / det;
    // Adjugate (transposed cofactor matrix) / det
    return float3x3(A*inv_det, D*inv_det, G*inv_det,
                    B*inv_det, E*inv_det, H*inv_det,
                    C*inv_det, F*inv_det, I*inv_det);
}

// ─── Pass 1 — Zone statistics ──────────────────────────────────────────────
// Samples 64 Halton points per frame. Classifies each sample into a luma zone.
// Computes per-zone mean RGB and lerps into ZoneTex for temporal stability.

float4 ZoneStatsPS(float4 pos : SV_Position,
                   float2 uv  : TEXCOORD0) : SV_Target
{
    int zone = int(pos.x);
    if (pos.y >= 1.0 || zone >= 3) return float4(0, 0, 0, 0);

    float3 sum = 0.0;
    float  w   = 0.0;

    [loop]
    for (int i = 0; i < 64; i++)
    {
        float3 rgb  = tex2Dlod(BackBuffer, float4(kHalton[i], 0, 0)).rgb;
        float  luma = Luma(rgb);

        float in_zone = 0.0;
        if (zone == 0) in_zone = step(luma,                    ZONE_DARK_MAX   / 100.0);
        if (zone == 1) in_zone = step(ZONE_DARK_MAX  / 100.0, luma) * step(luma, ZONE_BRIGHT_MIN / 100.0);
        if (zone == 2) in_zone = step(ZONE_BRIGHT_MIN / 100.0, luma);

        sum += rgb * in_zone;
        w   += in_zone;
    }

    // Fallback: neutral gray at zone centre luma if no samples landed here
    float fallback = (zone == 0) ? (ZONE_DARK_MAX   / 100.0) * 0.5
                   : (zone == 1) ? 0.50
                   :               (1.0 + ZONE_BRIGHT_MIN / 100.0) * 0.5;
    float3 mean = (w > 0.5) ? (sum / w) : float3(fallback, fallback, fallback);

    float4 prev  = tex2Dlod(ZoneSampler, float4((zone + 0.5) / 3.0, 0.5, 0, 0));
    float  speed = (prev.a < 0.001) ? 1.0 : (LERP_SPEED / 100.0);

    return float4(lerp(prev.rgb, mean, speed), lerp(prev.a, 1.0, speed));
}

// ─── Pass 2 — Build correction matrix ──────────────────────────────────────
// Reads ZoneTex, constructs A and M, computes B = M × A⁻¹.
// Outputs one row of B per pixel (runs on a 3×1 render target — near-zero cost).

float4 ComputeMatrixPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    int row = int(pos.x);
    if (pos.y >= 1.0 || row >= 3) return float4(0, 0, 0, 1);

    float3 v_dark   = tex2Dlod(ZoneSampler, float4(0.5 / 3.0, 0.5, 0, 0)).rgb;
    float3 v_mid    = tex2Dlod(ZoneSampler, float4(1.5 / 3.0, 0.5, 0, 0)).rgb;
    float3 v_bright = tex2Dlod(ZoneSampler, float4(2.5 / 3.0, 0.5, 0, 0)).rgb;

    float L_dark   = Luma(v_dark);
    float L_mid    = Luma(v_mid);
    float L_bright = Luma(v_bright);

    // A: zone means as columns
    float3x3 A = float3x3(
        v_dark.r,   v_mid.r,   v_bright.r,
        v_dark.g,   v_mid.g,   v_bright.g,
        v_dark.b,   v_mid.b,   v_bright.b
    );

    // M: target — each zone mean maps to neutral gray at its own luma
    //   column 0 target: (L_dark, L_dark, L_dark)
    //   column 1 target: (L_mid,  L_mid,  L_mid)
    //   column 2 target: (L_bright, L_bright, L_bright)
    float3x3 M = float3x3(
        L_dark,   L_mid,   L_bright,
        L_dark,   L_mid,   L_bright,
        L_dark,   L_mid,   L_bright
    );

    float3x3 B = mul(M, Invert3x3(A));

    return float4(B[row][0], B[row][1], B[row][2], 1.0);
}

// ─── Pass 3 — Apply correction ─────────────────────────────────────────────

float4 ApplyOrthoPS(float4 pos : SV_Position,
                    float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.x > 2459 && pos.x < 2471 && pos.y > 15 && pos.y < 27)
        return float4(0.0, 0.85, 0.3, 1.0);

    float4 col = tex2D(BackBuffer, uv);

    float3 B0 = tex2D(MatrixSampler, float2(0.5 / 3.0, 0.5)).rgb;
    float3 B1 = tex2D(MatrixSampler, float2(1.5 / 3.0, 0.5)).rgb;
    float3 B2 = tex2D(MatrixSampler, float2(2.5 / 3.0, 0.5)).rgb;

    float3 corrected;
    corrected.r = dot(B0, col.rgb);
    corrected.g = dot(B1, col.rgb);
    corrected.b = dot(B2, col.rgb);

    // Preserve original saturation and brightness — ortho corrects hue only
    float orig_max = max(col.r, max(col.g, col.b));
    float orig_min = min(col.r, min(col.g, col.b));
    float orig_sat = (orig_max > 0.001) ? (orig_max - orig_min) / orig_max : 0.0;

    float corr_max = max(corrected.r, max(corrected.g, corrected.b));
    float corr_min = min(corrected.r, min(corrected.g, corrected.b));
    float corr_sat = (corr_max > 0.001) ? (corr_max - corr_min) / corr_max : 0.0;

    float sat_scale        = (corr_sat > 0.001) ? orig_sat / corr_sat : 1.0;
    float brightness_scale = (corr_max > 0.001) ? orig_max / corr_max : 1.0;
    float3 hue_only = corr_max > 0.001
                    ? lerp(corr_max, corrected, sat_scale) * brightness_scale
                    : corrected;

    float3 result = lerp(col.rgb, hue_only, ORTHO_STRENGTH / 100.0);
    return float4(saturate(result), col.a);
}

// ─── Technique ─────────────────────────────────────────────────────────────

technique YouvanOrthoNorm
{
    pass ZoneStats
    {
        VertexShader = PostProcessVS;
        PixelShader  = ZoneStatsPS;
        RenderTarget = ZoneTex;
    }
    pass ComputeMatrix
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeMatrixPS;
        RenderTarget = MatrixTex;
    }
    pass ApplyOrtho
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyOrthoPS;
    }
}
