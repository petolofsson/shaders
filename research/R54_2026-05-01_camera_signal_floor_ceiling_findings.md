# R54 — Camera Signal Floor / Ceiling — Findings

**Date:** 2026-05-01
**Searches:**
1. ARRI LogC3 LogC4 black point code value 64 1023 linear light signal floor specification
2. RED Log3G10 black point linear offset signal floor white paper IPP2
3. Sony S-Log3 black point code value 64 IRE 8 signal floor specification
4. camera log format black point linear light value sensor noise floor physical rationale
5. ARRI LogC3 formula linear to log encoding constants cut1 a b c d e f
6. log to linear SDR display black point remap linear light percentage

---

## Key Findings

### 1. Published black point values — code-value percentages vs. linear light

All three major log formats lift their code-value black point well above digital zero as a
design feature, but the relationship to linear light differs significantly from the
commonly cited percentage figures.

**ARRI LogC3 (ALEXA Classic / Mini / LF):**
- Code-value black: 64/1023 = **6.25%** of full scale (or 64/876 = **7.3%** of the
  usable range 64–940).
- Linear light at that code value: via the LogC3 piecewise formula (cut at ~0.010591),
  the input value that produces code 64 is approximately **0.001–0.003 linear** — near
  true scene black, not 7.3% in linear units.
- The lift is by design to accommodate sensor noise below this point (sub-black data).
- Middle grey (18%): code value 400/1023 ≈ 39.1%.
- Source: ARRI LogC Conversion (Technical Summary 2017), AbelCine documentation.

**ARRI LogC4 (ALEXA 35 / REVEAL Color Science):**
- Middle grey repositioned to ~28% (285/1023, 12-bit: 1140/4095) to exploit the wider
  dynamic range of the ALEV4 sensor.
- Black point not independently confirmed in searches; presumed similar code-value floor.
- Source: ARRI ALEXA 35 Workflow & Post Guide, ARRI REVEAL documentation.

**RED Log3G10 (IPP2 pipeline):**
- Encodes from **−0.01 linear** (below true black), using a linear offset `c = 0.01`.
- Signal floor in linear: effectively 0.01 below zero — the format deliberately encodes
  sub-zero to preserve sensor data. Normalized display floor ≈ **0% in linear** (true
  black is inside the usable range, not at the floor).
- 18% grey maps to 1/3 of maximum code value.
- White ceiling: 10 stops above mid-grey → linear ≈ 184×, compressed to code 1.0.
- Source: RED OPS White Paper 915-0187 Rev-C (Log3G10 and RWG encoding spec).

**Sony S-Log3:**
- Code-value black: 64/1023 = **6.25%** (8 IRE in video terms).
- Linear light at code 64: approximately **0.00003 linear** (scene-black maps to
  essentially 0 in linear; the lift is purely in the encoded domain).
- 18% grey: code value 420/1023 ≈ 41%.
- White ceiling: 88 IRE (code ≈ 900/1023).
- Source: Sony S-Log3 Technical Summary, Gamut.io, Wolfcrow.

**Critical summary:** The "7.3%" figure is a **code-value percentage**, not a linear light
value. In scene-linear, all three formats map their black floor to 0–0.003 linear —
effectively true black. Displaying log footage without a proper log→display transform causes
the elevated code values to appear as a grey floor; this is an encoding artifact, not a
physical sensor property at the linear light level.

---

### 2. Fixed constant or user knob?

The framing of R54 as a "physical camera property" does not apply to this pipeline. vkBasalt
receives and linearizes the game's sRGB swapchain — the source is not a camera log signal.
True 0 and true 1 in the BackBuffer are legitimate display-referred values from the game
renderer, not sensor noise or encoding headroom.

The proposed remap is therefore an **aesthetic black pedestal and highlight rolloff**, not a
physics-based correction. Relevant comparisons:

| Stage | Black lift | Mechanism |
|-------|-----------|-----------|
| R51 PRINT_STOCK (0.025) | +2.5% linear, blended by knob | Kodak 2383 D-min emulation |
| R54 proposal (0.07 linear) | +7% linear, unblended | "ARRI-style" — actually aesthetic |

Given this, a user knob (`FILM_FLOOR`, `FILM_CEILING`) is the correct surface — the "right"
value is aesthetic preference, not derivable from a spec. Hardcoding 0.07 would be
misleading and inflexible.

**However:** 0.07 linear is extremely strong in this pipeline. In linear-to-sRGB terms,
0.07 linear ≈ pow(0.07, 1/2.2) ≈ **28% display code value** — a clearly visible grey
pedestal with no blend control. For reference, PRINT_STOCK's 0.025 lift appears as a
~17% code value and is already blended at 20%. A 0.07 hard remap would visually crush
all blacks to medium-dark grey.

**Recommended floor:** 0.003–0.010 linear (matching the actual linear-light values of the
log format black floors, not the code-value percentages). This maps to ~4–9% display grey —
subtle and cinema-realistic.

---

### 3. Remap must occur before EXPOSURE

The remap `col.rgb * (CEILING - FLOOR) + FLOOR` must run **before** `pow(max(col.rgb, 0.0), EXPOSURE)`:

- `pow(0.0, EXPOSURE) = 0.0` always — true blacks survive EXPOSURE untouched, bypassing
  any subsequent intent to lift the floor.
- Applying the remap first, then EXPOSURE gamma, correctly models "the lifted floor value
  is part of the raw signal and therefore subject to the camera's characteristic response."
- At EXPOSURE = 1.1 and FLOOR = 0.003: `pow(0.003, 1.1) ≈ 0.0024` — a slight floor
  compression is physically appropriate (a brighter scene pushes the sensor noise relatively
  lower), not a bug.
