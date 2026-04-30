# R28 — Kalman Temporal History — Findings
**Date:** 2026-04-30
**Method:** Brave search × 14 queries

---

## Research question 1 — Q and R values for real-time luminance tracking

**Finding: No universal published Q/R values for luminance; the Q/R ratio is the only physically meaningful quantity, and tuning guidance converges on Q/R ≈ 0.001–0.01 for slow signals with noisy measurements.**

The literature uniformly treats Q (process noise covariance) and R (measurement noise
covariance) as application-specific. No paper publishes "use Q=X for luminance" as a
universal constant. However, several sources provide grounding:

**What Q represents in this context:** how much the true zone median can change between
frames. In a steady-state scene, zone luminance drifts very slowly — frame-to-frame
change is small. In a scene cut, it can jump by 0.3–0.5 in [0,1] linear. A typical
Q for a slow signal is 1e-4 to 1e-3 (the expected variance of one frame's drift).

**What R represents:** how noisy the zone percentile estimate is. The zone histogram
uses ~256 samples across a 4×4 zone — at 8-bit, measurement variance R is in the
range 1e-3 to 1e-2 depending on scene content and sample count.

**The Q/R ratio sets the steady-state gain.** A key result from the ResearchGate
discussion on Kalman gain vs. Q/R ratio (Accidental fluctuation, Figure 1) shows that:
- Q/R ≈ 0.0001 → K_ss ≈ 0.01 (very smooth, barely tracks changes)
- Q/R ≈ 0.01   → K_ss ≈ 0.09 (moderate tracking, comparable to EMA α=0.05–0.1)
- Q/R ≈ 0.1    → K_ss ≈ 0.24 (fast tracking)
- Q/R ≈ 1.0    → K_ss ≈ 0.62 (near-measurement, little smoothing)

The same source notes that Q/R should be floored at 1/10000 to prevent K going
negative from numerical noise.

**For auto-exposure/AEC:** camera ISP literature (Camera 3A Algorithms: AEC, AF, AWB;
Placeholder Art auto-exposure blog) universally uses EMA-style smoothing with α
controlled by a time constant. The Placeholder Art blog specifies a time constant
τ in frames — equivalent to EMA α = 1/τ. No ISP paper from 2022–2024 was found that
uses a scalar Kalman filter explicitly for AEC luminance smoothing. The AO adaptive
optics literature (OSTI, ResearchGate) applies Kalman to suppress non-white noise in
WFS measurements, but at very different signal bandwidths.

**Practical recommendation for this pipeline:**
- R = 0.01 (zone percentile measurement noise: moderate, based on 8-sample histogram
  per zone per frame — matches the variance seen in the UpdateHistoryPS chroma loop)
- Q = 0.0001 (scene changes slowly frame-to-frame in steady state; allows scene cuts
  to self-adjust via P accumulation)
- Gives Q/R = 0.01 → steady-state K ≈ 0.09 (slower than current EMA base=0.05 at
  speed×(1+10Δ), but with principled fast response on cuts via P accumulation)
- On scene cut: P_pred climbs each frame until K → 1, then decays — no constant needed

These are starting values. They should be exposed as `KALMAN_Q_ZONE` / `KALMAN_R_ZONE`
in `creative_values.fx` for empirical tuning.

**Scene-adaptive tuning:** The Self-Tuning Process Noise in AQ-VBAKF paper (MDPI
Electronics, 2023) proposes adapting Q based on innovation sequences (measurement −
prediction). For this pipeline that would mean: if `abs(current - prev) > threshold`,
boost Q temporarily. However this reintroduces a magic threshold — the cold-start
and cut-response is already self-adapting via P accumulation, so explicit innovation-
based Q adaptation is not needed.

---

## Research question 2 — Steady-state gain (closed form)

**Finding: A closed-form steady-state gain K_inf exists for the scalar 1D case and IS worth using — it eliminates the P state entirely, reducing the shader to a fixed-gain EMA with theoretically optimal alpha.**

**The mathematics (scalar, unit A=1, unit H=1):**

The scalar discrete Riccati equation at steady state is:
```
P_inf = P_inf + Q - P_inf^2 / (P_inf + R)
```
Setting P_inf as the unknown and rearranging yields the quadratic:
```
P_inf^2 - Q*P_inf - Q*R = 0
```
Positive root:
```
P_inf = (Q + sqrt(Q^2 + 4*Q*R)) / 2
```
Steady-state gain:
```
K_inf = P_inf / (P_inf + R)
```

This is confirmed by the Laurent Lessard lecture notes (Lecture 12: Steady-State
Kalman Filter), the Binghamton University optimal control chapter, and the Wiley
"Iterative and Algebraic Algorithms for the Computation of the Steady State Kalman
Filter Gain" (2014, Assimakis). The scalar case has a unique positive-definite solution
to the ARE.

**Worked example with Q=0.0001, R=0.01:**
```
P_inf = (0.0001 + sqrt(0.0001^2 + 4*0.0001*0.01)) / 2
      = (0.0001 + sqrt(0.00000001 + 0.000004)) / 2
      = (0.0001 + sqrt(0.00000401)) / 2
      = (0.0001 + 0.002002) / 2
      = 0.001051
K_inf = 0.001051 / (0.001051 + 0.01) = 0.09525 ≈ 0.095
```

This is equivalent to EMA α = 0.095, which is a sensible smoothing speed for
zone luminance (approximately 10-frame half-life).

**Is it worth using in the shader?**

Yes, for the steady-state path. The recursive Kalman adds per-pixel read of `.a`,
two multiplies, an add, and a write of updated P. The steady-state version pre-computes
K_inf as a compile-time constant and uses a single `lerp` — identical cost to the
current EMA. The critical difference:

- **Steady-state only:** K_inf gives optimal steady-state gain, but cannot handle
  cold-start or scene cuts automatically. The recursive P update is needed for those.
- **Hybrid approach (recommended):** use steady-state K_inf for the normal case, but
  fall back to recursive Kalman for the first N frames (cold-start) and optionally on
  detected large innovations (scene cut). This is the best tradeoff.

The alpha-beta filter literature (Wikipedia: Alpha beta filter; IEEE: "Reconciling
Steady-State Kalman and Alpha-Beta Filter Design") confirms that a steady-state
Kalman filter with constant Q/R converges to a fixed-gain linear filter identical to
an alpha-beta filter. The connection to EMA is exact in the scalar position-only case.

**Relationship between K_inf and EMA alpha:**

For the scalar random-walk model (A=1, H=1):
```
alpha_EMA = K_inf = P_inf / (P_inf + R)
```
So the current `ZONE_LERP_SPEED / 100.0` is mathematically equivalent to K_inf. The
Kalman provides the derivation from physical noise variances instead of tuning by eye.

**GPU register cost of recursive vs. steady-state:**
- Steady-state: 0 extra registers (K_inf is a constant)
- Recursive: +1 VGPR for P (read prev.a, compute P_pred, K, P_new, write)
- Given R26 shows 83 VGPR pressure in grade.fx, the 1 extra VGPR in corrective.fx
  SmoothZoneLevelsPS is negligible — corrective passes are much simpler.

---

## Research question 3 — Real-time tone mapping / auto-exposure applications

**Finding: No published GPU shader or game-engine paper uses a Kalman filter explicitly for real-time tone mapping temporal history; the standard is EMA. Kalman is used in video stabilization (motion) and ISP AO systems but not luminance/chrominance statistics smoothing.**

**What was found:**

The most relevant shader-level auto-exposure resources (Narkowicz 2016 blog; Placeholder
Art 2014 blog; Bruno Opsenica's luminance histogram blog; Unreal Engine 4.27 auto-exposure
docs; CShade ReShade adaptive exposure) all use EMA / hardware blending for temporal
smoothing. None use Kalman. The industry standard is:
```
exposure_new = lerp(exposure_prev, exposure_target, alpha * dt)
```
where alpha is tuned by feel.

**Video stabilization:** Multiple papers (Real-Time Digital Image Stabilization Using
Kalman Filters, ScienceDirect; Vehicle video stabilization with adaptive Kalman, Springer
2023) apply Kalman to stabilize geometric motion vectors, not pixel luminance statistics.
The signal model is position+velocity (2-state), not the 1-state random walk appropriate
for zone luminance.

**ISP / camera AEC:** Camera 3A literature treats AEC as a PID or PI controller on
log-luminance error, not Kalman. The adaptive optics literature (OSTI: Kalman filtering
to suppress spurious signals in Adaptive Optics control) uses Kalman to suppress non-white
noise in wavefront sensors — formally similar but the noise model is colored, not the
white Gaussian assumed here.

**RAW video ISP (arxiv 2410.02572):** Mentions "Kalman structured updating" for
motion-adaptive temporal CFA filtering — closest match found. This is a per-pixel
recursive filter on RAW data, not scene-level statistics. No Q/R values given.

**MDPI 6G ISAC paper (2025):** "On the Design of Kalman Filter with Low Complexity for
6G-Based ISAC: Alpha and Alpha-Beta Filter Perspectives" — discusses steady-state Kalman
≡ alpha-beta filter, shows numerical convergence. Not graphics, but confirms the
theoretical equivalence used in Q2.

**Conclusion:** R28 would be novel in the game post-process / ReShade shader space.
Existing work uses EMA universally. The Kalman replacement is theoretically sound and
has clear prior art in signal processing, but there is no reference implementation to
copy from. The HLSL must be written from first principles.

---

## Concrete HLSL — refined by findings

### Recommended constants

Based on the Q/R analysis:
```hlsl
// creative_values.fx additions
#define KALMAN_Q_ZONE   0.0001   // process noise: ~0.01 RMS change in zone median/frame
#define KALMAN_R_ZONE   0.010    // measurement noise: histogram estimate variance
#define KALMAN_Q_CHROMA 0.0001   // process noise for chroma mean
#define KALMAN_R_CHROMA 0.010    // measurement noise for chroma mean
```

These give steady-state K_inf ≈ 0.095 (≈ EMA α=0.095, 10-frame half-life). Adjust
Q up (→ 0.001) for faster tracking or down (→ 0.00001) for heavier smoothing.

### Pre-computed steady-state gain (compile-time constant, zero register cost)

If cold-start and scene-cut self-adaptation are not required:
```hlsl
// Precomputed: P_inf = (Q + sqrt(Q^2 + 4QR)) / 2, K_inf = P_inf / (P_inf + R)
// With Q=0.0001, R=0.01: K_inf ≈ 0.0953
static const float ZONE_K_INF   = 0.0953;
static const float CHROMA_K_INF = 0.0953;
```
This is a zero-cost drop-in for the current `lerp(prev, current, base)`.

### Full recursive Kalman (recommended — handles cold-start + scene cuts)

**SmoothZoneLevelsPS:**
```hlsl
float4 SmoothZoneLevelsPS(float4 pos : SV_Position,
                          float2 uv  : TEXCOORD0) : SV_Target
{
    if (pos.y < 1.0) return tex2D(ZoneHistorySamp, uv);  // data highway guard

    float4 current = tex2D(CreativeZoneLevelsSamp, uv);
    float4 prev    = tex2D(ZoneHistorySamp, uv);

    // Kalman on median (.r) — cold-start: P<epsilon means uninitialised, use P=1.0
    float P_prev = (prev.a < 0.001) ? 1.0 : prev.a;
    float P_pred = P_prev + KALMAN_Q_ZONE;
    float K      = P_pred / (P_pred + KALMAN_R_ZONE);   // in (0,1) always
    float median = prev.r + K * (current.r - prev.r);
    float P_new  = (1.0 - K) * P_pred;

    // EMA on p25/p75 — less critical, keep cheap
    float base = KALMAN_K_INF;   // use steady-state gain for percentiles too
    float p25  = lerp(prev.g, current.g, base);
    float p75  = lerp(prev.b, current.b, base);

    return float4(median, p25, p75, P_new);
}
```

**UpdateHistoryPS (chroma Kalman on mean only):**
```hlsl
    // Replace lines 291-295 of current corrective.fx:
    float4 prev    = tex2D(ChromaHistory, float2((band_idx + 0.5) / 8.0, 0.5 / 4.0));

    // Kalman on chroma mean (.r)
    float P_prev   = (prev.a < 0.001) ? 1.0 : prev.a;
    float P_pred   = P_prev + KALMAN_Q_CHROMA;
    float K        = P_pred / (P_pred + KALMAN_R_CHROMA);
    float new_mean = prev.r + K * (mean - prev.r);
    float P_new    = (1.0 - K) * P_pred;

    // EMA on std and wsum — keep cheap
    float base     = KALMAN_K_INF;
    float new_std  = lerp(prev.g, stddev, base);
    float new_wsum = lerp(prev.b, sum_w,  base);

    return float4(new_mean, new_std, new_wsum, P_new);
```

**Notes on the HLSL:**
- `K = P_pred / (P_pred + R)` is mathematically guaranteed in (0, 1) when P_pred > 0
  and R > 0 — no `saturate()` needed, but adding one is harmless belt-and-suspenders.
- P_new converges toward P_inf within ~20 frames from cold-start with Q=0.0001, R=0.01.
- `.a` in ZoneHistoryTex changes from sentinel 1.0 to variance P (range ~0.001–1.0).
  Any downstream code that checks `.a == 1.0` as a write-sentinel will break. Audit
  the read sites — the R28 proposal already documents `.a=1.0` as unused beyond marking
  "written". Verify in corrective.fx and grade.fx before shipping.
- P_new is always < P_pred (since K > 0), and P_pred = P_prev + Q > P_prev, so P
  is bounded. In the worst case (K→0), P_pred → P_prev + Q, which grows without bound
  — but K→0 only when R→∞, which won't happen with fixed R. Safe.

---

## Summary

| Question | Answer |
|----------|--------|
| Q and R values | No universal constants in literature. Recommended starting point: Q=0.0001, R=0.01 (gives K_inf≈0.095, ≈10-frame half-life). Expose both in creative_values.fx. |
| Steady-state gain | Yes, closed form: P_inf=(Q+sqrt(Q²+4QR))/2, K_inf=P_inf/(P_inf+R). For Q=0.0001, R=0.01 → K_inf≈0.0953. Zero register cost. Worth pre-computing as a compile-time constant for p25/p75/std/wsum paths. Full recursive Kalman needed only for the primary signal (median, chroma mean) to get cold-start + scene-cut self-adaptation. |
| Prior art in graphics | None found for luminance/chroma statistics smoothing in shaders. EMA is universal. Kalman is used for motion/geometric stabilization in video and for WFS noise in adaptive optics. R28 is novel in this application area. |

**Implementation ready / blockers:**
- Ready to implement. No blocking unknowns.
- Single blocker to verify before coding: audit all read sites of ZoneHistoryTex.a and
  ChromaHistoryTex.a in corrective.fx and grade.fx — if any code treats `.a` as the
  sentinel 1.0, it must be updated to handle the new variance range.
- Retire `ZONE_LERP_SPEED` and `LERP_SPEED` from creative_values.fx; add
  `KALMAN_Q_ZONE`, `KALMAN_R_ZONE`, `KALMAN_Q_CHROMA`, `KALMAN_R_CHROMA`.
- Optional: expose `KALMAN_K_INF` as a precomputed constant for the EMA-kept channels
  (p25, p75, std, wsum) so those still benefit from the theoretically-grounded alpha.
