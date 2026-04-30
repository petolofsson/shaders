# R32 — Alpha Channel Data Highway Extension
**Date:** 2026-04-30
**Type:** Proposal
**ROI:** Low — doubles highway bandwidth at zero GPU cost, only useful if highway fills up

---

## Problem

The data highway (row y=0 of BackBuffer) currently uses RGB channels only:

| Pixels | Channel | Content |
|--------|---------|---------|
| 0–127  | R       | Luma histogram bins (128 bins, [0,1] fractions) |
| 128    | R       | Post-corrective luma mean |
| 129    | R       | (unused — broken smoothing removed in R27) |
| 130–193| R,G,B   | Hue histogram (64 bins across 3 channels) |

The alpha channel of every highway pixel is **completely unused**. The BackBuffer is
`B8G8R8A8_UNORM` — the alpha byte is transmitted and preserved between passes.

---

## Proposed extension

Use the alpha channel of highway pixels as a second data bus. This doubles available
bandwidth from ~192 scalars to ~384 scalars with zero additional GPU cost.

**Immediate candidate — zone_std and zone_log_key:**

Currently grade.fx reads all 16 zone medians via 16 separate texture taps, then computes
zone_std and zone_log_key from those values on every invoked pixel of ColorTransformPS.
These are global scalars (same value for every pixel in the frame). They could be
pre-computed in corrective.fx Pass 4 (SmoothZoneLevels) and written into the alpha
channel of highway pixels 0 and 1:

```hlsl
// corrective.fx — end of SmoothZoneLevels, after computing all 16 zone medians:
// (requires a gather pass or a dedicated single pixel write)
if (pos.x < 1.0 && pos.y < 1.0)
{
    // highway pixel 0 alpha = zone_std (pre-computed)
    // highway pixel 1 alpha = zone_log_key (pre-computed)
}
```

grade.fx would then read:
```hlsl
float zone_std     = tex2D(BackBuffer, highway_uv(0)).a;
float zone_log_key = tex2D(BackBuffer, highway_uv(1)).a;
```

Saving 16 ZoneHistorySamp reads + full-resolution zone_std/zone_log_key arithmetic.

---

## Prerequisite verification

**Must confirm before implementing:** does vkBasalt preserve the alpha channel of the
BackBuffer between effects and between passes within the same effect?

- Within an effect (corrective.fx passes 1–6): the Passthrough pass reads and re-emits
  `tex2D(BackBuffer, uv)` — a float4, which includes alpha. Alpha should survive.
- Between effects (corrective → grade): vkBasalt does not clear the BackBuffer between
  effects (confirmed by source review in R27). Alpha should survive.
- The game's own alpha output: most games render with alpha=1.0 or alpha=0.0 uniformly.
  The highway rows are in the top pixel row (y=0) which games don't intentionally render
  meaningful alpha into. Low risk of conflict.

**Test:** write a known value (e.g. 0.42) into highway pixel alpha in corrective Passthrough.
Read it back in grade.fx ColorTransformPS. If the value arrives intact, the channel is safe.

---

## RGBM / extended range encoding (separate idea)

The alpha channel could also carry a **scale factor** to encode HDR values through the
8-bit BackBuffer. Format: `rgb = hdr.rgb / scale, a = scale / max_scale`. Downstream
unpacks: `hdr.rgb = rgb * a * max_scale`.

For our pipeline this is not needed — we intentionally clip at `saturate()` (SDR by
construction). But if the pipeline ever needs to pass a high-dynamic-range intermediate
between effects without a dedicated RGBA16F render target, this is the mechanism.

**Not recommended for current pipeline** — our internal RGBA16F textures already provide
the range we need within an effect.

---

## Risks

**Alpha bleed from game content:** in row y=0, the game's framebuffer alpha is whatever
the game wrote. If the game writes non-uniform alpha at y=0, a pre-write guard is needed
(read game alpha, discard it, write our value). The highway write already owns those
pixels for RGB — same guard applies to alpha.

**8-bit precision:** BackBuffer alpha is 8-bit UNORM — 256 levels. For zone_std (typical
range 0.02–0.35) this gives ~0.001 precision, which is sufficient. For zone_log_key
(range ~0.05–0.9) same conclusion.

---

## Success criteria

- Alpha channel passthrough confirmed experimentally
- zone_std and zone_log_key written to highway alpha in corrective, read in grade
- 16 ZoneHistorySamp reads in grade.fx ColorTransformPS eliminated
- No new passes, no new textures, no visual change (values are identical, just precomputed)
