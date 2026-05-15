// creative_values.fx — tune here
// Knobs ordered by pipeline firing position.

// ── INPUT ─────────────────────────────────────────────────────────────────────
// Adaptive inverse tone mapping. Expands Oklab chroma using the IQR-derived compression
// ratio — restoring chroma the game's tonemapper compressed. Luma is handled by zone
// S-curve. Works on any S-curve tonemapper. 0 = off. Start at 0.30–0.50.
#define INVERSE_STRENGTH  0.60

// Luma inverse — undoes ACES midtone boost (standard UE4/UE5 tonemapper).
// Darkens display values below L≈0.73 (ACES fixed point) back toward scene-linear.
// Highlights above L≈0.73 are unchanged — ACES shoulder is irrecoverable in SDR.
// Midtones darken ~0.5 stops at 1.0 — increase EXPOSURE to compensate after enabling.
// 0 = off. Try 0.30–0.60 after recalibrating EXPOSURE.
#define INVERSE_LUMA 0.60

// ── CORRECTIVE ────────────────────────────────────────────────────────────────
// BLACKS: black floor, direct linear value. 0.00 = passthrough. 0.05 = 5% floor.
// WHITES: white ceiling, direct linear value. 1.00 = passthrough. 0.95 = ARRI LogC3 usable ceiling.
#define BLACKS  0.00
#define WHITES  0.95

// Exposure in stops. 0 = neutral, +1 = one stop brighter, -1 = one stop darker.
// Applied as rgb * pow(2, EXPOSURE) before any zone or curve work.
// Sets where pixels sit tonally — which directly changes what every knob below "sees".
// Rule of thumb: dial until overall brightness feels right, then tune beneath.
#define EXPOSURE 0.2

// Film emulsion scatter from specular highlights — orange/amber fringe around
// brightest sources. Red dominates (deepest dye layer), green small, blue near-zero
// (yellow filter layer blocks blue from reaching base). White sources glow orange.
// Fires pre-curve (physical: camera negative, before any processing).
// 0 = off. 1.0 = Ektachrome-style aggressive.
#define HALATION  0.50
// Chromatic crossover threshold (ring luma units). Controls where the inner/outer
// halation colour character transitions. Lower = more orange overall.
// Range 0.02–0.20. Tune: raise until orange fringe looks physically correct.
#define HALATION_CROSSOVER  1.00

// Per-channel knee and toe offsets for the FilmCurve. Encodes the physical dye-layer
// cross-over character of different film stocks. 0 = passthrough. Range ±1.
// ±1.0 = ±0.10 stop shift in the auto knee/toe position.
// R knee < 0 = red compresses earlier (film-like warm shadows).
// B knee > 0 = blue compresses later (open highlights). B toe < 0 = cool toe.
// Negative values invert the S-curve direction for that channel.
#define CURVE_R_KNEE  -0.00
#define CURVE_B_KNEE  +0.00
#define CURVE_R_TOE   +0.00
#define CURVE_B_TOE   -0.00

// Primary color grade. Runs after FilmCurve.
// TEMP: positive = warm (R up, B down), negative = cool. Range ±100.
// TINT: positive = magenta (G down, R+B up slightly), negative = green. Range ±100.
// All default to 0 — passthrough. No output change at defaults.
#define SHADOW_TEMP     -0
#define SHADOW_TINT      0
#define MID_TEMP        +0
#define MID_TINT         0
#define HIGHLIGHT_TEMP  +0
#define HIGHLIGHT_TINT   0

// ── TONAL ─────────────────────────────────────────────────────────────────────
// Spatially-adaptive local tone mapping (R190). Guided filter base layer lifts areas
// darker than scene global key — shadow/midrange only, highlights unaffected —
// while restoring the detail layer so all texture is preserved. 0 = off. 0.50–1.00 = subtle. 1.50–2.50 = cinematic.
#define LOCAL_CONTRAST  1.00

// Local contrast / clarity (R190). Scales the guided filter detail layer before reconstruction.
// >0 = micro-contrast punch (Lightroom Clarity equivalent). <0 = spatial softening.
// 0 = off. 0.10–0.30 = subtle punch. 0.50 = strong. Independent of LOCAL_CONTRAST.
#define CLARITY  0.40

// Scales the adaptive zone S-curve strength. 0 = off. 1.0 = full. 2.0 = aggressive.
#define CONTRAST  0.75

// Scales the auto shadow lift. 0 = off. 1.0 = full designed lift.
// Raise for dark games with poor visibility, lower if lift feels too aggressive.
#define SHADOWS  0.75

// Soft luma push/pull in the highlight range (L > 0.55). +1.0 brightens highlights,
// -1.0 recovers blown highlights. Range ±1.0. Default 0.0 = passthrough.
#define HIGHLIGHTS  0.00

