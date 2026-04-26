// creative_values.fx — tune here
// ZONE_STRENGTH / SHADOW_LIFT : 0 to 100 — 0 = passthrough, 100 = full effect
// EXPOSURE : 0 = dark (midgrey→0.20), 50 = neutral (→0.40), 100 = bright (→0.60)

#define EXPOSURE      1.10   // gamma: 1.0=passthrough, <1.0=brighten, >1.0=darken
#define ZONE_STRENGTH    0  // tonal zone contrast
#define CLARITY_STRENGTH 10  // 0–100; local midtone contrast (base/detail separation)
#define SHADOW_LIFT      5  // raise dark tones toward grey (0–100)

// Camera preset
//   0 — Soft base        (neutral, no true blacks/whites)
//   1 — ARRI ALEXA       (clean, neutral, wide latitude)
//   2 — Kodak Vision3    (warm, filmic, golden highlights)
//   3 — Sony Venice      (warm neutral, protected mids)
//   4 — Fuji Eterna 500  (cool, flat, green-leaning mids)
//   5 — Kodak 5219       (punchy, deep warm blacks)
#define PRESET              1    // camera preset (0–5)
#define GRADE_STRENGTH     50    // blend: 0=off, 100=full
#define CREATIVE_SATURATION 1.0  // >1 more vibrant, <1 muted
#define CREATIVE_CONTRAST   1.0  // >1 more punch, <1 flatter

// Inverse grade — pulled from chain (game curve is better; file kept for reference)
// #define INVERSE_STRENGTH 0

// Chroma lift
#define CHROMA_STRENGTH    10    // -100 to 100; per-hue saturation S-curve bend
#define DENSITY_STRENGTH   25    // 0–100; subtractive dye density (film body/weight)
