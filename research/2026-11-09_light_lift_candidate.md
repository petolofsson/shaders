# Light lift candidate: from colour edges to material veto (2026-11-09)

Continues the [colour-edge report](2026-11-09_colour_edge_light_material.md). The
user asked to try the stronger light-selective lift as a shader, then to keep
improving shadow/mid/light separation rather than park it. Production is
unchanged. The candidate lives in the ignored `captures/light_lift_20261109/`.
It contains the pipeline copy in `general/`, v2 in `general_v2_colouredge/`,
copied profiles `prof_*`, configs `*_A|B|debug|debug2.conf`, `run.sh`,
`make_review.py` and `build_artifact.py`, plus stills and reviews per round
(`stills_v1`, `_v2`, `_v3a`, current `stills`). Every capture was private and
headless, with 0 compile errors. Shader, profile and config hashes matched
before and after every run. Debug views are candidate-only defines.

## Result

**v3 "material veto"** is the current candidate.
- **Light estimate.** Light = log luminance (every step is light, as production
  assumes) plus a local correction that removes only confident paint steps.
- **Lift.** A light-selective lift follows three frame-relative zones with
  smooth ramps.
- **User verdict.** The user judged its shadow/mid/light zones "perfectly
  balanced".
- **Open.** Lift strength and whether it replaces or adds to production's lift.

## Shader structure (v3)

`general/grade/light_lift.fxh`, included by `grade.fx`. It runs 11 passes at the
1/8 spatial lane before `GradeColorTransform`:

1. **`LLDirections`** (1×1, MRT). One sparse 16×16 reduction gives the frame
   shade direction and two dark-pixel halves split across the sky axis. The sky
   (Planckian) direction is a constant.
2. **`LLDivergence`.**
   - A step to a neighbour is *paint* when its log-chromaticity change exceeds
     .35 and its component across every shade direction exceeds .35.
   - The pass outputs the divergence of the negated paint steps only.
3. **Convolution pyramid**, 4 levels: `LLDown1..4`, `LLUp3..0`.
   - Kernels as in Farbman et al. 2011: h1 [.15 .5 .7 .5 .15], g [.175 .547 .175].
   - Zero borders, output scale −1.0.
   - Four levels limit the correction's reach to about 16 lane pixels.
4. **`LLAnchor`** (1×1). Removes the correction's mean and computes the frame's
   lit level (mean + 1.28 sd of the light, ~p90).
5. **`ColorTransform`:**
   - **Upsampling.** Joint bilateral upsampling (4×4 lane taps, σs 1, σl .35)
     of lane log luminance plus correction. The guide is native log luminance
     only, because the BackBuffer is post-inverse-grade there and its chroma
     does not match the lane.
   - **Lift.** Applied to linear colour after the BLACKS/WHITES mapping, with a
     hue-preserving SDR ceiling. It uses d = stops below the lit level:
     `0.6 · SHADOW_LIGHT_LIFT · (0.3·ss(.75, 2, d) + 0.7·ss(1.75, 2.75, d)) · (1 − ss(5.5, 7.5, d)) · ss(log2 .001, log2 .004, light)`.

Debug views:
- `LL_DEBUG_VIEW 1` writes log2 light over 1e-4..1 as codes.
- `LL_DEBUG_VIEW 2` shows the paint correction, orange/blue, full at 1 stop.

## Round history

| Round | Light estimate | Lift | Outcome |
| --- | --- | --- | --- |
| v1 | col4 colour edges: keep a step only if a light colour explains it; 7-level pyramid | absolute band .004–.3, +0.6 stop | A brightened whole frames by about the same as shadows (+.03–.43 all, +.01–.52 dark): the band hit midtones |
| v2 | same | relative to lit level, +0.6 | still broad (+.16–.37 all). The user's 0–100 light map exposed three failures (below) |
| v3a | material veto, 4-level pyramid | relative, +0.6 | user's three failures fixed; zones accepted; A still +.08–.39 all |
| v3b | same | zone-following, `SHADOW_LIGHT_LIFT` .5 | lit areas untouched (table below) |

The three v2 failures the user found:
1. **Shelf interior (GZW 133058) read as lit.** Warm bounce makes the shade
   yellower, not bluer, so the edge was classed as paint.
