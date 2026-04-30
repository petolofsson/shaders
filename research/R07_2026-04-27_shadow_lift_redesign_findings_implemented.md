# Research 07 — Shadow lift redesign — Findings

## 1. Current weight function — numerical analysis

`lift_w = smoothstep(0.4, 0.0, new_luma)` where `t = (0.4 - luma) / 0.4`, `lift_w = t²(3-2t)`.

Multiplier at SHADOW_LIFT=12: `(12/100) * 0.15 = 0.018`.

| luma  | lift_w | current lift (+) | new_luma | problem |
|-------|--------|-----------------|----------|---------|
| 0.000 | 1.000  | +0.0180         | 0.018    | black → visible gray |
| 0.020 | 0.993  | +0.0179         | 0.038    | 2% pixel → 4% |
| 0.050 | 0.957  | +0.0172         | 0.067    | near-black → 3x higher |
| 0.100 | 0.844  | +0.0152         | 0.115    | 15% lift |
| 0.200 | 0.500  | +0.0090         | 0.209    | mid-shadow reference |
| 0.300 | 0.156  | +0.0028         | 0.303    | upper shadow minor |

The gray floor problem is precisely this: at luma=0.00, lift is 0.018. At luma=0.05, lift is still
0.017. The weight barely discriminates between pure black and mid-shadow. A gray scene is not just
a subjective impression — it is the mathematically correct result of applying a near-uniform offset
to all dark pixels.

## 2. Candidate weight functions

### Option A: `new_luma * smoothstep(0.4, 0.0, new_luma)` — multiplicative bell

`lift_w_A = luma * smoothstep(0.4, 0.0, luma)`

| luma  | lift_w_A |
|-------|----------|
| 0.000 | 0.0000   |
| 0.020 | 0.0199   |
| 0.050 | 0.0479   |
| 0.100 | 0.0844   |
| 0.200 | 0.1000   |
| 0.300 | 0.0469   |

**Peak derivation.** Let `t = (0.4 - luma) / 0.4`, so `luma = 0.4(1-t)` and
`lift_w_A = 0.4(1-t) * t²(3-2t)`. Setting `d/dt = 0`:
`(1-t)(6t - 6t²) + t²(3-2t)(-1) = 0` → `8t³ - 9t² + 1 = 0` → `t ≈ 0.578` → `luma ≈ 0.169`.
Peak value: `0.169 * smoothstep(0.4, 0, 0.169) ≈ 0.169 * 0.615 ≈ 0.104`.

Peak is at luma **≈ 0.17** — deep shadow, exactly where gradation needs revealing.

### Option B: `new_luma * (1.0 - new_luma / 0.4)` — linear bell

`lift_w_B = luma * (1 - luma/0.4)`

Peak at `d/dx [x(1-x/0.4)] = 0` → `x = 0.20`. Peak value: `0.20 * 0.50 = 0.100`.

Option B peaks at 0.20 — higher in the shadow range, less relief in deep shadow.
Option A is preferred: it concentrates lift lower (0.17) where tonal separation is most needed
and tapers off smoothly in both directions.

## 3. Scaling constant K

Match lift at luma=0.20 between old and new at SHADOW_LIFT=12:

Old: `(12/100) * 0.15 * 0.500 = 0.009`
New A: `(12/100) * K * 0.100 = 0.009` → **K = 0.75**

New multiplier: `(SHADOW_LIFT / 100.0) * 0.75` vs old `(SHADOW_LIFT / 100.0) * 0.15`.

Full comparison at SHADOW_LIFT=12 (multiplier = 0.09):

| luma  | old lift | new lift (K=0.75) | ratio new/old | new_luma |
|-------|----------|-------------------|---------------|----------|
| 0.000 | +0.0180  | +0.0000           | 0×            | 0.000    |
| 0.020 | +0.0179  | +0.0018           | 0.10×         | 0.022    |
| 0.050 | +0.0172  | +0.0043           | 0.25×         | 0.054    |
| 0.100 | +0.0152  | +0.0076           | 0.50×         | 0.108    |
| 0.169 | +0.0124  | +0.0094           | 0.76×  ← peak | 0.178    |
| 0.200 | +0.0090  | +0.0090           | 1.00×  ← match| 0.209    |
| 0.300 | +0.0028  | +0.0042           | 1.50×         | 0.304    |

