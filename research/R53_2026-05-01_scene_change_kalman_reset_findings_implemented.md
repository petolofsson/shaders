# R53 — Scene-Change Kalman Reset — Findings

**Date:** 2026-05-01
**Searches:**
1. Adaptive Kalman filter scene change detection gain reset temporal video processing
2. Histogram median jump discontinuity detection broadcast temporal filter adaptation
3. Kalman filter abrupt change detection gain reset innovation outlier temporal adaptation
4. Kalman filter jump detection adaptive gain reset innovation sequence
5. Scene cut detection video histogram luminance jump threshold frame difference broadcast

---

## Key Findings

### 1. Kalman innovation sequence — standard mechanism for abrupt change detection

Confirmed from multiple sources (Wikipedia Kalman filter, Stack Overflow, ResearchGate,
emergentmind.com, NIST):

The **innovation** (pre-fit residual) = `measurement - predicted_state`. In steady-state
Kalman operation, the innovation is small and bounded. When an abrupt scene change occurs,
the innovation spikes sharply — the filter's prediction is suddenly wrong by a large amount.

The standard adaptive Kalman approach for this (emergentmind.com survey, NIST 1985 paper
"Adaptive Kalman Filtering"):
> "Modifications to the filter involve allowing the filter to adapt the measurement model
> through matching the theoretical and observed covariance of the filter innovations sequence."

Specifically, from the scholarly.org paper on frequency jump detection:
> "gradually increase the covariance process noise which represents the frequency jump"
> "after that bring it to the normal value"
> "This change in the Kalman filter gain can be obtained by increasing the process noise covariance"

This is exactly the proposal: on large innovation (delta_p50 spike), raise the effective
Kalman gain temporarily toward 1.0, then let it decay back to K_INF.

From ResearchGate (Karbowski 2014), "On change detection in a Kalman filter based tracking
problem": "It is assumed that the tracking is done by a Kalman filter and that the abrupt
change takes place after the steady-state behavior of the filter is reached." — confirms the
problem statement. The innovation process carries the change signal.

Adaptive gain via process noise Q is the standard mechanism. The proposal's direct gain
override (`K_effective = lerp(KALMAN_K_INF, 1.0, scene_cut)`) is equivalent to Q → ∞ and
is cleaner to implement in a real-time shader context where Q is a fixed define.

### 2. Scene cut detection via histogram — well-established in video processing

Multiple confirmed sources:

**PySceneDetect**: Uses histogram correlation (`cv2.HISTCMP_CORREL`) between consecutive frames.
"A scene change is detected if the correlation between the histograms of consecutive frames
is below the specified threshold." This validates the histogram-comparison approach at the
implementation level.

**Shot transition detection (Wikipedia)**: "HD computes the difference between the histograms
of two consecutive frames; a histogram is a table that contains for each color within a frame
the number of pixels that are shaded in that color." Histogram difference is the canonical
approach for cut detection.

**Fade Scene Change Detection paper (ResearchGate)**: "utilizes the luminance histogram twice
difference in order to determine the dynamic threshold needed to evaluate the break."
The luminance histogram is specifically used, not RGB — directly applicable to the proposal's
`delta_p50 = abs(p50_raw - p50_prev)` which uses the luminance CDF.

The proposal uses the p50 (median) of the luminance histogram as the change signal. This is
a scalar compression of the histogram difference — less sensitive to outliers than a full
histogram distance but computationally free (p50 is already computed in analysis_frame.fx).
The claimed gap (`delta_p50 > 0.15` for cuts, `< 0.04` for normal evolution) is plausible:
a hard cut from a dark interior (median ~0.15) to a bright exterior (median ~0.55) would
produce delta_p50 ≈ 0.40 — well above threshold. False positive risk from explosions or
bright flashes is the main concern (see risks).

### 3. Texture budget — Option A (PercTex.a reuse) has a conflict

The proposal offers Option A (reuse PercTex.a, move iqr to ChromaHistoryTex col 6 channel b)
or Option B (new 1×1 SceneCutTex). **Option A has a confirmed conflict:**

From HANDOFF.md: ChromaHistoryTex col 6 layout: `.r=zone_log_key, .g=zone_std, .b=zmin, .a=zmax`.
All four channels are in use. There is no spare channel to receive `iqr`.

Option A is therefore not viable without also reorganizing ChromaHistoryTex, which is a
broader refactor with its own risk. **Option B (SceneCutTex, 1×1 R16F) is the correct choice.**
Cost: one 1×1 R16F texture + one sampler declaration in corrective.fx. VRAM cost is
negligible (2 bytes). This is the same pattern used by PercTex for global stats.

### 4. scene_cut propagation timing — one-frame lag is acceptable

The proposal correctly notes that `scene_cut` is written by `analysis_frame.fx` and read by
`corrective.fx` in the next frame (vkBasalt processes one effect per frame in the chain,
but analysis_frame and corrective run in the same frame — they are separate effects, so
analysis_frame writes BackBuffer row 0 stats and corrective reads them in the same frame's
corrective pass).

