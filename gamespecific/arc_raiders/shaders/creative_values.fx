// creative_values.fx — tune here

// ── CORRECTIVE ──────────────────────────────────────────────────────────────
#define CORRECTIVE_STRENGTH 100  // 0=passthrough, 100=full
#define EXPOSURE            1.17 // gamma: 1.0=passthrough, <1.0=brighten, >1.0=darken

// ── TONAL ───────────────────────────────────────────────────────────────────
#define TONAL_STRENGTH      100  // 0=passthrough, 100=full
#define ZONE_STRENGTH        30  // 0–100; zone contrast S-curve
#define CLARITY_STRENGTH     25  // 0–100; local midtone contrast
#define SHADOW_LIFT          15  // 0–100; raise dark tones toward grey

// ── CHROMA ──────────────────────────────────────────────────────────────────
#define CHROMA_STRENGTH      10  // -100 to 100; per-hue saturation bend
#define DENSITY_STRENGTH     45  // 0–100; subtractive dye density
// Seong 2025 HK correction: coefficient derived for HSV sat (0–1), but grade.fx works in
// Oklab chroma (~0–0.4 range), so HK_STRENGTH=20 gives ~6–8% max correction, not 20%.
// To match the research's full 20% effect at peak saturation, set to ~60.
#define HK_STRENGTH          20  // 0–100; perceived-brightness surplus from saturation

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
