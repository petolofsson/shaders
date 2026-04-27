# Gate-Free Chroma Design — Research Notes

Shader: `general/creative-color-grade/creative_color_grade.fx`, branch `alpha`
Context: vkBasalt HLSL chain, SDR, Oklab-based, Arc Raiders on Linux

---

## 1. Gate Inventory with Algebraic Analysis

### Gate A — Outer chroma gate

```hlsl
if (C >= SAT_THRESHOLD / 100.0)   // SAT_THRESHOLD = 2 → threshold = 0.02
```

**Protecting:**
1. `atan2`-based angle reconstruction at `C ≈ 0`
2. `new_C / total_w` division
3. Implicit: prevents `PivotedSCurve` from compressing low-chroma colours to zero

**Algebraic analysis of `PivotedSCurve` at `x = 0`:**

```
t    = 0 − m = −m
bent = −m + str·(−m)·(1 − |m|) = −m·(1 + str·(1−m))
out  = sat(m − m·(1 + str·(1−m))) = sat(−m·str·(1−m)) = 0
```

For any `m ∈ (0,1)` and `str ≥ 0`, `PivotedSCurve(0, m, str) = 0`. The function returns 0 at `x = 0`.

At the pivot `x = m`: `t = 0`, result = `sat(m)` = `m`. Fixed point.

**Consequence:** When `C = 0`, each band contributes `PivotedSCurve(0, …) · w = 0`, so `new_C = 0` and `final_C = 0`. The output would be `OklabToRGB(L, 0, 0)` — a neutral grey — which desaturates any colour whose C falls below the S-curve's natural zero region (roughly `C < str·m·(1−m)`). This is **not** identity; it is the real reason the outer gate exists.

Fix: `final_C = max(lifted_C, C)` makes the effect lift-only, restoring identity at small C by construction. With that floor in place, plus vector-space reconstruction eliminating the `atan2` hazard, the outer gate is unnecessary.

---

### Gate B — `total_w` division guard

```hlsl
float final_C = (total_w > 0.001) ? new_C / total_w : C;
```

**Protecting:** division by zero when no band covers the current hue.

**Analysis:** The live `HueBandWeight` is a **linear tent** (not a smoothstep):

```hlsl
return saturate(1.0 - d / (BAND_WIDTH / 100.0));
```

With `BAND_WIDTH = 8` (0.08 hue units), adjacent band centres are spaced 0.09–0.22 units apart. Many hue angles lie outside all six bands → `total_w = 0` is real. The fallback to `C` (no change) is correct. **This guard is necessary.** It could be written `(total_w > 0.0)` without loss.

---

### Gate C — `hk_factor` hard threshold

```hlsl
float hk_factor = (final_C > 0.05 && C > 0.05) ? pow(C / final_C, 0.15) : 1.0;
```

**Protecting:** `pow(0/0, 0.15)` undefined; preventing HK correction on near-achromatic pixels.

**Analysis:** At `C = 0.05` the correction can be anywhere in (0, 1] depending on how much chroma was boosted; the jump from `hk_raw` to `1.0` is discontinuous → confirmed ring source. Smooth replacement in §3.

---

### Gate D — Density bell curve

```hlsl
float c_shadow = smoothstep(0.0, 0.15, final_L) * (1.0 - smoothstep(0.55, 0.85, final_L));
```

**Protecting:** prevents density darkening in deep shadows and bright highlights.

**Analysis:** The highlight rolloff is a proxy for gamut proximity — bright, saturated pixels are near the sRGB boundary. But luminance is a crude proxy: the actual boundary depends on both L and C and varies by hue. `final_L = 0.55` is not a principled cutoff; it prematurely kills density "body" on bright saturated surfaces. The shadow floor (`< 0.15`) prevents over-darkening already-dark pixels, but again `delta_C` is already near zero there so the gate is redundant. Replaced by headroom probe in §4.

---

### Gate E — Gamut clip `if (rmax > 1.0)`

