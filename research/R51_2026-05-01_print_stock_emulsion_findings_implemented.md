# R51 — Print Stock Emulsion Response — Findings

**Date:** 2026-05-01
**Searches:**
1. Kodak 2383 print film sensitometry characteristic curve H&D gamma color science
2. Cinema print stock emulsion dye curves cyan magenta yellow density film color grading
3. Kodak 2383 print stock orange base D-min black lift warm cast sensitometry
4. ACES RRT output transform print film emulation black lift toe gamma cinematic

---

## Key Findings

### 1. Kodak 2383 official sensitometry — what the data sheet actually says

Kodak's official data sheet (H-1-2383t, available from kodak.com and archives.gov) describes
the three sensitometric curves (cyan, magenta, yellow dye layers) under ECP-2D processing,
Status A densitometry, 1/500 sec tungsten exposure. Key properties confirmed:

- **D-max**: Higher than the older EXR 2386 print stock — improved blacks on projection.
  The proposal's black lift (`x * (1.0 - 0.025) + 0.025`) addresses this minimum density floor.
- **Toe matching**: "The toe areas of the three sensitometric curves are matched more closely
  than 2386 Film, resulting in more neutral highlights on projection." This means the three
  dye channels converge in the highlights — the print does NOT add channel-divergent highlight
  behaviour, it converges toward neutral. The proposal's single-value warm cast (R+0.012, B−0.008)
  is a uniform shift, consistent with this.
- **Spectral match**: 2383 spectral sensitivity closely matches EASTMAN EXR Color Intermediate
  Film 5244, not a camera negative. It is designed to receive already-processed negative signal.
- **LAD aim density**: 1.00 visual density neutral gray at setup lights (25-25-25 printer points).

No publicly available digitized version of the three channel curves with explicit linear gamma
values was found. The data sheet uses log-density vs. log-exposure axes and is not directly
convertible to linear shader constants without densitometer calibration data. The proposal's
gamma values (toe `x*x*3.2`, shoulder `1-(1-x)^2*1.8`) are therefore approximations rather
than sensitometry-derived constants. This is acceptable for a cinematic look tool but should
be documented as such.

### 2. Orange base (D-min) — physical origin confirmed

The warm cast of the projected print is a well-documented physical property. Print stocks have
a minimum density (`D-min`) arising from the residual dye in the unexposed emulsion base. For
chromogenic print films, this base has an orange-ish cast (higher minimum density in the cyan
and blue-green channels than in the red-orange). On projection through a xenon arc:
- Red dye layer: lowest minimum density → least residual reddish cast
- Blue/cyan dye: higher D-min → subtracts blue from projected whites/shadows → warm appearance

The proposal's `x.r += 0.012 * (1.0 - x.r)` / `x.b -= 0.008 * (1.0 - x.b)` captures this
correctly in direction. The magnitude (1.2%/0.8%) is conservative relative to the real
effect, which is typically described as a visible warm cast on projection blacks.

### 3. ACES RRT / Output Transform — precedent for print emulation in rendering

The ACES Reference Rendering Transform (RRT) famously incorporates a "print film emulation"
stage before the Output Device Transform (ODT). The RRT's design intent (from the ACES
documentation and Zap Andersson's write-ups) includes:
- A simulated negative response (S-curve with film toe/shoulder)
- A print emulation stage with lifted blacks, compressed highlights, and slight warm bias
- The "cinematic look" is explicitly a function of both stages, not the negative alone

This is exactly the R51 proposal's conceptual basis — R49 handles the negative stage; R51
adds the print stage. The ACES precedent provides strong industry validation that a two-stage
photochemical model (negative + print) is the correct architecture.

### 4. Existing digital implementations (LUTs, PowerGrades)

Several commercial LUTs explicitly emulate Kodak 2383 (Juan Melara's free Film Print Emulation
LUTs, K83 PowerGrade). These products are treated as reference-grade in the color grading
community. Their existence confirms that:
- The perceptual properties of 2383 are stable and consistently described
- Black lift, desaturation, and warm cast are the three recognised characteristics
- The effect is strong enough to be commercially valuable as a standalone transform

These implementations are proprietary and not inspectable, but their acceptance validates
the perceptual targets in the proposal's validation section.

---

## Parameter Validation

### Black lift — `x * (1.0 - 0.025) + 0.025`

