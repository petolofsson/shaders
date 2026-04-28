# Research 07 — Shadow lift redesign

## Question
Can the shadow lift be redesigned so it enhances mid-shadow clarity and tonal separation
without raising the black floor — producing depth and internal gradation instead of gray fog?

## Context
The current shadow lift in `ColorTransformPS` Stage 2 (`grade.fx`):

```hlsl
float lift_w = smoothstep(0.4, 0.0, new_luma);
new_luma     = saturate(new_luma + (SHADOW_LIFT / 100.0) * 0.15 * lift_w);
```

`lift_w` is a monotonically decreasing function: maximum (1.0) at luma=0, zero at luma=0.4.
This means the greatest lift is applied at true black — the exact pixels that should anchor
to 0. The effect is an additive constant floor raise, which:

- Compresses shadow contrast: range 0–0.4 maps to floor–0.4, reducing internal gradation
- Grays out deep blacks: pixels that read as black now have positive luminance
- Looks game-independent: the same milky quality appears in any dark scene

The creative_values.fx comment explicitly names the problem: "raise dark tones toward grey".

The goal is the inverse: preserve black depth, lift mid-shadows to reveal gradation, produce
shadows that look integrated into the scene rather than fogged.

## Critical detail
`SHADOW_LIFT` is in `creative_values.fx` (default 12, range 0–100). The `0.15` is a hardcoded
ceiling baked into grade.fx. Any redesign must either preserve the knob's effective range at
the current default or adjust the ceiling constant K so behavior at SHADOW_LIFT=12 is comparable
to current at mid-shadow (luma ≈ 0.2), which is the region of most visual interest.

## What to read
- `general/grade/grade.fx` — Stage 2 shadow lift, full context including zone S-curve before it
  and clarity after it (lines ~399–419)
- `gamespecific/arc_raiders/shaders/creative_values.fx` — SHADOW_LIFT default
- `general/analysis-frame/analysis_frame.fx` — PercTex (p25/p50/p75) as potential scene-adaptive input

## What to investigate

1. **Current weight function — numerical properties.** At luma values 0, 0.02, 0.05, 0.10,
   0.20, 0.30: what is the current lift amount at SHADOW_LIFT=12? This quantifies the gray
   floor problem precisely.

2. **Candidate weight functions.** Evaluate at the same luma values:
   - Option A: `luma * smoothstep(0.4, 0.0, luma)` — multiplicative bell
   - Option B: `luma * (1.0 - luma / 0.4)` — simpler linear bell
   - Derive the peak luma and peak value for each candidate analytically.

3. **Scaling constant K.** For the preferred candidate, find K such that the lift at
   luma=0.20 with SHADOW_LIFT=12 matches the current lift at luma=0.20. This preserves
   the knob's feel at the mid-shadow point while fixing the black floor.

4. **Implicit scene adaptivity.** Does the bell weight function provide automatic adaptivity
   across game scenes without needing PercTex? Specifically: in a very dark scene (many pixels
   near 0), does the bell lift behave more conservatively than the current flat weight?
   Compare: lift applied at luma=0.05 (near-black) old vs new. Is this enough, or is an
   explicit p25-based gate needed?

5. **Pipeline interaction.**
   - FilmCurve toe: already lifts near-black slightly (R04 finding). Does the new bell weight
     create a cleaner role separation — FilmCurve handles near-black, bell lift handles mid-shadow?
   - Zone S-curve (dark zones): for a zone with median 0.15, the S-curve enhances internal
     contrast, and shadow lift then adds a mid-shadow bump. Do they still stack benignly?
   - Clarity: its mask is `smoothstep(0.0, 0.2, luma) * (1 - smoothstep(0.6, 0.9, luma))`.
     Shadow lift runs before clarity. Does the bell lift push pixels into the clarity-active
     zone in a way the old flat lift didn't? Is this beneficial or problematic?

6. **Game-agnostic robustness.** Characterize behavior in three scene types:
   - Bright scene (p25 > 0.25): shadows are a small fraction of pixels — both approaches
     are low-impact, but bell avoids graying the few deep shadows that exist
   - Normal scene (p25 ≈ 0.10): the common case
   - Dark scene (p25 < 0.05, e.g. horror game, night level): many pixels near black — old
     flat weight applies maximum lift to the largest pixel population; new bell is near-zero
     there. Is the effective lift in the 0.10–0.25 range still enough to reveal gradation?

## Output expected
- Table: current vs candidate lift amounts at key luma values (SHADOW_LIFT=12)
- Peak analysis: where each candidate peaks and by how much
- Recommended implementation: exact replacement lines for grade.fx Stage 2
- K constant value, derived not guessed
- Clear verdict on scene-adaptive gate: needed or not
- One-paragraph interaction summary
