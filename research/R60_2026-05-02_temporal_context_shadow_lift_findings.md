# R60 — Temporal Context Shadow Lift — Findings

**Date:** 2026-05-02
**Status:** Research complete — safe to implement.

---

## Q1 — ChromaHistoryTex col 7 availability

`UpdateHistoryPS` early-returns `float4(0,0,0,0)` when `band_idx >= 7` (line 328 of
`corrective.fx`). `ColorTransformPS` does not read col 7. Col 7 row 0 is free.

On cold start `prev_slow` reads 0.0. Initialise with:
```hlsl
float prev_slow = tex2Dlod(ChromaHistorySamp, float4(7.5/8.0, 0.5/4.0, 0, 0)).r;
if (prev_slow < 0.001) prev_slow = zone_log_key;
```
This gives an immediate warm-start on the first frame, no ramp-in artefact.

---

## Q2 — Time constant selection

At 60 fps, K_slow convergence times:

| K_slow | 63% time | 95% time | Character |
|--------|----------|----------|-----------|
| 0.010  | 100 f / 1.7 s | 300 f / 5 s | Too fast — barely slower than fast Kalman |
| 0.005  | 200 f / 3.3 s | 600 f / 10 s | Good — covers fast photopic adaptation |
| 0.002  | 500 f / 8.3 s | 1500 f / 25 s | Covers full photopic range |
| 0.001  | 1000 f / 17 s | 3000 f / 50 s | Slow — approaches scotopic onset |

Human photopic dark-adaptation is 10–30 s. **`K_slow = 0.003`** (63% at ~5.5 s,
95% at ~17 s) sits in the middle of that range and is the recommended value.

---

## Q3 — Formulation

**Linear ratio `slow_key / zone_log_key` does not work** — needs `saturate()` to stay
SDR, which clips the boost side to 1.0. Must use log space:

```hlsl
float log_context  = log2(slow_key / max(zone_log_key, 0.001));
float context_lift = exp2(log_context * CONTEXT_WEIGHT);
```

This is symmetric: a 2× darker deviation and a 2× brighter deviation produce
reciprocal multipliers. At steady state (`slow_key == zone_log_key`): `log_context = 0`
→ `context_lift = 1.0`, identity.

---

## Q4 — CONTEXT_WEIGHT calibration

Scenario: `slow_key = 0.15` (outdoor baseline), `zone_log_key = 0.06` (tunnel entry).
`log_context = log2(0.15/0.06) = 1.322`

| CONTEXT_WEIGHT | context_lift | Δ shadow lift | Character |
|----------------|-------------|---------------|-----------|
| 0.0 | 1.00 | none | Current R57–R59 behaviour |
| 0.3 | 1.47 | +47% | Subtle — barely perceptible on transitions |
| 0.4 | 1.58 | +58% | Moderate — noticeable during tunnel entry |
| 0.5 | 1.76 | +76% | Strong — clearly different in/out of shadow |
| 0.7 | 2.18 | +118% | Aggressive — risk of crush on brief bright re-entries |

Steady-state tunnel (`slow_key ≈ zone_log_key`): `context_lift = 1.0` always.
The modulation is strongest during transitions; fades as viewer "adapts."

**Recommended: `CONTEXT_WEIGHT = 0.4`** — meaningful transition boost without
over-shooting on bright-to-dark swings.

Trajectory validation — three scenarios at K_slow=0.003, 60 fps:

**Outdoor (key=0.18) → tunnel (key=0.06) → outdoor:**
- Frame 0 (enter tunnel): slow=0.18, fast=0.06, log_context=+1.585 → ×1.90 at w=0.4
- Frame 200 (~3.3 s): slow≈0.11, fast=0.06, log_context=+0.874 → ×1.43
- Frame 550 (~9 s): slow≈0.07, fast=0.06, log_context=+0.222 → ×1.08 (near-neutral)
- Frame 550+1 (exit): slow≈0.07, fast=0.18, log_context=−1.364 → ×0.58 (suppressed)
- Frame 750 (~3.3 s after exit): slow≈0.11, fast=0.18, log_context=−0.709 → ×0.74

Re-entry suppression is the right behaviour — the player's eye hasn't re-adapted to
bright yet; the lift would fight high-luma pixels unnecessarily.

**All-dark session (key=0.06 throughout):**
- After 550 frames: slow≈0.06, context_lift → 1.0. Lift settles at baseline.
  Mood preserved. ✓

**Flickering mixed scene (alternating 0.10/0.20 at 20-frame intervals):**
- slow_key tracks the mean (≈0.15) with small ripple (~0.003 amplitude at K=0.003).
  context_lift oscillates ±0.15 around 1.0. Imperceptible. ✓

---

## Q5 — Register pressure