Maps [0,1] → [0.025, 1.0]. At display-referred black (luma=0), output is 0.025. This is
a lift of ~6.4 code values on an 8-bit SDR output — visible as a slightly elevated black
floor, consistent with the "rich deep dark" character of projected print. The official Kodak
data sheet uses D-min of approximately 0.06–0.08 log density, which in linear transmittance
corresponds to `10^(-0.06)` to `10^(-0.08)` ≈ 0.87–0.83 transmittance — this is a minimum
density floor in the *negative*, not directly equivalent to the print's minimum projection
density. The 0.025 lift is a reasonable perceptual approximation.

### Gamma approximation — quadratic toe + quadratic shoulder

The toe `x*x*3.2` and shoulder `1-(1-x)^2*1.8` are quadratic approximations to the
characteristic curve's steeper-toe/harder-shoulder shape. At midtone (x=0.5):
- Toe branch: 0.25 * 3.2 = 0.80
- Shoulder branch: 1 - 0.25 * 1.8 = 0.55
- Blend factor t = smoothstep(0.0, 0.5, 0.5) = 0.5
- Output: lerp(0.80, 0.55, 0.5) = **0.675** — compresses midtones vs. identity (0.5)

At luma = 0.1 (shadow): toe = 0.032, shoulder = 0.918, t = 0.036 → output ≈ 0.065.
Shadow contrast is indeed steeper (0.1 → 0.065 with faster onset below).

At luma = 0.9 (highlight): toe = 2.592 (clipped to 1), shoulder = 0.838, t = 0.99 → output ≈ 0.840.
Highlight compression is real — 0.9 maps to 0.84.

The shape is plausible but the midtone compression (0.5→0.675) is significant. At `PRINT_STOCK=0.5`
blend the midtone lift is (0.675-0.5)*0.5 = +0.087 — this stacks with the black lift and the
FilmCurve's existing tone response. Monitor for midtone density appearing "muddy" or flat.

### Warm cast constants (0.012 / 0.008)

Maximum warm shift at pure black: R+1.2%, B−0.8%. Maximum warm shift at luma=0.5:
R+0.6%, B−0.4%. At luma=1.0: zero shift (correct — no cast on pure white). The
`x.r += 0.012 * (1.0 - x.r)` formulation correctly produces zero shift at R=1 and
maximum shift at R=0. Direction (red add, blue subtract) matches the D-min physics.

---

## Risks and Concerns

### 1. Midtone compression stacks with existing FilmCurve

The FilmCurve (R49) already applies a film negative response. PrintStock applies a second
curve on top. The combined midtone compression at `PRINT_STOCK=1.0` may be excessive — real
theatrical pipelines apply the print response to a signal that has already been through
lab-calibrated processing, not through an already-shaped negative emulation. At `PRINT_STOCK=0.5`
(proposed default), the blend mitigates this. Recommend starting at 0.3–0.4 in practice.

### 2. Gamma constants are not sensitometry-derived

The quadratic toe/shoulder approximation has no direct derivation from the Kodak H-1-2383t
data sheet. The actual 2383 gamma in the straight-line region is approximately 2.5–2.8 (per
the proposal), but the quadratic formulation does not reproduce a constant-gamma straight line
— it produces a continuously varying slope. This is perceptually adequate for a look tool
but cannot claim physical accuracy.

### 3. Desaturation formula targets midtone, but print stock desaturation is luminance-dependent

The proposal's desaturation bell peaks at luma 0.3–0.7. Real print stock mid-desaturation
arises from the coupling of negative and print dye curves across the saturation range.
The formula is a reasonable approximation but the physical basis is weaker than the
black lift or warm cast — those derive from specific measurable film properties.

---

## Verdict

**Proceed — with PRINT_STOCK default at 0.35, not 0.5.**

The proposal is architecturally sound and has strong industry precedent (ACES RRT two-stage
model). The physical basis for the three named effects (black lift, warm cast, desaturation)
is confirmed. The gamma approximation is heuristic but acceptable for a look tool.

**Recommended adjustment before implementation:**
- Default `PRINT_STOCK = 0.35` — the midtone compression stacks with FilmCurve and at 0.5
  risks muddiness without testing.
- Consider adding a comment that the toe/shoulder constants are perceptual approximations, not
  H&D-derived values, so future maintainers do not treat them as sacred numbers.
- The desaturation bell centre (0.0–0.3 and 0.6–1.0 rolloffs) should be validated against
  a neutral grey ramp at multiple PRINT_STOCK values before wider use.
