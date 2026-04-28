# R14 — Temporal Stability: Findings

**Date:** 2026-04-28  
**Status:** Research complete — adaptive formula viable, no new passes required

---

## 1. Internal Audit

**Current zone smoothing (corrective.fx `SmoothZoneLevels`, lines 496–499):**
```hlsl
float4 current = tex2D(CreativeZoneLevelsSamp, uv);
float4 prev    = tex2D(ZoneHistorySamp, uv);
float  speed   = (prev.r < 0.001) ? 1.0 : (ZONE_LERP_SPEED / 100.0);
return lerp(prev, current, speed);
```
Fixed-rate per-frame lerp of 8% (ZONE_LERP_SPEED=8).

**Current chroma smoothing (corrective.fx `UpdateHistory`, lines 534–538):**
```hlsl
float new_mean = lerp(prev.r, mean,   LERP_SPEED / 100.0);
float new_std  = lerp(prev.g, stddev, LERP_SPEED / 100.0);
float new_wsum = lerp(prev.b, sum_w,  LERP_SPEED / 100.0);
```
Fixed-rate 8% per frame.

**Problem:** At 60 fps, 8% per frame converges with τ ≈ 12 frames (~0.2 s). This is adequate for slow scene changes but too slow for scene cuts and too fast for stable ambient lighting.

---

## 2. Literature

### 2.1 Eye Adaptation — Narkowicz 2016 (Automatic Exposure)

**Source:** Narkowicz, K. "Automatic Exposure." Personal blog, 2016.

Frame-rate independent eye adaptation:

$$L_t = L_t + (L - L_t)\left(1 - e^{-\Delta t \cdot \tau}\right)$$

where $\Delta t$ is elapsed frame time (ms) and $\tau$ is the adaptation time constant. For 60 fps (Δt ≈ 16 ms) and τ = 0.008 (1/LERP_SPEED), this reduces to the existing lerp. The formula generalises to variable frame rates without behaviour change.

**Key observaton:** Narkowicz notes eye dark adaptation is **4–5× slower** than light adaptation. For auto-exposure, separate τ values for brightening vs. darkening produce more natural-looking adaptation.

### 2.2 Magnitude-Adaptive Temporal Filter (Signal Processing)

**Principle:** The blend speed of an exponential moving average (EMA) can be made proportional to the magnitude of the current frame delta. This is a standard technique in real-time signal processing called **variable-rate EMA** or **adaptive EMA**.

Formula:
$$\text{speed} = \text{base} \cdot (1 + k \cdot |\Delta|)$$

where base = LERP_SPEED/100, $\Delta = |\text{current} - \text{prev}|$, and k is the sensitivity coefficient.

**Behaviour:**
- Stable scene (Δ ≈ 0): speed = base (normal smoothing)
- Scene cut or explosion (Δ = 0.10): at k=10, speed = base × 2.0 (double-rate convergence)
- Hard cut (Δ ≈ 0.50): speed ≈ base × 6 (very fast convergence, near-instant reset)

This replaces the existing first-frame `(prev.r < 0.001) ? 1.0 : base` gate with a self-regulating continuous formula.

### 2.3 Asymmetric Adaptation

**Principle (from Narkowicz and photoreceptor biology):** The visual system adapts to increased luminance faster than it adapts to decreased luminance. In our context:
- Zone history going brighter: increase blend speed (scene got brighter → adapt quickly)
- Zone history going darker: reduce blend speed (eye dark adaptation is slow)

Gate-free asymmetric formulation:
$$\text{asym} = 1 + a \cdot \frac{\Delta}{\max(|\Delta|, \epsilon)}$$

where $a \approx 0.3$ — this equals 1.3 when brightening, 0.7 when darkening, 1.0 at Δ=0. The division `Δ/|Δ|` is sign(Δ), which is an arithmetic operation in SPIR-V with no branch.

---

## 3. Proposed Replacements

### Finding 1 — Magnitude-Adaptive Zone Smoothing [PASS]

**Current:**
```hlsl
float  speed = (prev.r < 0.001) ? 1.0 : (ZONE_LERP_SPEED / 100.0);
return lerp(prev, current, speed);
```

