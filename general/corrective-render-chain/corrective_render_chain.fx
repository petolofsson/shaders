// olofssonian_render_chain.fx — Corrective chain + display transform (game-agnostic)
//
// Single effect. All passes share CorrectiveBuf (RGBA16F) — no UNORM clamping
// between stages. Full scene-linear range reaches OpenDRT intact.
//
// CORRECTIVE (technical, game-agnostic):
//   Pass  1  WhiteBalance      BackBuffer    → CorrectiveBuf   WB_R/G/B only; no tonal change
//   Pass  2  ZoneStats         CorrectiveBuf → ZoneTex         Youvan: 64 Halton zone means
//   Pass  3  ComputeMatrix     ZoneTex       → MatrixTex       Youvan: B = M × A⁻¹
//   Pass  4  CopyBufToSrc      CorrectiveBuf → CorrectiveSrcTex
//   Pass  5  ApplyOrtho        CorrectiveSrc → CorrectiveBuf   Youvan: hue correction
//   Pass  6  ComputeLowFreq    CorrectiveBuf → LowFreqTex      Zone: 1/8 res downsample
//   Pass  7  ComputeZoneHist   LowFreqTex    → ZoneHistTex     Zone: 32-bin per-zone histogram
//   Pass  8  BuildZoneLevels   ZoneHistTex   → ZoneLevelsTex   Zone: CDF → zone medians
//   Pass  9  CopyBufToSrc      CorrectiveBuf → CorrectiveSrcTex
//   Pass 10  ApplyContrast     CorrectiveSrc → CorrectiveBuf   Zone: S-curve anchored at median
//   Pass 11  BuildSatLevels    SatHistTex    → SatLevelsTex    Chroma: CDF → band medians
//   Pass 12  CopyBufToSrc      CorrectiveBuf → CorrectiveSrcTex
//   Pass 13  ApplyChroma       CorrectiveSrc → CorrectiveBuf   Chroma: per-hue S-curve
//   Pass 14  CopyBufToSrc      CorrectiveBuf → CorrectiveSrcTex
//
// OUTPUT TRANSFORM (display rendering, not creative):
//   Pass 15  OutputTransform   CorrectiveSrc → BackBuffer      OpenDRT + OKLab highlight rolloff

// ─── White balance ──────────────────────────────────────────────────────────
#define WB_R  100   // 0–200; 100 = neutral
#define WB_G  100
#define WB_B  100

// ─── Youvan ─────────────────────────────────────────────────────────────────
#define YOUVAN_LERP_SPEED       2      // 0–100; zone mean adaptation speed
#define YOUVAN_ZONE_DARK_MAX    33     // luma threshold: dark zone upper bound
#define YOUVAN_ZONE_BRIGHT_MIN  66     // luma threshold: bright zone lower bound

// ─── Alpha zone contrast ─────────────────────────────────────────────────────
#define ZONE_CURVE_STRENGTH  0      // 0–100; S-curve blend strength
#define ZONE_LERP_SPEED      0.01   // % per second, frametime-normalized
#define ZONE_HIST_LERP       5.0    // % per second, frametime-normalized

// ─── Alpha chroma lift ───────────────────────────────────────────────────────
#define CHROMA_CURVE_STRENGTH  0      // 0–100; S-curve blend strength
#define CHROMA_LERP_SPEED      0.01   // % per second, frametime-normalized
#define CHROMA_BAND_WIDTH      0.15   // hue band half-width — must match frame_analysis.fx

// ─── Output transform ────────────────────────────────────────────────────────
#define OT_CONTRAST         1.35    // tone curve contrast
#define OT_CHROMA_COMPRESS  0.40    // highlight chroma rolloff strength
#define OT_BLACK_POINT      3.5     // black floor lift (0–100)
#define OT_SAT_MAX          85      // gamut compression threshold (0–100)
#define OT_SAT_BLEND        15      // gamut compression strength (0–100)

uniform float frametime < source = "frametime"; >;

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

texture2D CorrectiveBuf { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 1; };
sampler2D CorrectiveSamp
{
    Texture   = CorrectiveBuf;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D CorrectiveSrcTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 1; };
