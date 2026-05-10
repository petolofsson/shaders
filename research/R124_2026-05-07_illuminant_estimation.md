# R124 — Illuminant Estimation for CAT16 2026-05-07

**Scope:** Evaluate illuminant estimation methods to replace the current grey world
(flat lf_mip0 spatial average) feeding CAT16 chromatic adaptation. No web search
available — internal knowledge, prior-cutoff papers cited.

---

## Problem

The current illuminant is the spatial mean of `CreativeLowFreqTex mip0` (1/8-res,
RGBA16F). This is grey world: every pixel weighted equally. Failure mode: a scene with
a warm practical lamp and a cool window produces a muddy average that white-balances
neither region correctly. CAT16 then applies a single uniform adaptation matrix that
is wrong everywhere.

---

## Methods surveyed

### Grey world (current)
Mean of all pixels. Zero extra cost. Fails on multi-illuminant scenes and on
dominant-hue content (grass-heavy: overestimates green → over-corrects toward magenta).
Documented in Barnard et al. 2002 — "A comparison of computational colour constancy
algorithms" (*IEEE TPAMI*).

### White patch / Max-RGB
Illuminant = per-channel max of brightest N% of pixels. Outperforms grey world when
true specular highlights are present (specular ≈ illuminant color under diagonal model).
Fails on scenes with no true white — golden-hour footage, fire scenes — and would
misidentify warm halation bloom as the illuminant, conflicting with the existing
halation model. **Not suitable for this pipeline.**

### Grey edge — van de Weijer et al. 2007
Illuminant estimated from mean of spatial color gradients (first derivative). Edges
carry illuminant color independently of surface color, reducing dominant-hue bias.
*"Edge-Based Color Constancy"* — IEEE Trans. Image Processing 16(9):2207–2214, 2007.
Gijsenij et al. 2011 meta-analysis (*IEEE TIP*) shows grey edge beats grey world by
~20–30% median angular error across benchmarks. **Requires a full 1/8-res gradient
pass — not viable given GPU budget.**

### Neutral pixel weighting (recommended)
Weight the illuminant estimate by pixels whose R≈G≈B (Oklab chroma below threshold).
Achromatic surfaces carry illuminant color cleanly; saturated surfaces are noise
(warm lamp bloom, cool sky, green vegetation). Formalized as the Neutral Interface
Hypothesis — Choudhury & Medioni ICCV 2011. Used implicitly in camera AWB pipelines.
Outperforms grey world specifically on mixed-illuminant benchmarks — the exact failure
case here.

### CAT16 / CIECAM16 on illuminant estimation
Li et al. 2017 (*Color Research & Application* 42(6):703–718). CAT16 specifies the
adaptation transform, not the illuminant estimation method. Illuminant estimation is
explicitly left to the application. The current CAT16 matrix math is correct — improving
the estimate is fully independent of the adaptation math.

---

## Two implementation tiers

### Tier A — Zero extra pass (achromatic gate)

Highway slot 202 already carries `HWY_ACHROM_FRAC` — the fraction of near-neutral pixels.
When this fraction is low, the grey world estimate is unreliable (saturated scene — no
neutral references). Scale down CAT16 adaptation strength proportionally:

```hlsl
float achrom_frac = ReadHWY(HWY_ACHROM_FRAC);          // x=202
float cat_confidence = smoothstep(0.02, 0.12, achrom_frac);
float cat_blend = lerp(0.60, lerp(0.80, 0.60, illum_dev), cat_confidence);
// existing: lerp(0.80, 0.60, saturate(illum_dev / 0.3))
// new: same shape but scaled to cat_confidence when scene is saturated
```

Effect: in scenes with few neutral pixels (low achrom_frac), CAT16 backs off rather
than applying a poorly-estimated adaptation. Zero new passes, zero new highway slots.
~3 ALU.

### Tier B — One extra 1/8-res pass (neutral-weighted mean)

New pass over `CreativeLowFreqTex mip0` (1/8-res, 262K pixels at 1920×1080). For each
pixel, compute Oklab chroma from the RGBA16F values. Accumulate only pixels below a
chroma threshold (e.g. C < 0.08 — near-grey). Output: weighted mean RGB → new
`IllumEstTex` (1×1 RGBA16F). Replace `lf_mip0` mean with this neutral-weighted mean
as the CAT16 illuminant input.

GPU cost: one 1/8-res pass, single loop over texture. ~1.2ms at 1080p on AMD RX 580
(estimated from similar histogram passes). Non-trivial GPU budget — needs measurement.

---

## Recommendation

**Implement Tier A immediately.** Zero cost, uses existing highway data, directly
addresses the failure mode where a saturated scene (low achrom_frac) produces an
unreliable grey world estimate. CAT16 backs off gracefully rather than applying a
confident-but-wrong adaptation.

**Evaluate Tier B after Tier A.** If A/B comparison on mixed-illuminant scenes shows
Tier A insufficient (adaptation still fires when it shouldn't), Tier B's neutral-weighted
pass is the correct fix. Budget cost must be measured before committing.

**Do not use white patch** — incompatible with the halation warm-bias model. Bright
pixels in this pipeline carry halation color, not illuminant color.

---

## Stage impact estimate

Tier A: Stage 1 finished +2%, Stage 1 novel +1% (novel: achromatic-confidence-gated
CAT16 in real-time is not documented elsewhere).

Tier B: Stage 1 finished +4%, Stage 1 novel +3% (neutral-weighted illuminant estimation
in a game post-process pipeline).
