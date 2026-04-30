# R27N — Data Highway Integrity Audit — Findings
**Date:** 2026-04-30  
**Method:** Static code audit + vkBasalt source review (effect_reshade.cpp)

---

## Web research outcomes

| Question | Finding |
|----------|---------|
| Does vkBasalt clear BackBuffer between effects? | **No.** Each effect receives the previous effect's output unchanged. |
| Does BackBuffer persist across frames? | **No.** Pipeline resets each frame; BackBuffer is reloaded from the swapchain. |
| SV_Position.y for topmost pixel row? | **0.5** (pixel center). `pos.y < 1.0` correctly catches only the first row. |

Highway mechanism is sound: data written by `analysis_scope_pre` at row y=0 is intact
when `analysis_scope` reads it. No inter-effect clearing, no guard bypasses in any
active BB-writing pass.

---

## Pass-by-pass results

### `analysis_frame.fx` — DebugOverlay (BackBuffer writer, BEFORE scope_pre)

| Check | Result |
|-------|--------|
| Guard present? | **NO** — `DebugOverlayPS` has no `if (pos.y < 1.0)` guard |
| Risk now? | **Zero** — runs before scope_pre; highway not yet established |
| Risk if chain changes? | **Critical** — if any future effect writes highway data before analysis_frame, DebugOverlay silently corrupts it |

Verdict: **defensive gap**. Not a current bug, but the only unguarded BB writer in the chain.

---

### `analysis_scope_pre.fx` — ScopeCapture (WRITER)

| Pixel range | Expected | Actual | Status |
|-------------|----------|--------|--------|
| 0–127 | luma histogram bins | Written ✓ | OK |
| 128 | scene mean luma | Written ✓ | OK |
| 129 | reserved (scope post-mean) | Falls through to DrawLabel → game content | **See Finding 2** |
| 130–193 | hue histogram (64 bins) | Written ✓ | OK |

Histogram math verified: 8×8 grid sampling with `Halton`-style deterministic UVs, correct bin
counting, fraction output. Hue histogram: saturation-weighted, `step(0.04, hsv.y)` threshold
excludes near-grey pixels. Both histograms correct.

---

### `corrective.fx` — Passes 1–5 (explicit RenderTargets)

| Pass | RenderTarget | Touches BackBuffer? |
|------|-------------|---------------------|
| ComputeLowFreq | `CreativeLowFreqTex` | No |
| ComputeZoneHistogram | `CreativeZoneHistTex` | No |
| BuildZoneLevels | `CreativeZoneLevelsTex` | No |
| SmoothZoneLevels | `ZoneHistoryTex` | No |
| UpdateHistory | `ChromaHistoryTex` | No |

All clean. UpdateHistory reads BackBuffer for chroma sampling but only at Halton
UV coordinates spread across the full image — does not write BackBuffer.

### `corrective.fx` — Passthrough (BackBuffer writer)
```
Line 305: if (pos.y < 1.0) return c;  // data highway
```
**Guard: PRESENT ✓**

---

### `grade.fx` — ColorTransformPS (BackBuffer writer)
```
Line 200: if (pos.y < 1.0) return col;  // data highway
```
**Guard: PRESENT ✓**

Analysis texture reads verified:
- `ZoneHistorySamp` at explicit UV coords (zone grid, spatial UV) — no row y=0 reads ✓
- `ChromaHistory` at `float2((band + 0.5) / 8.0, 0.5 / 4.0)` — dedicated texture, not BackBuffer ✓
- `PercSamp` at `float2(0.5, 0.5)` — 1×1 texture ✓
- `CreativeLowFreqSamp` at `uv` and `float4(uv, 0, 2)` — no row y=0 reads ✓

---

### `pro_mist.fx` — ProMistPS (BackBuffer writer)
```
Line 67: if (pos.y < 1.0) return base;
```
**Guard: PRESENT ✓**

---

### `analysis_scope.fx` — ScopePS (READER / RESTORER)