```hlsl
float rmax = max(chroma_rgb.r, max(chroma_rgb.g, chroma_rgb.b));
if (rmax > 1.0) { … }
```

**Necessary.** `OklabToRGB` can produce values > 1 after chroma boost. The compressor fires only when needed and is correct. Keep as-is.

---

### Gate F — Film matrix `fm_gate`

```hlsl
float fm_chroma = (fm_max > 0.001) ? (fm_max - fm_min) / fm_max : 0.0;
float fm_gate   = smoothstep(FILM_CHROMA_LO, FILM_CHROMA_HI, fm_chroma)
                * smoothstep(FILM_LUMA_LO,   FILM_LUMA_HI,   fm_luma);
```

Both smoothstep transitions are already soft. The `(fm_max > 0.001)` guard prevents division by zero; it could be replaced with `max(fm_max, 0.001)` in the denominator without visual impact. Not a seam source.

---

### Gate G — Tint saturation gates (`tt_gate`, `st_gate`)

```hlsl
float tt_gate = smoothstep(0.14, 0.27, tt_sat);   // toe tint
float st_gate = smoothstep(0.08, 0.22, st_sat);   // shadow tint
```

Smoothstep onset on saturation; self-limiting. Not seam sources.

---

### Gates H — Compile-time branches

```hlsl
if (CREATIVE_SATURATION != 1.0) { … }
if (CREATIVE_CONTRAST   != 1.0) { … }
```

Uniform-constant branches — eliminated by the compiler when the value equals 1. Fine as-is.

---

### Gates I — Numerical division guards

```hlsl
max(luma, 0.001)
max(Luma(result), 0.001)
max(rmax - L_grey, 0.001)
```

Necessary floating-point safety. No visual impact.

---

## 2. Vector-Space Reconstruction of (a, b)

### Problem

The current output direction is computed as:

```hlsl
float h_rad    = atan2(lab.z, lab.y);            // noisy at C ≈ 0
float h_nudged = h_rad + <angle corrections>;
float f_oka    = final_C * cos(h_nudged);
float f_okb    = final_C * sin(h_nudged);
```

When `C → 0`, `h_rad = atan2(0+ε, 0+ε)` is floating-point noise. The `final_C → 0` multiplier drives the output toward zero, but the cos/sin reconstruction still executes on a garbage angle. The corrections (green hue nudge, Abney) are also expressed in angle space, making the output direction undefined at `C = 0`.

### Formulation

The green nudge and Abney corrections are small rotations proportional to `final_C`. A 2D rotation by angle `dθ` applied to a Cartesian vector `(a_s, b_s)` is exact and requires no `atan2`:

```
f_oka = a_s · cos(dθ) − b_s · sin(dθ)
f_okb = a_s · sin(dθ) + b_s · cos(dθ)
```

The scaling step `(a_in, b_in) → (a_s, b_s)` replaces magnitude `C` with `final_C`:

```
(a_s, b_s) = (lab.y, lab.z) · (final_C / C)
```

**Self-limiting proof:** At `C = 0`, `(lab.y, lab.z) = (0, 0)`, so `(a_s, b_s) = (0, 0)` regardless of the scale factor, and `(f_oka, f_okb) = (0, 0)` regardless of `dθ`. No `atan2` is needed for the output direction.

`h = OklabHueNorm(lab.y, lab.z)` is still computed for band weight inputs. At `C ≈ 0` its value is noisy, but all weights are multiplied through `final_C → 0`, so the noisy hue has no effect on the output.

### Code

