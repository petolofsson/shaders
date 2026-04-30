# R34 — Kalman Filter for PercTex Percentiles
**Date:** 2026-04-30
**Type:** Proposal
**ROI:** High — same fix as R28, same pass-count cost (zero), removes the last EMA
in the temporal stack; cold-start and scene-cut improvement to FilmCurve anchor

---

## Problem

`analysis_frame.fx` smooths the luma histogram temporally in two passes before the CDF
walk computes p25/p50/p75:

**Pass 5 — LumHistSmoothPS:**
```hlsl
return float4(lerp(prev, raw, (LERP_SPEED / 100.0) * (frametime / 10.0)), 0.0, 0.0, 1.0);
```

**Pass 6 — SatHistSmoothPS:** same formula.

`LERP_SPEED = 4.3` (hardcoded `#define`). At 60fps (frametime ≈ 16.7ms):
```
alpha = (4.3 / 100) * (16.7 / 10) = 0.0718
```

Half-life ≈ 9 frames. The `frametime / 10.0` factor provides crude frame-rate
compensation, but the denominator `10.0` (targeting 10ms = 100fps) is a magic constant.

The `CDFWalkPS` (Pass 7) then reads the temporally-smoothed histogram and computes
p25/p50/p75. The output is written directly to `PercTex` with no further smoothing —
the temporal character of the percentiles is entirely determined by the histogram EMA.

**Problems inherited from R28 pattern:**
- **Cold-start:** first frame, prev = 0 (uninitialized texture), lerp converges slowly
  from 0 to the true histogram rather than locking on immediately.
- **Scene-cut:** large instantaneous histogram change is damped by the EMA — FilmCurve
  anchors (p25/p50/p75) lag the true scene key by several frames, causing incorrect
  tone mapping for 9+ frames after each cut.
- **Magic constant:** `10.0` in `frametime / 10.0` assumes a target framerate of 100fps;
  at 30fps the alpha doubles, making the filter much looser. Not a principled design.

---

## Proposed replacement

Apply Kalman directly to the per-frame percentile outputs. The histogram smoothing passes
(LumHistSmooth, SatHistSmooth) are retained as-is — they provide intra-frame stability
across the 64-bin histogram. Kalman is applied to the OUTPUTS of CDFWalkPS rather than
to the histogram bins.

**Key insight:** `PercTex.a` currently stores `saturate(p75 − p25)` = IQR. This value
is used by `pro_mist.fx` and nothing else reads it from `.a` — both could compute IQR
inline as `perc.b − perc.r`. Freeing `.a` for Kalman P costs no extra storage.

**Proposed CDFWalkPS:**

```hlsl
float4 CDFWalkPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // CDF walk — unchanged, produces raw p25/p50/p75 from smoothed histogram
    float cumul = 0.0;
    float p25 = 0.25, p50 = 0.50, p75 = 0.75;
    // ... [existing walk loop — unchanged] ...

    // Kalman: filter p25/p50/p75 — P in .a, cold-start when uninitialized
    float4 prev = tex2D(PercSamp, float2(0.5, 0.5));
    float  P    = (prev.a < 0.001) ? 1.0 : prev.a;
    float  P_pred = P + KALMAN_Q_PERC;
    float  K      = P_pred / (P_pred + KALMAN_R_PERC);
    float  new_p25 = prev.r + K * (p25 - prev.r);
    float  new_p50 = prev.g + K * (p50 - prev.g);
    float  new_p75 = prev.b + K * (p75 - prev.b);
    float  P_new   = (1.0 - K) * P_pred;

    return float4(new_p25, new_p50, new_p75, P_new);
}
```

**Reads and writes to PercTex in the same pass:** valid in vkBasalt/ReShade — the read
(`tex2D(PercSamp, ...)`) returns the previous frame's value; the write (`SV_Target`)
produces the current frame's output. Same pattern as R28's ZoneHistoryTex.

---

## Downstream changes

**`grade.fx`:** currently reads `perc.a` for IQR nowhere (already uses `perc.b - perc.r`
in eff_p75 path). No change needed.

**`pro_mist.fx`:** reads `perc.a` as IQR:
```hlsl
float iqr = perc.a;
```
Change to:
```hlsl
float iqr = perc.b - perc.r;
```
One line. No behavioral change — the value is identical (was `saturate(p75-p25)`,
saturation is implicit since p75 ≥ p25 by construction).

---

## Kalman constants

Percentile signals are slower-moving than zone medians (averaging over the full frame
rather than a 1/16 region). Recommended:
```hlsl
#define KALMAN_Q_PERC  0.00005   // process noise: percentiles change slowly
#define KALMAN_R_PERC  0.005     // measurement noise: CDFwalk has some bin-granularity noise
```

This gives K_inf ≈ 0.097 — similar to R28's 0.095. Tune Q up for faster scene tracking,
down for more smoothing.

Where to define: `analysis_frame.fx` local `#define` block (alongside `LERP_SPEED`,
which is retired). Or expose in `creative_values.fx` if game-specific tuning is needed.

---

## Storage

`PercTex` (1×1 RGBA16F):

| Channel | Before | After |
|---------|--------|-------|
| `.r` | p25 | p25 (Kalman-smoothed) |
| `.g` | p50 | p50 (Kalman-smoothed) |
| `.b` | p75 | p75 (Kalman-smoothed) |
| `.a` | IQR (p75−p25) | Kalman P |

---

## Benefits over EMA

| Property | EMA (current) | Kalman |
|----------|--------------|--------|
| Cold-start | Slow ramp from 0 | K≈1 → immediate lock-on |
| Scene-cut re-lock | ~9 frames at 60fps | Self-adapts: P rises → faster |
| Frame-rate sensitivity | Partially corrected by `frametime` factor | None — P-based |
| Magic constants | `LERP_SPEED=4.3`, `10.0` denominator | Q, R — physically interpretable |

---

## Success criteria

- `CDFWalkPS` applies Kalman to p25/p50/p75; stores P in `PercTex.a`
- `LERP_SPEED` define retired from `analysis_frame.fx`
- `pro_mist.fx` computes IQR inline as `perc.b − perc.r`
- No new textures, no new passes
- Cold-start: FilmCurve anchors correct from frame 1 (no 9-frame ramp)
- Scene-cut: FilmCurve re-locks within 3–5 frames (vs. current 9+)