sampler2D CorrectiveSrc
{
    Texture   = CorrectiveSrcTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// Shared with frame_analysis — identical declaration = same GPU resource
texture2D SatHistTex { Width = 64; Height = 6; Format = R32F; MipLevels = 1; };
sampler2D SatHistSamp
{
    Texture   = SatHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Youvan textures ─────────────────────────────────────────────────────────

texture2D ZoneTex { Width = 3; Height = 1; Format = RGBA16F; MipLevels = 1; };
sampler2D ZoneSampler
{
    Texture   = ZoneTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D MatrixTex { Width = 3; Height = 1; Format = RGBA32F; MipLevels = 1; };
sampler2D MatrixSampler
{
    Texture   = MatrixTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Alpha zone textures ──────────────────────────────────────────────────────

texture2D LowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; MipLevels = 1; };
sampler2D LowFreqSamp
{
    Texture   = LowFreqTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture2D ZoneHistTex { Width = 32; Height = 16; Format = R16F; MipLevels = 1; };
sampler2D ZoneHistSamp
{
    Texture   = ZoneHistTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture2D ZoneLevelsTex { Width = 4; Height = 4; Format = R16F; MipLevels = 1; };
sampler2D ZoneLevelsSamp
{
    Texture   = ZoneLevelsTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// ─── Alpha chroma textures ────────────────────────────────────────────────────

texture2D SatLevelsTex { Width = 6; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D SatLevelsSamp
{
    Texture   = SatLevelsTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
};

// ─── Vertex shader ───────────────────────────────────────────────────────────

void PostProcessVS(in  uint   id  : SV_VertexID,
                   out float4 pos : SV_Position,
                   out float2 uv  : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    pos  = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float SCurve(float x, float m, float strength)
{
    float t_lo = saturate(x / max(m, 0.001));
    float t_hi = saturate((x - m) / max(1.0 - m, 0.001));
    float s_lo = m * (t_lo * t_lo * (3.0 - 2.0 * t_lo));
    float s_hi = m + (1.0 - m) * (t_hi * t_hi * (3.0 - 2.0 * t_hi));
    float s    = lerp(s_lo, s_hi, step(m, x));
    return lerp(x, s, strength);
}

// ─── Youvan helpers ───────────────────────────────────────────────────────────

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
    return float3x3(A*inv_det, D*inv_det, G*inv_det,
                    B*inv_det, E*inv_det, H*inv_det,
                    C*inv_det, F*inv_det, I*inv_det);
}

// ─── Alpha chroma helpers ─────────────────────────────────────────────────────

float3 RGBtoHSV(float3 c)
{
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float  d = q.x - min(q.w, q.y);
    float  e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 HSVtoRGB(float3 c)
{
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

float HueBandWeight(float hue, float center)
{
    float d = abs(hue - center);
    d = min(d, 1.0 - d);
    return saturate(1.0 - d / CHROMA_BAND_WIDTH);
}

static const float kBandCenters[6] = {
      0.0 / 360.0,   // Red
     60.0 / 360.0,   // Yellow
    120.0 / 360.0,   // Green
    180.0 / 360.0,   // Cyan
    240.0 / 360.0,   // Blue
    300.0 / 360.0    // Magenta
};

// ─── Output transform helpers ─────────────────────────────────────────────────

float3 RGBtoOKLab(float3 c)
{
    float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    l = pow(max(l, 0.0), 1.0 / 3.0);
    m = pow(max(m, 0.0), 1.0 / 3.0);
    s = pow(max(s, 0.0), 1.0 / 3.0);
    return float3(
         0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
         1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
         0.0259040371 * l + 0.4072426305 * m - 0.4327467890 * s
    );
}

float3 OKLabtoRGB(float3 c)
{
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    l = l * l * l;  m = m * m * m;  s = s * s * s;
    return float3(
        +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    );
}

float3 OpenDRT(float3 x)
{
    const float grey = 0.18;
    float gc = pow(grey, OT_CONTRAST);
    float K  = gc * (1.0 - grey) / (grey - gc);
    float A  = 1.0 + K;
    float3 xc = pow(max(x, 0.0), OT_CONTRAST);
    return A * xc / (xc + K);
}

// ═══ Pixel shaders ════════════════════════════════════════════════════════════

// Pass 1 — Copy BackBuffer → CorrectiveBuf with white balance applied
float4 WhiteBalancePS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;  // data highway
    float3 c = col.rgb * float3(WB_R / 100.0, WB_G / 100.0, WB_B / 100.0);
    return float4(c, col.a);
}

// Passes 4, 9, 12, 14 — Snapshot CorrectiveBuf → CorrectiveSrcTex
float4 CopyBufToSrcPS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0) : SV_Target
{
    return tex2D(CorrectiveSamp, uv);
}

// Pass 2 — Youvan: zone mean statistics
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
        float3 rgb  = tex2Dlod(CorrectiveSamp, float4(kHalton[i], 0, 0)).rgb;
        float  luma = Luma(rgb);

        float in_zone = 0.0;
        if (zone == 0) in_zone = step(luma,                          YOUVAN_ZONE_DARK_MAX   / 100.0);
        if (zone == 1) in_zone = step(YOUVAN_ZONE_DARK_MAX  / 100.0, luma) * step(luma, YOUVAN_ZONE_BRIGHT_MIN / 100.0);
        if (zone == 2) in_zone = step(YOUVAN_ZONE_BRIGHT_MIN / 100.0, luma);

        sum += rgb * in_zone;
        w   += in_zone;
    }

    float fallback = (zone == 0) ? (YOUVAN_ZONE_DARK_MAX   / 100.0) * 0.5
                   : (zone == 1) ? 0.50
                   :               (1.0 + YOUVAN_ZONE_BRIGHT_MIN / 100.0) * 0.5;
    float3 mean = (w > 0.5) ? (sum / w) : float3(fallback, fallback, fallback);

    float4 prev  = tex2Dlod(ZoneSampler, float4((zone + 0.5) / 3.0, 0.5, 0, 0));
    float  speed = (prev.a < 0.001) ? 1.0 : (YOUVAN_LERP_SPEED / 100.0);

    return float4(lerp(prev.rgb, mean, speed), lerp(prev.a, 1.0, speed));
}

// Pass 3 — Youvan: build correction matrix B = M × A⁻¹
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

    float3x3 A = float3x3(
        v_dark.r,   v_mid.r,   v_bright.r,
        v_dark.g,   v_mid.g,   v_bright.g,
        v_dark.b,   v_mid.b,   v_bright.b
    );
    float3x3 M = float3x3(
        L_dark,   L_mid,   L_bright,
        L_dark,   L_mid,   L_bright,
        L_dark,   L_mid,   L_bright
    );

    float3x3 B = mul(M, Invert3x3(A));
    return float4(B[row][0], B[row][1], B[row][2], 1.0);
}

// Pass 5 — Youvan: apply hue correction
float4 ApplyOrthoPS(float4 pos : SV_Position,
                    float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;  // data highway

    float3 B0 = tex2D(MatrixSampler, float2(0.5 / 3.0, 0.5)).rgb;
    float3 B1 = tex2D(MatrixSampler, float2(1.5 / 3.0, 0.5)).rgb;
    float3 B2 = tex2D(MatrixSampler, float2(2.5 / 3.0, 0.5)).rgb;

    float3 corrected;
    corrected.r = dot(B0, col.rgb);
    corrected.g = dot(B1, col.rgb);
    corrected.b = dot(B2, col.rgb);

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

    float3 v_d = tex2D(ZoneSampler, float2(0.5 / 3.0, 0.5)).rgb;
    float3 v_m = tex2D(ZoneSampler, float2(1.5 / 3.0, 0.5)).rgb;
    float3 v_b = tex2D(ZoneSampler, float2(2.5 / 3.0, 0.5)).rgb;
    float L_d = Luma(v_d), L_m = Luma(v_m), L_b = Luma(v_b);
    float dev_d = max(abs(v_d.r-L_d), max(abs(v_d.g-L_d), abs(v_d.b-L_d)));
    float dev_m = max(abs(v_m.r-L_m), max(abs(v_m.g-L_m), abs(v_m.b-L_m)));
    float dev_b = max(abs(v_b.r-L_b), max(abs(v_b.g-L_b), abs(v_b.b-L_b)));
    float strength = saturate(max(dev_d, max(dev_m, dev_b)));

    float3 result = lerp(col.rgb, hue_only, strength);
    return float4(result, col.a);
}

// Pass 6 — Alpha zone: 1/8 res downsample
float4 ComputeLowFreqPS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    float2 px = float2(1.0 / BUFFER_WIDTH, 1.0 / BUFFER_HEIGHT);
    float3 rgb = 0.0;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2(-1.5, -1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2( 1.5, -1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2(-1.5,  1.5) * px, 0, 0)).rgb;
    rgb += tex2Dlod(CorrectiveSamp, float4(uv + float2( 1.5,  1.5) * px, 0, 0)).rgb;
    rgb *= 0.25;
    return float4(rgb, Luma(rgb));
}

// Pass 7 — Alpha zone: per-zone 32-bin luma histogram
float4 ComputeZoneHistogramPS(float4 pos : SV_Position,
                              float2 uv  : TEXCOORD0) : SV_Target
{
    int b        = int(pos.x);
    int zone     = int(pos.y);
    int zone_col = zone % 4;
    int zone_row = zone / 4;

    float u_lo      = float(zone_col) / 4.0;
    float v_lo      = float(zone_row) / 4.0;
    float bucket_lo = float(b)     / 32.0;
    float bucket_hi = float(b + 1) / 32.0;

    float count = 0.0;
    [loop] for (int sy = 0; sy < 10; sy++)
    [loop] for (int sx = 0; sx < 10; sx++)
    {
        float2 suv  = float2(u_lo + (sx + 0.5) / 10.0 * 0.25,
                             v_lo + (sy + 0.5) / 10.0 * 0.25);
        float  luma = tex2Dlod(LowFreqSamp, float4(suv, 0, 0)).a;
        count += (luma >= bucket_lo && luma < bucket_hi) ? 1.0 : 0.0;
    }

    float v    = count / 100.0;
    float prev = tex2Dlod(ZoneHistSamp,
        float4((float(b) + 0.5) / 32.0, (float(zone) + 0.5) / 16.0, 0, 0)).r;
    float h    = lerp(prev, v, (ZONE_HIST_LERP / 100.0) * (frametime / 10.0));
    return float4(h, h, h, 1.0);
}

// Pass 8 — Alpha zone: CDF walk → zone medians
float4 BuildZoneLevelsPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    int zone_x = int(pos.x);
    int zone_y = int(pos.y);
    int zone   = zone_y * 4 + zone_x;

    float2 prev_uv = float2((float(zone_x) + 0.5) / 4.0, (float(zone_y) + 0.5) / 4.0);
    float4 prev    = tex2Dlod(ZoneLevelsSamp, float4(prev_uv, 0, 0));
    float  speed   = (prev.r < 0.001) ? 1.0 : (ZONE_LERP_SPEED / 100.0) * (frametime / 10.0);

    float cumulative = 0.0;
    float median     = 0.5;
    float locked     = 0.0;

    [loop] for (int b = 0; b < 32; b++)
    {
        float bv   = float(b) / 32.0;
        float frac = tex2Dlod(ZoneHistSamp,
            float4((float(b) + 0.5) / 32.0, (float(zone) + 0.5) / 16.0, 0, 0)).r;
        cumulative += frac;

        float at50 = step(0.50, cumulative) * (1.0 - locked);
        median     = lerp(median, bv, at50);
        locked     = saturate(locked + at50);
    }

    return float4(lerp(prev.r, median, speed), 0.0, 0.0, 1.0);
}

// Pass 10 — Alpha zone: S-curve anchored at zone median
float4 ApplyContrastPS(float4 pos : SV_Position,
                       float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;  // data highway

    float luma = Luma(col.rgb);

    float zone_median = tex2D(ZoneLevelsSamp, uv).r;

    float t        = luma * 2.0 - 1.0;
    float tonal_w  = 1.0 - t * t;
    float strength = (ZONE_CURVE_STRENGTH / 100.0) * tonal_w;

    float new_luma = SCurve(luma, zone_median, strength);
    float scale    = new_luma / max(luma, 0.001);

    return float4(col.rgb * scale, col.a);
}

// Pass 11 — Alpha chroma: CDF walk on SatHistTex → per-band saturation medians
float4 BuildSatLevelsPS(float4 pos : SV_Position,
                        float2 uv  : TEXCOORD0) : SV_Target
{
    int   band  = int(pos.x);
    float row_v = (float(band) + 0.5) / 6.0;

    float4 prev  = tex2Dlod(SatLevelsSamp, float4((float(band) + 0.5) / 6.0, 0.5, 0, 0));
    float  speed = (prev.r < 0.001) ? 1.0 : (CHROMA_LERP_SPEED / 100.0) * (frametime / 10.0);

    float cumulative = 0.0;
    float median     = 0.5;
    float locked     = 0.0;

    [loop] for (int b = 0; b < 64; b++)
    {
        float bv   = float(b) / 64.0;
        float frac = tex2Dlod(SatHistSamp,
            float4((float(b) + 0.5) / 64.0, row_v, 0, 0)).r;
        cumulative += frac;

        float at50 = step(0.50, cumulative) * (1.0 - locked);
        median     = lerp(median, bv, at50);
        locked     = saturate(locked + at50);
    }

    return float4(lerp(prev.r, median, speed), 0.0, 0.0, 1.0);
}

// Pass 13 — Alpha chroma: per-hue-band saturation S-curve
float4 ApplyChromaPS(float4 pos : SV_Position,
                     float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;  // data highway

    float3 hsv = RGBtoHSV(col.rgb);

    float blended_median = 0.0;
    float total_w        = 0.0;

    [loop] for (int band = 0; band < 6; band++)
    {
        float w = HueBandWeight(hsv.x, kBandCenters[band]);
        float m = tex2Dlod(SatLevelsSamp, float4((float(band) + 0.5) / 6.0, 0.5, 0, 0)).r;
        blended_median += m * w;
        total_w        += w;
    }

    blended_median = (total_w > 0.001) ? blended_median / total_w : 0.5;

    float new_sat = SCurve(hsv.y, blended_median, CHROMA_CURVE_STRENGTH / 100.0);
    float3 result = HSVtoRGB(float3(hsv.x, new_sat, hsv.z));

    return float4(result, col.a);
}

// Pass 15 — Output transform: OpenDRT tone curve + OKLab highlight rolloff → BackBuffer
float4 OutputTransformPS(float4 pos : SV_Position,
                         float2 uv  : TEXCOORD0) : SV_Target
{
    float4 col    = tex2D(CorrectiveSrc, uv);
    if (pos.y < 1.0) return col;  // data highway

    float3 result = col.rgb;

    // Gamut compression (linear, before tone curve)
    float luma_gc = Luma(result);
    float under   = saturate(-min(result.r, min(result.g, result.b)) * 10.0);
    result        = lerp(result, float3(luma_gc, luma_gc, luma_gc), under);

    float gc_max  = max(result.r, max(result.g, result.b));
    float gc_min  = min(result.r, min(result.g, result.b));
    float sat_gc  = (gc_max > 0.001) ? (gc_max - gc_min) / gc_max : 0.0;
    float excess  = max(0.0, sat_gc - OT_SAT_MAX / 100.0) / (1.0 - OT_SAT_MAX / 100.0);
    float gc_amt  = excess * excess * (OT_SAT_BLEND / 100.0);
    result        = result + (gc_max - result) * gc_amt;

    // Black lift
    result = result * (1.0 - OT_BLACK_POINT / 100.0) + OT_BLACK_POINT / 100.0;

    // OpenDRT per-channel tone curve
    result = OpenDRT(result);

    // Highlight chroma compression (OKLab)
    float3 lab    = RGBtoOKLab(result);
    float hl_gate = smoothstep(0.65, 1.0, lab.x);
    lab.yz       *= (1.0 - hl_gate * OT_CHROMA_COMPRESS);
    result        = OKLabtoRGB(lab);

    return saturate(float4(result, col.a));
}

// ─── Technique ───────────────────────────────────────────────────────────────

technique OlofssonianRenderChain
{
    pass WhiteBalance
    {
        VertexShader = PostProcessVS;
        PixelShader  = WhiteBalancePS;
        RenderTarget = CorrectiveBuf;
    }
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
    pass CopyBufToSrc0
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyBufToSrcPS;
        RenderTarget = CorrectiveSrcTex;
    }
    pass ApplyOrtho
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyOrthoPS;
        RenderTarget = CorrectiveBuf;
    }
    pass ComputeLowFreq
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeLowFreqPS;
        RenderTarget = LowFreqTex;
    }
    pass ComputeZoneHistogram
    {
        VertexShader = PostProcessVS;
        PixelShader  = ComputeZoneHistogramPS;
        RenderTarget = ZoneHistTex;
    }
    pass BuildZoneLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildZoneLevelsPS;
        RenderTarget = ZoneLevelsTex;
    }
    pass CopyBufToSrc1
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyBufToSrcPS;
        RenderTarget = CorrectiveSrcTex;
    }
    pass ApplyContrast
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyContrastPS;
        RenderTarget = CorrectiveBuf;
    }
    pass BuildSatLevels
    {
        VertexShader = PostProcessVS;
        PixelShader  = BuildSatLevelsPS;
        RenderTarget = SatLevelsTex;
    }
    pass CopyBufToSrc2
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyBufToSrcPS;
        RenderTarget = CorrectiveSrcTex;
    }
    pass ApplyChroma
    {
        VertexShader = PostProcessVS;
        PixelShader  = ApplyChromaPS;
        RenderTarget = CorrectiveBuf;
    }
    pass CopyBufToSrc3
    {
        VertexShader = PostProcessVS;
        PixelShader  = CopyBufToSrcPS;
        RenderTarget = CorrectiveSrcTex;
    }
    pass OutputTransform
    {
        VertexShader = PostProcessVS;
        PixelShader  = OutputTransformPS;
    }
}