```hlsl
// Scale (a,b) to final_C — Cartesian, no atan2
float2 ab_in  = float2(lab.y, lab.z);
float  C_safe = max(C, 1e-6);
float2 ab_s   = ab_in * (final_C / C_safe);

// Rotation angle — both terms ∝ final_C → 0 at C = 0
float abney  = (-HueBandWeight(h, BAND_BLUE)   * 0.08
               - HueBandWeight(h, BAND_CYAN)   * 0.05
               + HueBandWeight(h, BAND_YELLOW) * 0.05) * final_C;
float dtheta = -(GREEN_HUE_COOL * 2.0 * 3.14159265) * green_w * final_C + abney;

// Exact 2D rotation in Cartesian — no atan2 needed
float cos_dt = cos(dtheta);
float sin_dt = sin(dtheta);
float f_oka  = ab_s.x * cos_dt - ab_s.y * sin_dt;
float f_okb  = ab_s.x * sin_dt + ab_s.y * cos_dt;
```

**Note on approximation:** `dtheta` is not linearised — this is an exact rotation. For the typical magnitudes involved (green nudge `GREEN_HUE_COOL · 2π · final_C ≈ 0.07 · final_C` rad, Abney ≤ 0.08·final_C rad) the small-angle approximation would also be fine, but the exact form costs nothing extra.

---

## 3. Smooth `hk_factor`

### Current (broken)

```hlsl
float hk_factor = (final_C > 0.05 && C > 0.05) ? pow(C / final_C, 0.15) : 1.0;
```

Discrete jump from `hk_raw` to `1.0` at the 0.05 boundary → ring artefact confirmed.

### Replacement

```hlsl
float hk_blend  = smoothstep(0.0, 0.10, C) * smoothstep(0.0, 0.10, final_C);
float hk_raw    = pow(max(C / max(final_C, 1e-6), 0.001), 0.15);
float hk_factor = lerp(1.0, hk_raw, hk_blend);
```

**Self-limiting proof:**
- `C = 0` → `hk_blend = 0` → `hk_factor = 1.0`. Identity.
- `C > 0.10` and `final_C > 0.10` → `hk_blend = 1.0` → `hk_factor = hk_raw`. Matches original behaviour.
- Transition is `C²(3−2C)` (smoothstep), continuous and differentiable across [0, 0.10].

The blend window [0, 0.10] vs the old threshold 0.05 means the correction is fully applied slightly later. This is intentional — HK is not perceptually meaningful at very low chroma, and the wider ramp avoids any visible onset.

---

## 4. Gate-Free Density via Gamut-Distance Headroom

### Problem

```hlsl
float c_shadow  = smoothstep(0.0, 0.15, final_L) * (1.0 - smoothstep(0.55, 0.85, final_L));
float density_L = saturate(final_L - delta_C * c_shadow * (DENSITY_STRENGTH / 100.0));
```

The bell curve suppresses density in highlights as a proxy for gamut proximity. It is too aggressive: at `final_L = 0.6`, `c_shadow ≈ 0.3`, and at `final_L = 0.7`, `c_shadow ≈ 0.07` — density body on bright saturated surfaces is gone before the gamut boundary is reached.

### Gamut-distance formulation

After computing `(final_L, f_oka, f_okb)`, probe the RGB gamut before applying darkening:

```hlsl
float3 rgb_probe  = OklabToRGB(float3(final_L, f_oka, f_okb));
float  rmax_probe = max(rgb_probe.r, max(rgb_probe.g, rgb_probe.b));
float  headroom   = saturate(1.0 - rmax_probe);
float  delta_C    = max(final_C - C, 0.0);
float  density_L  = saturate(final_L - delta_C * headroom * (DENSITY_STRENGTH / 100.0));
```

**Self-limiting proof:**
- `rmax_probe → 1` (gamut boundary) → `headroom → 0` → density = 0. No darkening when already clipping.
- `rmax_probe = 0.6` (mid-gamut, e.g. `final_L = 0.5`, moderate C) → `headroom = 0.4`. Full density body present.
- `C → 0` → `delta_C = 0` → `density_L = final_L`. Identity.
- Shadows: low-L, low-C pixels have small `rmax_probe` → large headroom, but `delta_C` is also near zero (little chroma was boosted). The actual darkening is limited by the chroma delta, not a luminance floor.

