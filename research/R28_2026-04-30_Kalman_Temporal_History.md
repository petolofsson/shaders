# R28 — Kalman Filter Temporal History
**Date:** 2026-04-30
**Type:** Proposal
**ROI:** High — drop-in replacement, zero extra passes, provably optimal

---

## Problem

Both history passes use an adaptive EMA with a heuristic speed multiplier:

**`corrective.fx:254` — SmoothZoneLevelsPS:**
```hlsl
float speed = saturate(base * (1.0 + 10.0 * abs(current.r - prev.r)));
return lerp(prev, current, speed);
```

**`corrective.fx:292` — UpdateHistoryPS:**
```hlsl
float speed_c = saturate(LERP_SPEED / 100.0 * (1.0 + 10.0 * delta_c));
```

The `1.0 + 10.0 * abs(delta)` multiplier is a tuning guess. It reacts faster on large
changes but the `10.0` constant has no theoretical basis — it was tuned by eye. It also
has a cold-start problem: on the first frame, `prev` is zero, delta is large, speed
clamps to 1.0, and the first measurement is accepted wholesale with no smoothing.

---

## Proposed replacement — scalar Kalman filter

A Kalman filter tracks the same quantity but maintains an **error variance P** alongside
the estimate, giving it principled, self-calibrating speed adaptation:

```
Predict:  P_pred  = P + Q
Update:   K       = P_pred / (P_pred + R)
          x̂_new   = x̂ + K * (measurement - x̂)
          P_new   = (1 - K) * P_pred
```

Where:
- **Q** — process noise: how much does the true scene value change per frame?
- **R** — measurement noise: how noisy is each frame's zone/chroma estimate?
- **K** — Kalman gain: adapts automatically. Large P → large K (fast response). Small P → small K (smooth).

Properties the heuristic EMA lacks:
- Cold-start: initialize P large → K≈1 on frame 1 → fast lock-on, then slows automatically
- Scene cut: large innovation drives P up → K increases → fast re-lock, no tuning constant needed
- Steady state: P converges to a fixed point determined by Q/R ratio — provably optimal
- No magic constants: Q and R are physically meaningful (expected frame-to-frame variance)

---

## Storage

**ZoneHistoryTex** (4×4 RGBA16F): currently `.r=median, .g=p25, .b=p75, .a=1.0`
→ repurpose `.a` for **P** (zone median error variance). Apply Kalman to median only;
keep EMA for p25/p75 (less critical, don't need the overhead).

**ChromaHistoryTex** (8×4 RGBA16F): currently `.r=mean, .g=std, .b=wsum, .a=1.0`
→ repurpose `.a` for **P** (chroma mean error variance). Apply Kalman to mean;
keep EMA for std and wsum.

No new textures. No new passes. The `.a=1.0` sentinel is unused beyond marking the
texture as written — both passes already check `pos.y >= 1.0` as their write guard.

---

## Initial P value

P must be initialized large so K≈1 on first frame. Since `.a` starts at 0.0 (unwritten
texture), treat `P < epsilon` as cold-start and substitute `P = P_init`:

```hlsl
float P = (prev.a < 0.001) ? 1.0 : prev.a;
```

---

## Proposed HLSL (SmoothZoneLevelsPS)

```hlsl
float4 SmoothZoneLevelsPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 current = tex2D(CreativeZoneLevelsSamp, uv);
    float4 prev    = tex2D(ZoneHistorySamp, uv);

    // Kalman: median (.r) — cold-start if P uninitialized
    float  P_prev  = (prev.a < 0.001) ? 1.0 : prev.a;
    float  P_pred  = P_prev + KALMAN_Q_ZONE;
    float  K       = P_pred / (P_pred + KALMAN_R_ZONE);
    float  median  = prev.r + K * (current.r - prev.r);
    float  P_new   = (1.0 - K) * P_pred;

    // EMA: p25/p75 — less critical, keep cheap
    float base = ZONE_LERP_SPEED / 100.0;
    float p25  = lerp(prev.g, current.g, base);
    float p75  = lerp(prev.b, current.b, base);

    return float4(median, p25, p75, P_new);
}
```

---

## Research questions for web search

1. What are typical Q and R values for real-time luminance tracking in video? Are there
   published recommendations for scene-adaptive Kalman tuning (e.g. Bayesian scene cut
   detection)?
2. Is there a closed-form steady-state Kalman gain for constant Q/R that could replace
   the recursive P update (simpler shader, same steady-state result)?
3. Has Kalman filtering been applied to real-time tone mapping or auto-exposure in the
   graphics literature? Any 2023–2026 papers?

---

## Success criteria

- `SmoothZoneLevelsPS` and `UpdateHistoryPS` rewritten with Kalman
- No new textures, no new passes
- Cold-start: frame-1 output is the raw measurement (K≈1), same as current
- Steady state: smoother than current EMA at equivalent apparent speed
- Scene cut: faster re-lock than current without overshooting
- ZONE_LERP_SPEED and LERP_SPEED defines retired; replaced by KALMAN_Q/R constants
  in `creative_values.fx` (or hardcoded if values prove universal)
