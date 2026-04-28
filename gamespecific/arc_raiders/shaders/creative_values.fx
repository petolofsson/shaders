// creative_values.fx — tune here

// ── EXPOSURE ─────────────────────────────────────────────────────────────────
// First thing that runs. Applied as pow(rgb, EXPOSURE) before any zone or curve
// work. Sets where pixels sit tonally — which directly changes what every knob
// below "sees". Raising this (>1.0) darkens; lowering (<1.0) brightens.
// Rule of thumb: dial EXPOSURE until overall brightness feels right, then tune
// the contrast/chroma knobs beneath.
#define EXPOSURE            1.02

// ── ZONE CONTRAST ────────────────────────────────────────────────────────────
// ZONE_STRENGTH and RANK_CONTRAST_STRENGTH are two modes of the same operation.
// ZONE_STRENGTH sets the S-curve depth, pivoted at each spatial zone's median.
// RANK_CONTRAST_STRENGTH blends in a rank-based version of that same curve:
//   0  = pure median S-curve (classic zone contrast)
//   100 = full rank/CDF equalization (more aggressive, flattens skewed zones)
// The useful range for RANK is 10–40 — enough to correct asymmetric zones
// without looking over-processed. Both knobs amplify each other; raising one
// means you may want to lower the other to keep the same overall punch.
// Also note: higher EXPOSURE lifts pixels into the midtone range where the
// S-curve is most active, so contrast feels stronger at the same knob values.
#define ZONE_STRENGTH        40
#define RANK_CONTRAST_STRENGTH 15

// SPATIAL_NORM_STRENGTH runs after the zone S-curve. Where ZONE_STRENGTH
// increases contrast within each zone, SPATIAL_NORM pulls zones toward each
// other — dark areas lift slightly, bright areas compress slightly, all toward
// the global scene key. Raising both simultaneously can feel flat; typically
// keep one dominant. At the default of 15 the effect is subtle balancing.
#define SPATIAL_NORM_STRENGTH 10

// CLARITY adds local midtone contrast at pixel scale — finer-grained than zones.
// It stacks on top of zone work. Keep modest: above 35 it starts to feel
// sharpened rather than film-like.
#define CLARITY_STRENGTH     30

// SHADOW_LIFT raises the toe. Interacts with EXPOSURE: lowering EXPOSURE already
// lifts shadows upward through the gamma; SHADOW_LIFT then pushes the toe further.
// If blacks feel milky lower one or both. At 16 the lift is gentle and film-like.
#define SHADOW_LIFT          18

// ── CHROMA ───────────────────────────────────────────────────────────────────
// These three run in sequence: DENSITY compacts chroma first, CHROMA bends what
// remains per hue, then HK reacts to the final chroma level to add perceived
// brightness. Lower DENSITY = more chroma = stronger HK response.
//
// DENSITY_STRENGTH — subtractive dye density (film-like colour compaction).
//   Desaturates uniformly before other chroma work. The "film stock body" feel.
// CHROMA_STRENGTH — per-hue saturation bend after density.
//   Positive bends all hues more vibrant; negative mutes. Fine-tune hue
//   saturation balance here, not overall colour volume.
// HK_STRENGTH — Hellwig 2022 hue-dependent brightness boost from saturation.
//   Cyan/blue get the most correction (~1.2×), yellow the least (~0.3×).
//   At 12 it matches the perceptual parity of the previous model on average;
//   raise toward 20–25 for a stronger psychophysical effect.
#define DENSITY_STRENGTH     40
#define CHROMA_STRENGTH      15
#define HK_STRENGTH          15

// ── FILM GRADE ───────────────────────────────────────────────────────────────
// PRESET picks the film stock character (log matrix, tints, toe/shoulder shape,
// cross-over behaviour). GRADE_STRENGTH gates how much is applied — 0 = off.
// CREATIVE_SATURATION and CREATIVE_CONTRAST are final-stage multipliers: they
// act on the graded result, so they amplify whatever the preset already did.
// Raise GRADE_STRENGTH before touching the final two; otherwise you're scaling
// an effect that isn't on yet.
//   0 — Soft base        (neutral, no true blacks/whites)
//   1 — ARRI ALEXA       (clean, neutral, wide latitude)
//   2 — Kodak Vision3    (warm, filmic, golden highlights)
//   3 — Sony Venice      (warm neutral, protected mids)
//   4 — Fuji Eterna 500  (cool, flat, green-leaning mids)
//   5 — Kodak 5219       (punchy, deep warm blacks)
#define GRADE_STRENGTH        0
#define PRESET                1
#define CREATIVE_SATURATION 1.00
#define CREATIVE_CONTRAST   1.00

// ── STAGE GATES ──────────────────────────────────────────────────────────────
// Bypass entire stages for A/B comparison. Not tuning knobs — leave at 100.
#define CORRECTIVE_STRENGTH 100
#define TONAL_STRENGTH      100