- Insertion point: line 224 of `grade.fx`, after data-highway guard, before line 240
  (`FilmCurve / pow`).

---

### 4. Interaction with R51 PRINT_STOCK black lift

R51 applies `ps = lin * (1.0 - 0.025) + 0.025` after EXPOSURE + FilmCurve. The two lifts
stack independently:

| Scenario | True-black input path | Result at display |
|----------|----------------------|------------------|
| R54 alone (FLOOR=0.003, no PRINT_STOCK) | 0 → 0.003 → pow(0.003,1.0) → FilmCurve(0.003) ≈ 0.003 | ~4% grey |
| PRINT_STOCK alone (0.025, blend=0.20) | 0 → 0 → FilmCurve(0) = 0 → 0 * 0.975 + 0.025 = 0.025, blended: 0.20 × 0.025 = 0.005 | ~6% grey |
| R54 + PRINT_STOCK combined (both at moderate values) | 0 → 0.003 → ~0.003 → 0.003 * 0.975 + 0.025 = 0.028, blended: 0.20 × 0.028 + 0.80 × 0.003 ≈ 0.008 | ~8% grey |

They **do not fight** — they stack additively. The combined floor remains manageable at
conservative values. At aggressive values (FLOOR=0.07, PRINT_STOCK blend=1.0):
- Floor would land near 0.07 * 0.975 + 0.025 = 0.093 → 30% display grey — unacceptable.

**Risk:** At current tuning (PRINT_STOCK=0.20), the combined floor with FLOOR=0.003 is subtle.
At higher PRINT_STOCK or higher FILM_FLOOR, the interaction needs monitoring.

**Alternative path:** Absorb R54 into the existing PRINT_STOCK black lift constant (change
0.025 → 0.028 or similar), eliminating a separate stage. This avoids new knobs and keeps
the floor logic in one place. This is the lower-cost implementation option.

---

## Parameter Validation

### FILM_FLOOR candidate values

| FILM_FLOOR (linear) | sRGB display grey | Physical analogue |
|--------------------|-------------------|------------------|
| 0.001 | ~3% | RED Log3G10 actual linear black |
| 0.003 | ~5% | ARRI LogC3 linear black (accurate) |
| 0.007 | ~8% | Sony S-Log3 linear black (approximate) |
| 0.025 | ~17% | PRINT_STOCK existing lift |
| 0.070 | ~28% | **Proposal value — too strong for unblended hard remap** |

**Recommended value if implemented as a hard remap (no blend):** FILM_FLOOR = 0.003–0.005.
If implemented with a blend knob (like PRINT_STOCK), 0.025–0.05 is tenable.

### FILM_CEILING = 0.95

Maps linear 1.0 → 0.95 before EXPOSURE. At EXPOSURE = 1.1:
- Input 1.0 → 0.95 → pow(0.95, 1.1) ≈ 0.945
- Previously: pow(1.0, 1.1) = 1.0

This adds 5% highlight rolloff before EXPOSURE, which is plausible as "sensor clip headroom."
No conflict with the rest of the chain — values remain in [0, 1] throughout. Moderate and
well-behaved.

---

## Risks and Concerns

### 1. The "7.3% ARRI floor" figure is a code-value percentage, not linear light

The proposal's BLACK_FLOOR = 0.07 is 13–23× larger than the actual linear-light value at
the LogC3/S-Log3 black point. Using 0.07 without a blend would apply a visually extreme
grey pedestal inconsistent with the stated physical motivation.

### 2. Stacks with PRINT_STOCK — combined floor may exceed intent

At PRINT_STOCK ≥ 0.5 and FILM_FLOOR ≥ 0.03, the combined lift could make shadows
appear crushed to medium-grey. Recommend tuning both together, not independently.

### 3. Redundancy risk with PRINT_STOCK

Both stages serve the "lifted black" perceptual goal. A separate FILM_FLOOR knob increases
UI surface area for a marginal incremental benefit over adjusting the PRINT_STOCK constant.
The simpler option (increase PRINT_STOCK's 0.025 constant slightly) achieves the same effect
with no new code.

### 4. "Physical camera" framing does not hold for a game pipeline

The game outputs display-referred sRGB, not camera log. The "ARRI-style" motivation is
aesthetic, not correctional. This is worth documenting clearly in the shader comment to
avoid future confusion about why the remap is present.

---

## Verdict

**Proceed with caution — scaled-down values and a blend knob required.**

The physical motivation requires significant revision: the correct linear-light floor value
is 0.003–0.007 (not 0.07). As a hard remap without a blend, even 0.007 is visible; a blend
knob (similar to PRINT_STOCK) is recommended.

**Two implementation paths — choose one:**

**Path A (preferred, lower cost):** Absorb the floor intent into the existing PRINT_STOCK
constant: increase `0.025` → `0.030` in the R51 block (`grade.fx:246`). Zero new knobs,
zero new code. PRINT_STOCK's existing blend controls the strength.

**Path B (new stage):** Add a blended `FILM_FLOOR` knob:
```hlsl
// R54: camera signal floor/ceiling (aesthetic — not physical correction for game input)
float3 floored = col.rgb * (FILM_CEILING - FILM_FLOOR) + FILM_FLOOR;
col.rgb = lerp(col.rgb, floored, FILM_FLOOR_STRENGTH);
```
With FILM_FLOOR = 0.005, FILM_CEILING = 0.95, FILM_FLOOR_STRENGTH = 0.5 as defaults.
Insertion: line 224, after data-highway guard.

**Not recommended:** A hard unblended remap at FILM_FLOOR = 0.07. The grey pedestal would
be clearly visible and inconsistent with the current tuning at PRINT_STOCK = 0.20.