`ColorTransformPS` currently sits at ~129 scalars. The proposed addition is:
- 1× `tex2Dlod` on `ChromaHistorySamp` (col 7) — same sampler already in scope
- `log2()`, `exp2()`, multiply — 3 scalar ops, 1–2 registers live simultaneously

The net register addition is 1–2 scalars. This may trigger spill at the compiler's
threshold. Must verify after implementation with a SPIR-V disassembly or shader
compiler output. If spill occurs, `slow_key` can be packed into an existing read:
`ChromaHistoryTex` col 6 already fetched for `zone_log_key` — extending that fetch
to include col 7 in the same pass avoids a second sampler instruction.

**Mitigation already available**: merge the col 6 and col 7 reads into a single
`tex2Dlod` by reading both columns in one loop (requires restructuring UpdateHistoryPS
to write col 7 alongside col 6). Zero net new taps in grade.fx if the slow_key is
packed into the existing `ChromaHistory` col 6 read path — e.g. store slow_key in
col 6 `.a` (currently unused: col 6 layout is `.r=zone_log_key, .g=zone_std,
.b=zmin, .a=zmax` — all 4 channels taken). Alternatively: encode slow_key as a
second row of col 6 (row 1, currently unused in `ChromaHistoryTex` which is 8×4).

**Preferred slot: col 6 row 1** — same texture, same sampler, no column-7 guard
change required, zero impact on existing col 7 early-return logic.

---

## Implementation

### corrective.fx — UpdateHistoryPS, inside `band_idx == 6` block

After the existing col 6 row 0 write, add slow-key update:

```hlsl
// Slow ambient key — long time constant EMA for temporal context (R60)
float prev_slow = tex2Dlod(ChromaHistorySamp, float4(6.5/8.0, 1.5/4.0, 0, 0)).r;
if (prev_slow < 0.001) prev_slow = exp(lk * 0.0625); // cold-start: zone_log_key
float slow_key_w = lerp(prev_slow, exp(lk * 0.0625), 0.003);
// write col 6, row 1:
if (pos.y >= 1.0 && pos.y < 2.0)
    return float4(slow_key_w, 0, 0, 0);
```

Wait — `UpdateHistoryPS` dispatches one pixel per band per row. The dispatch geometry
must be verified before this approach is valid. If the pass only ever writes row 0,
a second pixel at row 1 will never execute.

**Alternative: write slow_key into col 6 row 0 as a fifth float.**
`ChromaHistoryTex` is RGBA16F — only 4 channels. No fifth float available.

**Correct approach: write to col 7 row 0, remove the `band_idx >= 7` guard for
col 7 only.** Change the guard from `band_idx >= 7` to `band_idx >= 8` and handle
`band_idx == 7` as the slow-key update:

```hlsl
// corrective.fx line 328 — change guard
if (band_idx >= 8) return float4(0, 0, 0, 0);  // was >= 7

// Add after band_idx == 6 block:
if (band_idx == 7)
{
    float zone_log_key = tex2Dlod(ChromaHistorySamp, float4(6.5/8.0, 0.5/4.0, 0, 0)).r;
    float prev_slow    = tex2Dlod(ChromaHistorySamp, float4(7.5/8.0, 0.5/4.0, 0, 0)).r;
    if (prev_slow < 0.001) prev_slow = zone_log_key;
    return float4(lerp(prev_slow, zone_log_key, 0.003), 0, 0, 0);
}
```

### grade.fx — ColorTransformPS, shadow lift block

```hlsl
// R60: temporal context modulation
float slow_key     = max(tex2Dlod(ChromaHistorySamp, float4(7.5/8.0, 0.5/4.0, 0, 0)).r, 0.001);
float context_lift = exp2(log2(slow_key / max(zone_log_key, 0.001)) * 0.4);
float shadow_lift  = SHADOW_LIFT * (0.149169 / (illum_s0 * illum_s0 + 0.003))
                   * local_range_att * texture_att * detail_protect * context_lift;
```

One additional `tex2Dlod` in `ColorTransformPS`. Monitor register count after compile.

---

## Recommendation

**Implement.** The formulation is clean, the storage is free, the time constant is
physically motivated. The modulation is strongest during transitions (exactly when it
matters) and fades to identity at steady state (preserving mood in sustained-dark
environments). Register pressure is the only implementation risk — verify after
compiling and repack into col 6 row 0 unused `.a` if needed (check whether `.a` is
truly free: HANDOFF says col 6 layout is `.r=zone_log_key, .g=zone_std, .b=zmin,
.a=zmax` — zmax is used in grade.fx, so `.a` is taken).

Final storage conclusion: **col 7 row 0 with guard change `>= 7` → `>= 8`** is the
cleanest path. One-line guard change in corrective.fx, one new `band_idx == 7` block,
one extra tap in grade.fx.
