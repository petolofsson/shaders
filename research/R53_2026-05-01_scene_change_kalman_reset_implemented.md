# R53 — Scene-Change Kalman Reset

**Date:** 2026-05-01
**Status:** Implemented

---

## Problem

All temporal filters in the chain (ZoneHistoryTex, ChromaHistoryTex, PercTex) use a
VFF-RLS Kalman with steady-state gain `KALMAN_K_INF ≈ 0.095`. This gives smooth,
stable stats under normal scene evolution but is too slow to respond to discontinuous
scene changes:

- Loading screen → gameplay (extreme luminance jump)
- Interior → exterior (large dynamic range shift)
- Fade-from-black / fade-to-white

During these transitions, the Kalman carries stale stats for approximately `1 / 0.095 ≈ 10`
frames before converging. On a 60fps game, that is ~167ms of incorrect tone mapping —
visible as a brief wrong-exposure or colour cast that slowly corrects itself.

The fix is standard in broadcast adaptive filtering: detect a statistical discontinuity in
the incoming signal and temporarily spike the Kalman gain toward 1.0, then let it decay
back to `KALMAN_K_INF`. This gives fast adaptation on cuts and slow drift otherwise.

---

## Signal

Frame-to-frame change in the histogram centroid. The `PercTex` 1×1 texture already holds
`p50` (scene median) from the previous frame. The current frame's raw histogram provides a
new candidate `p50_raw`. Their difference:

```hlsl
float delta_p50 = abs(p50_raw - p50_prev);
```

A scene cut typically produces `delta_p50 > 0.15` in a single frame. Normal scene
evolution produces `delta_p50 < 0.04`. The gap is wide enough for a reliable threshold.

---

## Proposed implementation

### Part 1 — Scene change metric (analysis_frame.fx, CDF walk pass)

After computing `p50_raw` from the CDF walk, read the previous `p50` from `PercTex`:

```hlsl
// analysis_frame.fx — end of CDF walk pass
float p50_prev   = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0)).g;
float delta_p50  = abs(p50_raw - p50_prev);
float scene_cut  = smoothstep(0.10, 0.25, delta_p50); // 0 = stable, 1 = cut
```

Write `scene_cut` into an otherwise-unused channel (e.g. `PercTex.a` if not already
used for IQR, or a dedicated 1×1 `SceneCutTex R16F`).

### Part 2 — Gain spike in all Kalman update passes (corrective.fx)

In `UpdateHistoryPS`, `SmoothZoneLevelsPS`, and the PercTex smooth pass, read `scene_cut`
and override the Kalman gain:

```hlsl
// corrective.fx — inside each Kalman update
float scene_cut = tex2Dlod(SceneCutSamp, float4(0.5, 0.5, 0, 0)).r;
float K_effective = lerp(KALMAN_K_INF, 1.0, scene_cut);
// replace KALMAN_K_INF with K_effective in the lerp
float new_val = lerp(prev_val, raw_val, K_effective);
```

At `scene_cut = 1.0` (hard cut), `K = 1.0` → instant snap to new stats, no history.
At `scene_cut = 0.0` (stable), `K = KALMAN_K_INF = 0.095` → current behaviour.

The `scene_cut` signal is one frame behind by the time it reaches `UpdateHistoryPS`
(it is written in analysis_frame, read in corrective), but that is acceptable — on a
hard cut the second frame is still far from converged.

---

## Texture budget

Option A — reuse `PercTex.a`: currently stores `iqr`. Move `iqr` to `ChromaHistoryTex`
col 6 channel b (currently unused) and use `PercTex.a` for `scene_cut`. Zero new textures.

Option B — add `SceneCutTex`: 1×1 R16F. Minimal VRAM cost, cleaner separation.

Option A preferred — avoids a new texture and a new sampler declaration in both effects.

---

## Interaction with existing pipeline

- **Zone contrast, chroma lift, shadow lift**: all read from Kalman-smoothed textures.
  On a scene cut they will snap to new stats instantly rather than drifting over 10 frames.
  This is strictly correct behaviour.
- **FilmCurve p25/p50/p75**: also Kalman-smoothed via PercTex. Will snap on cut — the
  film curve will immediately reflect the new scene's tonal character.
- **VFF-RLS residual-driven Q (R39)**: R39 already adjusts Q based on residual magnitude.
  The scene_cut override bypasses Q entirely by forcing K → 1.0. The two mechanisms
  are complementary: R39 handles gradual scene evolution, R53 handles discontinuities.

---

## Validation targets

- Transition from dark loading screen to bright outdoor gameplay: tone mapping should
  correct within 1–2 frames, not 10
- Normal gameplay (no cuts): zero change in behaviour — `delta_p50 < 0.04`, `scene_cut = 0`
- Slow dawn/dusk lighting transition: `delta_p50` stays below threshold, smooth Kalman
  drift continues normally

---

## Risk

Medium. Requires coordinated changes across `analysis_frame.fx` and `corrective.fx`.
The `PercTex.a` reuse (Option A) requires verifying that `iqr` is not read in the same
pass it is being relocated from — check all `PercSamp` reads in `corrective.fx` and
`grade.fx` before implementing. The `scene_cut` value is a 0–1 float, not a binary gate,
so there are no hard seams. Worst case on mis-detection: one frame of slightly faster
Kalman adaptation, invisible at 60fps.