2. **Left trees (GZW 133750) read as lit.** Integration filled them from the
   grass across rejected edges; only the isolated right tree went dark.
3. **Dim Arc room (210448) read as flat mid grey.**

Cause of all three: col4 defaults to "material" for any step the colour cannot
prove is light.

## Screens (CPU, 7 synthetic oracle scenes)

Region-balanced error of the stronger lift curve against true light; lower is
better. Tools: `tools/flatfield_screen.py`, `material_veto_screen.py`,
`material_local_screen.py`.

| Estimate | Mean | Notes |
| --- | ---: | --- |
| production tonal base | .209–.211 | |
| luminance only, same 1/8 + JBU path (control) | .208 | the path alone gives nothing |
| col4 colour edges + JBU | .157 | fails on game frames (above) |
| flat-field, round / stretched bins | .267 / .238 | worse; game maps also wrong |
| **material veto t .35, global** | **.149** | best synthetic; spreads 13% of the Arc frame |
| hue-angle paint rule, any reach | .19–.23 | weaker rule |
| veto with ±1-stop cap | .204–.210 | the cap removes the gain |
| veto, screened Poisson reach 16, no cap | .152 | local |
| **veto, 4-level pyramid, scale −1.0** | **.150** | the GPU form |

- **Flat-fielding (astronomy/MRI) fails.** Each material needs both lit and
  shaded instances, but in game frames a material usually sits under one light.
- **Contained version.** The 4-level pyramid matches the exact short-reach solve
  on the synthetic scenes and keeps paint corrections local on game frames.
  Corrections larger than .5 stop cover 0–3.8% of a frame (GPU readback on Arc
  210448: 5.2%).
- **Proper multigrid** reached 2% error but needed 36–56 passes. Cascadic
  multigrid did not converge.

Across all 40 reference stills, paint edges are .4–3.7% of steps. The colourful
Arc menu (205938, .8%) is mid-range, so a frame-level "UI" gate is not
supported and was not built.

## v3b matched captures

A = new lift only (`SHADOW_LIFT_STRENGTH` 0); B = both lifts; `SHADOW_LIGHT_LIFT`
.5. Stops vs production; "dark" = production luminance < .05; the red marker is
masked.

| Still | A all | A dark | B dark | A repeat (codes) |
| --- | ---: | ---: | ---: | ---: |
| GZW 133058 | −.14 | −.11 | +.14 | 1 |
| GZW 101035 | +.10 | +.23 | +.33 | 6 |
| GZW 133750 | −.03 | .00 | +.24 | 1 |
| GZW 133932 | +.16 | +.26 | +.28 | 4 |
| Arc 205938 | +.03 | +.08 | +.26 | 3 |
| Arc 210448 | −.06 | −.04 | +.23 | 1 |

- **A is darker than production in three shadows**, because it removes the old
  lift and gives less at .5.
- **Recommendation pending the user's look:** A at `SHADOW_LIGHT_LIFT` about 1.0,
  a single zone-driven lift.
- **Repeat noise.** 133932 was 20 codes in v3a and 4 in v3b, so treat that
  still's numbers loosely.

## Ruled out this session

- **Camera motion/temporal.** I recommended it, then retracted before building.
  Shadows and paint are both fixed to the world, so camera motion gives no
  separating information. Only moving occluders or lights would, which is
  situational.
- **Learned detector distillation.** Offline BDRAR (2026-11-07) marks the same
  dark materials as shadow.
- **Edge-shape matched filter.** Penumbra width is not resolvable at 1/8.
- **Pure single-frame separation.** It has a hard limit: a darker version of a
  material produces the same pixels as its shade
  ([surface relations](2026-11-07_shadow_surface_relation_screen.md)). v3 accepts
  that limit by defaulting to production's assumption, and uses colour only
  where it is unambiguous.

## Review conventions adopted

- **Light maps per frame "0–100".** The user's idea: black = p1, white = p99 of
  log light, even in stops. Fixed and lit-relative scales looked misleadingly
  pale.
- **Zone overlays.** Shadow > 2 stops below the lit level, mid .75–2, light
  within .75. A soft version blends exactly as the lift ramps do.
- **Review page.** Private artifact "Light Lift Review", version 5.
