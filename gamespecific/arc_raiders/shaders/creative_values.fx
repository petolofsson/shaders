// creative_values.fx — tune here

// ── CORRECTIVE ──────────────────────────────────────────────────────────────
#define CORRECTIVE_STRENGTH 100  // 0=passthrough, 100=full
#define EXPOSURE            1.17 // gamma: 1.0=passthrough, <1.0=brighten, >1.0=darken

// ── TONAL ───────────────────────────────────────────────────────────────────
#define TONAL_STRENGTH      100  // 0=passthrough, 100=full
#define ZONE_STRENGTH        30  // 0–100; zone contrast S-curve
#define RANK_CONTRAST_STRENGTH 30  // 0–100; rank-based zone contrast blend (0=median S-curve, 100=CDF equalization)
#define SPATIAL_NORM_STRENGTH 20  // 0–100; zone-to-key normalization (between-zone luminance balance)
#define CLARITY_STRENGTH     25  // 0–100; local midtone contrast
#define SHADOW_LIFT          15  // 0–100; raise dark tones toward grey

// ── CHROMA ──────────────────────────────────────────────────────────────────
#define CHROMA_STRENGTH      10  // -100 to 100; per-hue saturation bend
#define DENSITY_STRENGTH     45  // 0–100; subtractive dye density
// Hellwig 2022 H-K model: hue-dependent f(h)*C^0.587. f(h) ∈ [0.25, 1.21] (cyan peak, yellow trough).
// Value 12 ≈ perceptual parity with previous Seong model at average scene saturation.
// Increase toward 20–25 for stronger correction (more accurate to full psychophysical effect).
#define HK_STRENGTH          12  // 0–100; perceived-brightness surplus from saturation

// ── FILM GRADE ──────────────────────────────────────────────────────────────
// Camera preset
//   0 — Soft base        (neutral, no true blacks/whites)
//   1 — ARRI ALEXA       (clean, neutral, wide latitude)
//   2 — Kodak Vision3    (warm, filmic, golden highlights)
//   3 — Sony Venice      (warm neutral, protected mids)
//   4 — Fuji Eterna 500  (cool, flat, green-leaning mids)
//   5 — Kodak 5219       (punchy, deep warm blacks)
#define GRADE_STRENGTH        0  // 0=passthrough, 100=full
#define PRESET                1  // camera preset (0–5)
#define CREATIVE_SATURATION 1.00 // >1 more vibrant, <1 muted
#define CREATIVE_CONTRAST   1.00 // >1 more punch, <1 flatter