Actually, checking the chain: `analysis_frame → analysis_scope_pre → corrective → grade →
analysis_scope`. Within a single rendered frame, analysis_frame runs first and corrective
runs later in the same frame. The `scene_cut` value written by analysis_frame to SceneCutTex
would be available to corrective within the same frame — **no one-frame lag**, assuming
SceneCutTex is a persistent texture written by analysis_frame and read by corrective.

The PercTex (1×1) precedent confirms this pattern: PercTex is written by analysis_frame
and read by grade.fx later in the same chain. SceneCutTex would follow the same model.

### 5. VFF-RLS (R39) interaction

The existing Kalman uses VFF (Variable Forgetting Factor via residual-driven Q). Under the
R53 override:
- `K_effective = 1.0` on a hard cut — overrides both Q and the VFF mechanism entirely
- This is safe: K=1 means "trust the new measurement completely" — correct on a scene cut
- After the cut frame, K_effective decays back toward K_INF as scene_cut → 0
- R39's VFF mechanism then resumes its normal residual-driven adaptation
- The two mechanisms are complementary and non-conflicting: R39 handles gradual drift,
  R53 handles discontinuities

---

## Parameter Validation

### `scene_cut = smoothstep(0.10, 0.25, delta_p50)`

- `delta_p50 < 0.10`: scene_cut = 0 — normal evolution, no override
- `delta_p50 = 0.175`: scene_cut = 0.5 — moderate brightness jump (e.g. flash)
- `delta_p50 > 0.25`: scene_cut = 1.0 — hard cut, full K=1 snap

Normal scene evolution (`delta_p50 < 0.04` per proposal) sits well below the 0.10 lower
bound — no false triggers expected under normal play. The gap between 0.04 and 0.10 provides
a comfortable margin.

### `K_effective = lerp(KALMAN_K_INF, 1.0, scene_cut)`

At scene_cut=1.0: K=1.0 — single-frame snap, history discarded.
At scene_cut=0.5: K=0.547 — ~5.75× faster adaptation than steady-state.
At scene_cut=0.0: K=KALMAN_K_INF=0.095 — current behaviour exactly.

The lerp is linear in K, which means Q-equivalent grows non-linearly. This is acceptable —
the important properties are: zero change in normal operation, full snap on hard cuts.

---

## Risks and Concerns

### 1. False trigger on game-engine bright flashes / explosions

An explosion or lightning strike that raises scene median by > 0.10 in one frame will
trigger partial Kalman reset. On the flash frame: K≈0.5+ → Kalman snaps partially toward
the bright flash. On the next frame: flash gone, K back to 0.095, Kalman slowly returns.

Net effect: the filter briefly over-adapts to the flash, then slowly returns. This may
produce a brief "wrong tone map" after a large explosion. However:
- The flash frame itself is correctly tone-mapped by the existing Kalman state
- The K=1 snap only fully fires at delta_p50 > 0.25 — a 0.25 median shift in one frame
  from an explosion is extreme (most explosions bloom locally, not the full scene median)
- The VFF mechanism (R39) would have already spiked K upward on a large residual

Risk is **low to medium** — monitor in explosion-heavy Arc Raiders combat sequences.

### 2. Slow dawn/dusk transitions near threshold

A slow sunrise moving the p50 by 0.02 per frame will stay below 0.10 and not trigger.
At 60fps a full 0.4-unit median shift would take 20 frames, well below the threshold.
This is correct and intended behaviour.

### 3. PercTex.a contains iqr — confirm all read sites before implementation

`iqr` is used in: `grade.fx` (shadow lift gate: `zone_iqr` — actually from ChromaHistoryTex;
the global `iqr` from PercTex is used in `pro_mist.fx` adapt_str calibration and potentially
elsewhere). Before relocating iqr, all read sites of `PercTex.a` must be audited across
`corrective.fx`, `grade.fx`, and `pro_mist.fx`. If iqr cannot be moved cleanly, Option B
(SceneCutTex) is clean with no relocation required.

---

## Verdict

**Proceed — strong theoretical and empirical support. Use Option B (SceneCutTex). Medium
implementation complexity.**

The proposal is correct in theory and validated by both the Kalman filter literature and
the scene cut detection literature. The key implementation decisions:

1. **Use Option B** — SceneCutTex 1×1 R16F. Option A conflicts with ChromaHistoryTex col 6.
2. **Audit all PercTex.a read sites** before any texture rearrangement.
3. **scene_cut is same-frame** — analysis_frame writes SceneCutTex, corrective reads it
   in the same frame. No lag issue.
4. **Monitor explosions** — watch for false triggers on large single-frame luminance spikes
   in combat-heavy sequences.

The implementation risk (Medium) is purely from the cross-effect coordination requirement
(analysis_frame + corrective + grade must all be aware of SceneCutTex). Logic is simple;
the complexity is in touching multiple files safely.