**On preserving body:** A bright saturated pixel (`final_L = 0.65`, `final_C = 0.25`) might convert to `rmax_probe ≈ 0.88`, giving `headroom = 0.12`. This is less darkening than the old bell curve at that L, but it is conditional on actual gamut proximity. A same-L pixel with `final_C = 0.15` (smaller boost, `rmax_probe ≈ 0.75`) gets `headroom = 0.25` and more density body. The effect is now physically motivated rather than heuristic.

**Cost:** one additional `OklabToRGB` call (one matrix multiply + cube roots). Acceptable in a full-screen post-process pass.

---

## 5. Complete Revised Chroma Block

Drop-in replacement for the `// ── 3. Oklab chroma lift ──` section in `MegaPassPS`.

```hlsl
    // ── 3. Oklab chroma lift ──────────────────────────────────────────────────
    float3 lab = RGBtoOklab(lin);
    float  C   = length(lab.yz);
    float  h   = OklabHueNorm(lab.y, lab.z);

    float hunt_scale = lerp(0.7, 1.3, saturate((perc.g - 0.15) / 0.50));
    float chroma_str = saturate(CHROMA_STRENGTH / 100.0 * hunt_scale);

    float new_C = 0.0, total_w = 0.0, green_w = 0.0;
    for (int band = 0; band < 6; band++)
    {
        float w     = HueBandWeight(h, GetBandCenter(band));
        float4 hist = tex2D(ChromaHistory, float2((band + 0.5) / 8.0, 0.5 / 4.0));
        new_C   += PivotedSCurve(C, hist.r, chroma_str) * w;
        total_w += w;
        if (band == 2) green_w = w;
    }
    // max(lifted, C) — lift-only; identity limit at C = 0 by construction
    float lifted_C = (total_w > 0.001) ? new_C / total_w : C;
    float final_C  = max(lifted_C, C);

    // Vector-space (a,b) reconstruction — no atan2 needed for output direction
    float2 ab_in  = float2(lab.y, lab.z);
    float  C_safe = max(C, 1e-6);
    float2 ab_s   = ab_in * (final_C / C_safe);

    float abney  = (-HueBandWeight(h, BAND_BLUE)   * 0.08
                   - HueBandWeight(h, BAND_CYAN)   * 0.05
                   + HueBandWeight(h, BAND_YELLOW) * 0.05) * final_C;
    float dtheta = -(GREEN_HUE_COOL * 2.0 * 3.14159265) * green_w * final_C + abney;
    float cos_dt = cos(dtheta);
    float sin_dt = sin(dtheta);
    float f_oka  = ab_s.x * cos_dt - ab_s.y * sin_dt;
    float f_okb  = ab_s.x * sin_dt + ab_s.y * cos_dt;

    // Smooth HK luminance correction — continuous onset, no discrete ring
    float hk_blend  = smoothstep(0.0, 0.10, C) * smoothstep(0.0, 0.10, final_C);
    float hk_raw    = pow(max(C / max(final_C, 1e-6), 0.001), 0.15);
    float hk_factor = lerp(1.0, hk_raw, hk_blend);
    float final_L   = saturate(lab.x * hk_factor);

    // Gamut-distance density: headroom limits darkening near the sRGB boundary
    float3 rgb_probe  = OklabToRGB(float3(final_L, f_oka, f_okb));
    float  rmax_probe = max(rgb_probe.r, max(rgb_probe.g, rgb_probe.b));
    float  headroom   = saturate(1.0 - rmax_probe);
    float  delta_C    = max(final_C - C, 0.0);
    float  density_L  = saturate(final_L - delta_C * headroom * (DENSITY_STRENGTH / 100.0));

    float3 chroma_rgb = OklabToRGB(float3(density_L, f_oka, f_okb));
    float  rmax       = max(chroma_rgb.r, max(chroma_rgb.g, chroma_rgb.b));
    if (rmax > 1.0)
    {
        float L_grey = dot(chroma_rgb, float3(0.2126, 0.7152, 0.0722));
        float gclip  = (1.0 - L_grey) / max(rmax - L_grey, 0.001);
        chroma_rgb   = L_grey + gclip * (chroma_rgb - L_grey);
    }
    lin = saturate(chroma_rgb);
```