| Read | UV | Status |
|------|----|--------|
| `data_v` | `0.5 / BUFFER_HEIGHT` = row y=0 center | ✓ |
| pre_mean | pixel 128 at data_v | ✓ |
| post_mean | pixel 129 at data_v | Reads correctly; value quality issue — see Finding 2 |
| Hue bars | pixels 130–193 at data_v | ✓ |
| Restore pixels 0–128 | reads row y=1 (`1.5/BUFFER_HEIGHT`) | ✓ |

Row y=0 pixels 0–128 are restored from row y=1 (the fully-graded row immediately
below). After scope runs, the data highway row blends back into the image seamlessly.

---

### Inactive effects (`veil.fx`, `retinal_vignette.fx`)

Both are declared in `arc_raiders.conf` but absent from the `effects =` line.
Both have guards:
- `veil.fx` line 64: `if (pos.y < 1.0) return col;` ✓
- `retinal_vignette.fx` line 109: `if (pos.y < 1.0) return col;` ✓

Safe to activate without highway risk.

---

## Findings

### Finding 1 — Defensive gap: `analysis_frame` DebugOverlay missing guard
**Severity: LOW (latent)**

`DebugOverlayPS` in `analysis_frame.fx` is the only BackBuffer-writing pass in the
active chain with no `if (pos.y < 1.0)` guard. Currently harmless because it
executes before `analysis_scope_pre` and the highway is not yet established.

If the chain order ever changes — e.g. adding an effect before `analysis_frame` that
writes highway data — this becomes a silent critical failure.

**Recommendation:** Add the standard guard to `DebugOverlayPS`.

---

### Finding 2 — Post-mean temporal smoothing broken at pixel 129
**Severity: LOW (scope display artifact, no color-grade impact)**

`analysis_scope_pre` has no explicit handler for pixel 129 at row y=0. It falls
through to the DrawLabel passthrough, writing the game's raw pixel value at screen
position (129, 0) into the data highway.

`analysis_scope` later reads pixel 129 at `data_v` as `prev` for temporal smoothing:
```hlsl
float prev = tex2Dlod(BackBuffer, float4((float(SCOPE_BINS + 1) + 0.5) / float(BUFFER_WIDTH), dv, 0, 0)).r;
float s = lerp(prev, live, SCOPE_LERP / 100.0 * frametime / 10.0);
```

Since vkBasalt provides **no cross-frame BackBuffer persistence**, `prev` is always the
game's pixel at (129, 0) — not a prior smoothed mean. The lerp anchors to the wrong
value. At 60 fps and SCOPE_LERP=4.3 the weight is ≈0.072 per frame, so the error is
diluted but present: `s ≈ 0.928 * game_pixel + 0.072 * live_mean`.

**Impact:** The scope's post-mean yellow needle may show a slightly shifted value
depending on what the game renders at screen coordinate (129, 0). The pre-correction
histogram (pixels 0–127, pixel 128 mean) is unaffected. The color grade is unaffected.

**Fix options:**
- A: In `ScopeCapturePS`, explicitly write `float4(0,0,0,1)` to pixel 129 (neutral prior
  — the smoothing then anchors to 0, which pulls slightly dark on dark scenes).
- B: Have `ScopePS` not read a prior frame value at all — compute live post-mean directly
  with no temporal smoothing (simpler, eliminates the broken state entirely).
- C: Keep as-is (the visual artifact is minor and the feature is cosmetic).

---

## Summary

| Check | Status |
|-------|--------|
| All active BB-writing passes after scope_pre have guards | **PASS** |
| scope_pre writes histogram correctly (pixels 0–128, 130–193) | **PASS** |
| scope reads from correct coordinates (data_v, pixel 128, 129) | **PASS** |
| Explicit-RenderTarget passes do not touch BackBuffer | **PASS** |
| Inactive effects (veil, retinal_vignette) have guards | **PASS** |
| vkBasalt preserves highway data between effects | **CONFIRMED via source** |
| analysis_frame DebugOverlay guard | **MISSING (latent risk)** |
| Post-mean temporal smoothing (pixel 129) | **BROKEN (cosmetic only)** |

The data highway is **structurally sound**. Highway corruption in the color grade path
is not occurring. The two open items are both in the scope display subsystem and
carry zero color-grade risk.
