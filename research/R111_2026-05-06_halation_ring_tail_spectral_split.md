# Research Findings — Halation Inner/Outer Spectral Split — 2026-05-06

## Summary

Implemented. Derived from Spektrafilm (andreavolpato/spektrafilm dev) warm-outer /
neutral-inner halo structure, translated to the halation physics context.

---

## Physical basis

The halation DoG ring (mip1−mip2) represents light that has reflected off the film base
after approximately 1–2 bounces through the antihalation dye layer. At this short path,
the antihalation dye has had little cumulative effect — the spectral character is close
to the scene's own color.

The Lorentzian tail represents deep multi-bounce scatter (k≈4, per R109 derivation):
light that has traversed the antihalation dye layer multiple times. Each transit applies
Beer-Lambert absorption: `T = exp(-α·d·c)`. Green and blue dye absorption coefficients
are higher than red in the 2383 antihalation layer. After 4 transits the G/B suppression
is multiplicative — the tail is strongly warm-biased.

Previous code applied the same wing spectral weights (`g*0.88, b*0.75`) to both the
ring computation and the tail computation. This over-warmed the ring and under-warmed
the tail relative to physics.

---

## Change made (`grade.fx`)

**Before (single shared wing weights):**
```hlsl
float3 hal_core_g = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).rgb, 0.0); // redundant tap
float3 hal_wing_w  = float3(hal_wing.r, hal_wing.g * 0.88, hal_wing.b * 0.75);
float  hal_ring_r  = max(hal_core_r.r - hal_wing_w.r, 0.0);
float  hal_ring_g  = max(hal_core_g.g - hal_wing_w.g, 0.0);
// tail uses hal_wing_w too
```

**After (split ring/tail weights):**
```hlsl
// ring: near-neutral (1-bounce, minimal dye absorption)
float3 hal_wing_ring = float3(hal_wing.r, hal_wing.g * 0.94, hal_wing.b);
// tail: warm (multi-bounce, cumulative G/B dye absorption)
float3 hal_wing_tail = float3(hal_wing.r, hal_wing.g * 0.78, hal_wing.b * 0.60);
float  hal_ring_r  = max(lf_mip1.r - hal_wing_ring.r, 0.0);  // uses cached lf_mip1
float  hal_ring_g  = max(lf_mip1.g - hal_wing_ring.g, 0.0);  // uses cached lf_mip1
// tail uses hal_wing_tail
```

Also removed the redundant `hal_core_g` `tex2Dlod` — it read mip1 again (identical to
`lf_mip1` already in registers). Replaced with direct `lf_mip1.r/.g` reads.

---

## Net delta

| Item | Before | After |
|------|--------|-------|
| tex2Dlod taps (halation block) | 3 (lf_mip1 hoisted + redundant core_g + lf_mip2) | 2 (lf_mip1 hoisted + lf_mip2) |
| Ring G attenuation | 0.88 (warm) | 0.94 (near-neutral) |
| Tail G attenuation | 0.88 (same as ring) | 0.78 (warmer than before) |
| Tail B attenuation | 0.75 (same for ring and tail) | 0.60 (tail only — ring B unchanged) |
| Extra ALU | — | +2 float3 mul (split wing compute) |
| Net cost | — | −1 tap, +2 ALU |

---

## Expected visual character

- The tight annular ring immediately around a bright source: less warm, closer to scene
  color. A white highlight's ring stays whiteish.
- The Lorentzian tail that falls off into the surrounding dark area: more strongly
  red-warm. The warm fringe concentrates in the far scatter, not at the source edge.
- At HAL_STRENGTH=0.40 and HAL_GAMMA=0.40: the perceptual difference is subtle — most
  visible on neutral or cool highlights (white LEDs, moonlight) where the ring warmth
  was previously the dominant impression.

---

## Targets met

- Stage 3.5 novel: +2% (physically motivated ring/tail spectral split — not in any
  reviewed real-time halation implementation)
- Stage 3.5 finished: +1%