**Constraints satisfied:**
- No `static const float[]` — band centres via `GetBandCenter()` using `#define` literals, unchanged.
- No variable named `out`.
- SDR — all outputs in [0, 1] via `saturate` and the gamut clip.
- No new `#define`s — all knobs already in `creative_values.fx`.
- The outer `if (C >= SAT_THRESHOLD / 100.0)` gate is gone. Behaviour at `C = 0`: `final_C = max(0, 0) = 0`, `ab_s = (0, 0)`, `f_oka = f_okb = 0`, `delta_C = 0`, `density_L = final_L = lab.x`. Output = `OklabToRGB(lab.x, 0, 0)` = input (achromatic pass-through).
- Local variable `t` from the gamut clip renamed `gclip` (avoids any reserved-word ambiguity in SPIR-V cross-compilation).

---

## 6. Full Gate Survey of MegaPassPS

| # | Section | Gate | Type | Status |
|---|---------|------|------|--------|
| 1 | Entry | `if (pos.y < 1.0) return col` | Hard return | **Keep** — data highway guard |
| 2 | Chroma | `if (C >= SAT_THRESHOLD / 100.0)` | Hard branch | **Remove** — see §2 + §5 |
| 3 | Chroma | `(total_w > 0.001) ? new_C/total_w : C` | Scalar ternary | **Keep** — bands have real gaps at BAND_WIDTH=8 |
| 4 | Chroma | `(final_C > 0.05 && C > 0.05) ? pow(…) : 1.0` | Hard branch | **Replace** — ring source, see §3 |
| 5 | Chroma | `smoothstep(0,0.15,L)·(1−smoothstep(0.55,0.85,L))` | Soft bell | **Replace** — see §4 |
| 6 | Chroma | `if (rmax > 1.0)` gamut clip | Hard branch | **Keep** — SDR compliance |
| 7 | Film | `(fm_max > 0.001) ? … : 0.0` | Division guard | Replace with `max(fm_max, 0.001)` denom — no visual impact |
| 8 | Film | `fm_gate = smoothstep(…) · smoothstep(…)` | Soft gate | Self-limiting; fine |
| 9 | Toe tint | `tt_gate = smoothstep(0.14, 0.27, tt_sat)` | Soft gate | Self-limiting; fine |
| 10 | Black lift | `1.0 − smoothstep(0.0, 0.10, result_luma)` | Soft weight | Self-limiting; fine |
| 11 | Shadow tint | `st_gate = smoothstep(0.08, 0.22, st_sat)` | Soft gate | Self-limiting; fine |
| 12 | Highlight | `hl_t = smoothstep(HIGHLIGHT_START/100, 1.0, luma)` | Soft gate | Self-limiting at L=1; fine |
| 13 | Zone contrast | `smoothstep(0.4, 0.0, new_luma)` shadow lift | Soft weight | Self-limiting; fine |
| 14 | Clarity | `smoothstep(0,0.2,luma)·(1−smoothstep(0.6,0.9,luma))` | Soft bell | Self-limiting; fine |
| 15 | Grade | `if (CREATIVE_SATURATION != 1.0)` | Compile-time | Fine |
| 16 | Grade | `if (CREATIVE_CONTRAST != 1.0)` | Compile-time | Fine |
| 17 | Throughout | `max(x, 0.001)` division guards | Numeric guard | **Keep** |
| 18 | Debug | `if (pos.y >= 10 && pos.y < 22 && pos.x >= …)` | Debug branch | Fine |

**Summary:** Gates 2, 4, 5 are the seam/ring sources. Gate 3 is necessary and benign. Gate 6 and the `max` guards (17) are necessary for correctness. Gates 7–16 are either smooth (no seam risk) or compile-time eliminations.
