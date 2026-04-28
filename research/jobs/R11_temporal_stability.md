**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)
**Task:** Use the **Brave Search MCP** to find adaptive temporal filtering approaches for the zone and chroma history textures in `corrective.fx`, replacing the fixed-rate lerp smoothing with content-aware temporal stability.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/corrective/corrective.fx`

**Current zone history smoothing** (`corrective.fx`, SmoothZoneLevels pass):
```hlsl
// Temporal lerp at fixed ZONE_LERP_SPEED = 8
new_val = lerp(prev, current, dt * ZONE_LERP_SPEED);
```

**Current chroma history smoothing** (`corrective.fx`, UpdateHistory pass):
```hlsl
// Temporal lerp at fixed LERP_SPEED = 8
hist = lerp(prev_hist, new_sample, 1.0 / LERP_SPEED);
```

Problems:
- Fixed lerp speed means: fast dynamic scenes (explosions, flickering lights) cause the history to flicker visibly because the smoothing can't keep up, OR the smoothing is so aggressive it lags behind scene changes (grey cast during rapid scene transitions).
- No distinction between gradual scene evolution (slow fade) and abrupt cuts or explosions — both are treated identically.
- The zone median and chroma stats drive the S-curve and chroma lift respectively. Instability in these stats causes per-frame variation in the entire color grade — visible as a "breathing" or "pumping" artifact.

**Philosophy:** SDR, vkBasalt, no new passes. The history textures are small (4×4 for zones, 8×4 for chroma). Changes confined to SmoothZoneLevels and UpdateHistory passes in `corrective.fx`.

---

### 2. Autonomous Brave Search (The Hunt)

Search `arxiv.org`, `acm.org`, `graphics.stanford.edu` for:

- **Adaptive temporal filtering:** "adaptive temporal filter" game post-process scene change detection 2023–2026. Looking for signal-magnitude-driven blend factors: blend faster when the signal changes significantly, blend slower when stable.
- **Auto-exposure temporal stability:** "auto-exposure temporal smoothing" game real-time 2023–2026. Auto-exposure systems face the exact same problem (adapting to scene changes without flickering) and have well-documented solutions. The zone history is effectively an auto-contrast system — their temporal approaches transfer directly.
- **Exponential moving average with reset:** "exponential moving average" scene cut detection shader 2023–2026. Is there a lightweight scene-change signal (e.g. frame-to-frame luminance delta) that can trigger a faster blend or full reset without a full-frame analysis pass?
- Specifically: a formula of the form `speed = base_speed * f(|current - history|)` where `f` increases the blend rate proportionally to how much the signal changed — no discrete branch, self-regulating.

---

### 3. Documentation

Output findings to `research/2026-XX-XX_temporal_stability.md`. For each approach:

- **Core thesis:** How does the adaptive blending work?
- **Mathematical delta:** Fixed `lerp(prev, curr, k)` vs. proposed adaptive formula
- **Scene-cut handling:** Does it handle hard cuts without a full-reset branch?
- **Injection point:** `SmoothZoneLevels` pass and `UpdateHistory` pass in `corrective.fx`
- **New uniforms needed:** Does it require a frame delta time or frame count? (Both are available: `FRAME_COUNT` uniform already exists in corrective.fx)
- **Viability verdict:** PASS/FAIL

---

### 4. Strategic Recommendation

The minimum viable improvement is replacing the fixed lerp coefficient with a magnitude-proportional one: `speed = LERP_SPEED * (1.0 + k * abs(current - prev))` — faster when the signal is changing, falls back to baseline when stable. No new passes, no new textures, two-line change per smoothing pass. Assess whether the literature supports a specific `k` value or whether it needs to be a new tuning knob.

**Constraint:** The history textures are written with FRAME_COUNT-gated initialization (first frame writes directly). Any adaptive formula must be compatible with this initialization pattern.