// ── CHROMA ────────────────────────────────────────────────────────────────────
// R183: pre-flash warm shadow cast. Fixed warm amber additive in deep shadows (L < 0.25),
// falls to zero at mid-gray. Models Deakins' colored negative pre-flash technique.
// Positive = warm amber, negative = cool blue-green. Range ±1.0. Default 0.0 = passthrough.
#define SHADOW_CAST  0.25

// Rod-vision blue-green bias + scotopic desaturation across mesopic range (luma 0–0.30).
// Hue: shifts a* (green) + b* (blue) toward 507nm rod peak — blue-green, not pure blue.
// Desat: lab.yz *= (1 − 0.12 × w) — rods are achromatic; deep shadows lose chroma.
// Neutrals unaffected (C=0 → zero shift). R117: transition widened luma 0.12 → 0.30.
// Recalibrate from scratch: try 0.6–0.8. 0 = off.
#define PURKINJE  0.60

// Per-band hue rotation in Oklab LCh. ±1.0 → ±36°. Positive = clockwise
// (Red→Yellow, Green→Cyan, Blue→Magenta). Default 0.0 = passthrough.
#define HUE_RED      0.00
#define HUE_YELLOW  -0.00
#define HUE_GREEN   -0.02
#define HUE_CYAN    +0.00
#define HUE_BLUE    -0.00
#define HUE_MAG      0.00

// Per-hue chroma lift strength. Acts as a gain near each hue band's scene mean —
// lift-only, vibrance-masked (already-saturated pixels are attenuated).
// Reach for this first — lifts flat/dull areas without pushing vivid pixels further.
// 0 = off. 1.0 = full designed lift.
#define VIBRANCE  0.10

// Per-band chroma scale in Oklab C. ±1.0 → ±80% chroma per hue band.
// Applied after Vibrance. Default 0.0 = passthrough.
#define SAT_RED    -0.05
#define SAT_YELLOW -0.05
#define SAT_GREEN   0.0
#define SAT_CYAN    0.0
#define SAT_BLUE    0.0
#define SAT_MAG     0.0

// Global chroma multiplier. -1.0 = greyscale, 0.0 = passthrough, +1.0 = 2× chroma.
// Applied uniformly — use after Vibrance when you want a deliberate global push.
#define SATURATION  0.00

// ── LOOK ──────────────────────────────────────────────────────────────────────
// Applied after all grading and chroma work — ACES LMT position.
// Kodak 2383 print emulsion: gentle shadow density bow, restrained shoulder,
// desaturates mids ~15%. 0 = off. 1 = full 2383.
#define PRINT_STOCK  0.85
// Skip the bleach step during print development — retains metallic silver alongside
// color dye. Desaturates shadows most (denser silver retention in unexposed areas),
// steepens midtone contrast, adds grit. Se7en, Saving Private Ryan, Traffic.
// 0 = off. 1 = full (near-monochrome shadows).
#define BLEACH_BYPASS  0.05

// R192: Printer lights — per-channel contact-printer exposure after all emulsion work.
// Mirrors film lab RGB printer head notation: 0 = neutral, ±12 = ±1 stop, 1 point = 1/12 stop.
// Push R up for warm cast, push B up for cool cast, etc.
// Applied after print stock and bleach bypass — post-LMT.
#define PRINTER_R   1.5
#define PRINTER_G   1.5
#define PRINTER_B   1.5

// ── OUTPUT ────────────────────────────────────────────────────────────────────
// Hollywood Black Magic dual-component model (R131):
//   A) Additive shimmer — highlight bloom into dark areas only (micro-lenslet).
//   B) Soft midtone overlay — gentle airbrushed smoothing, zero at blacks/whites.
// R132 polydisperse: per-channel scatter — red ×1.15, green ×1.00, blue ×0.85.
// 0 = off. 0.5 = subtle. 1.0 = Hollywood workhorse (HBM 1/2 grade). 1.5 = aggressive.
#define DIFFUSION  0.32

// R136: Selwyn 2383 granularity — three decorrelated dye layers (R:G:B = 1.00:0.80:1.50).
// Envelope sqrt(1−L_gamma): mathematically highest at pure black, tapers to zero at white.
// Perceived peak is in upper shadows — grain at pure black is invisible against the dark.
// Framerate-independent: turns over at ~24fps regardless of display fps.
// 0 = off. 1.0 = 2383 amplitude. 1.5 = pushed. 2.0 = stylistic.
#define GRAIN  0.0

// ── STAGE GATES ───────────────────────────────────────────────────────────────
// Bypass entire stages for A/B comparison. Not tuning knobs — leave at 100.
#define CORRECTIVE_STRENGTH  100
#define TONAL_STRENGTH       000
#define CHROMA_STRENGTH      000
#define LOOK_STRENGTH        000