**Proposed:**
```hlsl
float4 delta = abs(current - prev);
float  base  = ZONE_LERP_SPEED / 100.0;
float  speed = saturate(base * (1.0 + 10.0 * delta.r));
return lerp(prev, current, speed);
```

- Gate-free: replaces `(prev.r < 0.001) ? 1.0 : base` with continuous formula.
- Self-initialises: on first frame, prev = 0 and current is the computed level. delta.r ≈ 0.3–0.5, giving speed ≈ 4–6× base → near-instant convergence on first frame, matching the intent of the old gate.
- Scene cut: large delta → fast blend, converges in 1–3 frames.
- Stable: small delta → slow blend, preserves smoothing behaviour.
- The coefficient `10.0` means: Δ=0.10 (typical cut) doubles the blend speed; Δ=0.50 gives 6× speed. Recommended value; could be hardcoded at 10 or exposed as `TEMPORAL_SENSITIVITY` in creative_values.fx.
- Injection point: `corrective.fx:496–499`.

### Finding 2 — Magnitude-Adaptive Chroma Smoothing [PASS]

**Current:**
```hlsl
float new_mean = lerp(prev.r, mean,   LERP_SPEED / 100.0);
float new_std  = lerp(prev.g, stddev, LERP_SPEED / 100.0);
float new_wsum = lerp(prev.b, sum_w,  LERP_SPEED / 100.0);
```

**Proposed:**
```hlsl
float delta_c = abs(mean - prev.r);
float speed_c = saturate(LERP_SPEED / 100.0 * (1.0 + 10.0 * delta_c));
float new_mean = lerp(prev.r, mean,   speed_c);
float new_std  = lerp(prev.g, stddev, speed_c);
float new_wsum = lerp(prev.b, sum_w,  speed_c);
```

- Adaptive on chroma mean change `delta_c`.
- `speed_c` is scalar (computed once, applied to all three channels) — no extra ALU per channel.
- Injection point: `corrective.fx:534–538`.

### Finding 3 — Asymmetric Zone Adaptation [PASS — Optional enhancement]

Add asymmetric adaptation on top of F1:

```hlsl
float4 delta = current - prev;            // signed
float4 abs_d = abs(delta);
float  base  = ZONE_LERP_SPEED / 100.0;
float  asym  = 1.0 + 0.3 * delta.r / max(abs_d.r, 0.001);  // sign(delta.r)
float  speed = saturate(base * (1.0 + 10.0 * abs_d.r) * asym);
return lerp(prev, current, speed);
```

- When scene brightens (delta.r > 0): asym = 1.3 → 30% faster
- When scene darkens (delta.r < 0): asym = 0.7 → 30% slower
- Gate-free: `delta.r / max(abs_d.r, 0.001) = sign(delta.r)` is arithmetic (no branch).
- Biological motivation: photopic adaptation 5× faster than scotopic (Narkowicz). The 0.3 coefficient is conservative (30% asymmetry vs. the biological 5×) because our video game context has artificial cuts that are harder to separate from natural dark adaptation.

---

## 4. Strategic Assessment

| Finding | Gate-free | New uniforms | Visual impact |
|---------|-----------|-------------|---------------|
| F1 — Adaptive zone speed | PASS | None | High (cuts, explosions stable) |
| F2 — Adaptive chroma speed | PASS | None | Medium (chroma pumping reduced) |
| F3 — Asymmetric adaptation | PASS | None | Low (subtle natural feel) |

**Recommendation:** F1 + F2 together as a single commit — they share the same pattern and the code change is small. F3 is optional polish for a later pass.

**Compatibility with FRAME_COUNT initialization:** The existing `(prev.r < 0.001) ? 1.0 : base` initialization gate is replaced by the magnitude-adaptive formula, which self-initialises on first frame (large delta ≈ large speed ≈ immediate convergence). No separate initialization guard needed.

**Not implemented:** Frame-rate-independent exponential decay (`1 - exp(-frametime * τ)`) would require a `frametime` uniform. While vkBasalt/ReShade supports this via `source = "frametime"`, the additional per-frame branch is unnecessary at fixed 60 fps. If variable frame rate support is needed in future, adding the uniform is a one-line change.