The new lift is dramatically less at near-black (4–10× less) and approximately equal or slightly
greater at mid-shadow (0.20–0.30). The knob feel at the region the user tunes for (mid-shadow
visibility) is preserved. The black floor is eliminated.

## 4. Scene adaptivity — no explicit gate needed

The bell is implicitly scene-adaptive through its proportional-to-luma behavior:

**Dark scene (horror game, night level, p25 < 0.05):** Most pixels near 0. Old weight applies
full 0.018 lift uniformly — entire image lifts gray. New weight applies 0–0.004 at luma ≤ 0.05.
Deep black scenes stay deep. Mid-shadow (0.15–0.25) still gets ~0.008 lift where detail exists.

**Normal scene (Arc Raiders, p25 ≈ 0.10–0.15):** Pixel distribution centered in mid-shadow range.
Bell peaks at 0.17 — directly in the most populated shadow region. Maximum lift applied where it
is most needed.

**Bright scene (p25 > 0.25, outdoor / day):** Few pixels below 0.3. Both approaches are low-impact,
but old lifts the rare deep black (e.g. a window frame, unlit corner) to 0.018 gray. New leaves
it at 0 or near it. Correct behavior.

No p25 gate is needed. The functional form provides adaptivity by construction.

## 5. Pipeline interactions

**FilmCurve toe:** R04 confirmed FilmCurve lifts near-black by ~0.005–0.010. The old flat lift
then added 0.018 on top — double-stacking at luma=0. The new bell is near-zero at luma < 0.05.
FilmCurve handles near-black recovery; bell lift handles mid-shadow reveal. Roles are now
explicitly separated rather than accidentally additive at the bottom.

**Zone S-curve (dark zones):** For a zone with median ~0.15, the IQR-scaled S-curve (R02) already
enhances internal contrast. The bell lift then adds ~0.009 at luma 0.17–0.20 — just above the
zone median. This is complementary: zone S-curve provides contrast around the local median, bell
lift provides a global mid-shadow elevation. With the old flat lift, dark zone pixels near luma=0.02
received 0.018 lift regardless of zone context. With the bell, near-black pixels in dark zones
stay anchored to their context, and the lift activates where local contrast already reveals detail.

**Clarity:** Shadow lift runs before Clarity. Clarity mask: `smoothstep(0.0, 0.2, luma)`. In the
old system, luma=0.02 → 0.038 (fully inside clarity onset). Near-black pixels pulled into the
clarity-active zone where they have no meaningful detail — Clarity adds noise there. With new bell:
luma=0.02 → 0.022, barely entering clarity onset. Near-black detail avoidance is improved without
changing Clarity itself.

**No conflicts identified.** All interactions are improved or neutral.

## 6. Game-agnostic robustness

The gray floor problem is worst in dark games. The old lift sets a scene-independent floor of 0.018
at SHADOW_LIFT=12 — identical behavior in any game. In a horror or stealth game where deep black
is part of the intended visual language, the current lift destroys it.

The new bell is inherently game-agnostic: it scales with scene content. A game that intentionally
uses near-black gets near-zero lift there. A game that has rich mid-shadow detail (Arc Raiders:
metal surfaces, directional occlusion, shadowed geometry) gets the lift exactly where those tones
live. No per-game SHADOW_LIFT re-tuning needed for the black floor problem — it is solved by the
function shape.

## Recommended implementation

Two-line change in `general/grade/grade.fx` Stage 2:

```hlsl
// Replace:
float lift_w = smoothstep(0.4, 0.0, new_luma);
new_luma     = saturate(new_luma + (SHADOW_LIFT / 100.0) * 0.15 * lift_w);

// With:
float lift_w = new_luma * smoothstep(0.4, 0.0, new_luma);
new_luma     = saturate(new_luma + (SHADOW_LIFT / 100.0) * 0.75 * lift_w);
```

Changes: multiply `lift_w` by `new_luma`, update ceiling from 0.15 → 0.75.

The SHADOW_LIFT knob semantics are preserved at mid-shadow (0.20). No changes needed in
`creative_values.fx` except optionally updating the comment from "raise dark tones toward grey"
to reflect the new behavior.
