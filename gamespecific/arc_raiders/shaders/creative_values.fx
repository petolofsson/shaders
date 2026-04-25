// creative_values.fx — tune here
// ZONE / CHROMA / SHADOW_LIFT : 0 to 100 — 0 = passthrough, 100 = full effect

#define ZONE_STRENGTH   30  // tonal zone contrast
#define CHROMA_STRENGTH 20  // per-hue saturation lift
#define SHADOW_LIFT     25  // raise dark tones toward grey (0–100)

// Camera preset
//   0 — Soft base        (neutral, no true blacks/whites)
//   1 — ARRI ALEXA       (clean, neutral, wide latitude)
//   2 — Kodak Vision3    (warm, filmic, golden highlights)
//   3 — Sony Venice      (warm neutral, protected mids)
//   4 — Fuji Eterna 500  (cool, flat, green-leaning mids)
//   5 — Kodak 5219       (punchy, deep warm blacks)
#define PRESET              1    // camera preset (0–5)
#define GRADE_STRENGTH    100    // blend: 0=off, 100=full
#define CREATIVE_SATURATION 1.0  // >1 more vibrant, <1 muted
#define CREATIVE_CONTRAST   1.0  // >1 more punch, <1 flatter
