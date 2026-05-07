# R120 — Genesis Film Emulation & Bogdanowicz: Findings

## Source

Session research into Dr. Mitch Bogdanowicz (2× Oscar, 32 years Kodak), the Genesis
film emulation plugin (Cullen Kelly / Bogdanowicz / Steve Yedlin ASC), the Kodak Look
Management System, and the Joker (2019) LUT.

---

## Key findings

### Genesis plugin architecture

Genesis (OFX, DaVinci Resolve) models film as an **integrated system** — grain, halation,
color separation, and density response all interact rather than being applied independently.
42 negative stocks + 13 print stocks built from original Kodak/Fuji design specs.

Core modeled phenomena:
- Nonlinear sensor response (toe / straight-line / shoulder)
- Exposure-dependent grain (Yedlin probabilistic model — extracts probability distribution
  from real scanned film, does not store scanned images)
- Dye layer density modeling (layered emulsion structure)
- Interlayer saturation (separate from DIR inhibition)
- Halation (Yedlin empirical model — see below)
- Printer points, push/pull, bleach bypass (negative and print independently)

### Halation physics (Yedlin / Bogdanowicz)

Halation is a negative stock property — light bounces off the film base and re-exposes
the emulsion from behind. Layer order determines color:

- **Innermost ring**: red layer hit first by reflected light → red-dominant
- **Middle zone**: reflection strong enough to penetrate green layer → red + green → orange/amber
- **Outer tail**: all layers contribute → near-white diffusion

Anti-halation backing reduces but cannot eliminate the effect.

**Implication for our pipeline**: our HAL_GAMMA crossover (inner/outer ring split) is
physically motivated and architecturally correct. The color character matches.

**Order bug**: halation is a negative stock phenomenon — it occurs before printing.
In our pipeline it fires at the end of CHROMA, after PRINT_STOCK compression. Print stock
is attenuating the halation glow, which is backwards. The glow should feed into the print
emulsion, not emerge from it.

### Joker LUT (2019)

- Target: Kodak EXR 200T 5293 (out of production, tungsten-balanced, microfine grain)
- Built by Jill Bogdanowicz (colorist, Company 3) + Mitch Bogdanowicz pre-production
- Creative intent: late 1970s/early 1980s — subdued palette, cyan in shadows, held-back saturation
- Same LUT used on-set, through VFX, and final DI for consistency
- 5293 LiveGrain added on top

### Bogdanowicz patent: US20060007460A1

"Method of Digital Processing for Digital Cinema Projection of Tone Scale and Color" (2005)

Key concept: **Analytical Dye Amount space** — channel-independent (orthogonal) color space
derived from spectrophotometric measurements of cyan/magenta/yellow print film dyes.
Prevents cross-channel errors during CMY→RGB projection conversion.
Out-of-gamut remapping preserves hue angles (most perceptually important attribute),
adjusts lightness and saturation to fit displayable range.

Our approach: Oklab gives perceptual orthogonality; HueCeil() preserves hue angles during
gamut compression. Architecture matches the patent's intent without requiring raw dye data.

### Kharma LUTs (Bogdanowicz / Ravengrade)

9 LUTs built from true spectral and colorimetry data: Vision3 5203, Kodachrome 5268,
Fuji Eterna, Ektachrome 7294, Fuji Eterna SR12, Vision3 2383, EXR Color Print 2386,
Fuji 3510. Includes Cineon transforms, film gamut compression, print matrices.

### Yedlin on grain methodology

> "It's knowing what to DO with the information, not merely having the information."

Grain stored as a probability distribution model, not scanned frames. Exposure-dependent:
overexposed areas → finer/less visible grain; underexposed → coarser/more grain.
This is the correct physical model — grain clumps at the development boundary.

---

## What does NOT apply to our pipeline

- **42-stock library**: we have one tunable curve character — correct for a real-time pipeline
- **Grain**: GPU cost prohibitive for real-time vkBasalt; not in scope
- **Analytical Dye Amount space**: requires actual spectrophotometric dye data we don't have;
  our 2383 approximation is sufficient without the raw measurements
- **Interlayer saturation as separate control**: our DIR couplers already model cross-channel
  inhibition; the positive interlayer contribution is subtle and overlaps significantly

---

## Proposals

### P1 — Fix halation stage order (zero cost, physically correct)

**What**: Move halation to fire before PRINT_STOCK in the ColorTransformPS stage order.
Currently halation fires at end of CHROMA, after print stock compression — backwards.

**What we gain**: Halation glow feeds into the print emulsion as it does physically.
Print stock then compresses and warm-tints the glow, which is the correct photochemical
chain. Visually: halation will appear stronger at the same HAL_STRENGTH (print compression
is no longer attenuating it), and it will interact with print stock warmth more naturally.
Likely needs HAL_STRENGTH recalibration downward after the move.

**Cost**: Reorder two blocks in ColorTransformPS. No new knobs.

---

### P2 — Bleach bypass (high creative value)

**What**: Simulate skipping the bleach step in negative development. Retains silver
alongside dye — desaturates, boosts contrast, adds metallic shadow quality.
New knob: `BLEACH_BYPASS` in creative_values (0 = off, 1 = full).

**What we gain**: A major cinematic aesthetic tool absent from our pipeline.
Saves Private Ryan, Se7en, Traffic, 28 Days Later all used real bleach bypass.
In practice for games: cuts through colour noise, adds grit and weight to dark scenes
without crushing blacks. Works synergistically with PRINT_STOCK — both affect density
but in different directions.

**Implementation**: In log space inside the FilmCurve stage — attenuate chroma by
strength, steepen luma curve proportionally. Fires before PRINT_STOCK, same as physical order.

**Cost**: ~10 lines in grade.fx, one knob in creative_values.

---

### P3 — Push/pull development (moderate creative value)

**What**: Simulate extended (push) or shortened (pull) development time.
Push: raises straight-line slope, compresses toe, slight mid saturation boost.
Pull: flattens slope, opens shadows, reduces saturation slightly.
New knob: `PUSH_PULL` in creative_values (stops, e.g. ±2).

**What we gain**: Deliberate development character independent of scene key.
Push gives aggressive contrast and crushed shadows — useful for high-contrast action.
Pull gives flat, overexposed Scandinavian-film quality. Neither is achievable with
ZONE_STRENGTH or EXPOSURE alone because this operates on the FilmCurve slope directly.
Genesis models this per negative stock; we'd have one global control.

**Implementation**: Offset the FilmCurve knee position by PUSH_PULL stops before
fc_stevens adaptive blend. Interacts with existing scene-adaptive slope — needs care
to avoid fighting the adaptation.

**Cost**: ~15 lines in grade.fx, one knob in creative_values. More complex than P1/P2
because it interacts with the adaptive FilmCurve.

---

## Priority order

1. **P1** — halation stage order. Zero cost, physically correct, do it.
2. **P2** — bleach bypass. High value add, clean implementation path.
3. **P3** — push/pull. Useful but interacts with existing adaptive machinery — do after P2.
