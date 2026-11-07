# Region-owned shading and a joint noise budget

The user requested continuing brightness-gradient work. This screen tests
spatial ownership of the brightness range and a new tradeoff: strengthen shading
while slightly attenuating the finest existing variation. Earlier increment-only
references kept existing detail untouched. The new reference explicitly pays for
some added shading by reducing fine detail. It is CPU research, not an adopted
denoising effect or a change to the eight-pass production pipeline.

There is no implementation proposal from this finite screen. The region
reference produces selected gains at unchanged average code brightness, but
the quiet versions lose fine metal/material separation and longer-range grain
still amplifies. Native comparisons do not establish the clear overall benefit
needed for adoption. The brightness estimate remains ~45, subtle color 70–75;
existing chain/grade and tonal-model ratings retain their original scopes.

## Research and scope

[Lischinski et al.](https://www.microsoft.com/en-us/research/publication/interactive-local-adjustment-of-tonal-values/)
propagate local tonal constraints using edge-aware optimization.
[Shan, Jia and Brown](https://grail.cs.washington.edu/projects/sq_tonemapping/)
combine overlapping local linear adjustments through global optimization.
These references motivate spatially varying adjustments with compatibility
constraints. Neither supplies automatic material boundaries or validates the
noise budget below; their full optimization systems are not implemented here.

Use supplied material rectangles as an **ownership diagnostic**, not automatic
or verified semantic segmentation. Rectangles can contain several surfaces,
thin bright structures and lighting transitions. This is not an upper bound on
what ideal segmentation could achieve. Feather ownership inside each rectangle,
leave its exterior unchanged and preserve its mean encoded luminance. An
automatic segmentation algorithm is not built merely to operationalize a weak
reference.

## Region-owned contrast reference

Use preserved same-update floating source/current/half-color observations for
wall, metal and held timber. The shelf uses the previously recorded separate
8-bit grade-input/current half-color screenshots. Source/profile/producer and
input hashes are checked; these scopes must not be conflated.

Estimate source/current brightness bases with 9×9 medians. Within each supplied
region, fit the slope from current to source base differences at 4/16/32 pixels,
using the previous source-lightness/log-gap/color-difference exclusions. Half
the slope above one is retained, capped at an extra slope of 0.25. No gain or
pivot search is performed. Apply either pointwise or through the median base.
The pivot is the source-gate/ownership-weighted mean of that signal, so positive
and negative corrections balance inside the region. Common RGB gain is bounded
by SDR headroom.

| Region | Point: absolute 4-pixel code-gap gain | Median-base gain |
| --- | ---: | ---: |
| Wall | +2.19% | +0.33% |
| Metal | +3.12% | −0.78% |
| Held timber | +5.74% | +1.01% |
| Shelf, PNG scope | +5.36% | +0.72% |

Actual mean code-luminance changes are below 2e-15 in these references. This is
not unchanged RGB means, Oklab L or perceived density. Outside ownership, output
is exact. Tested black-source samples remain exact. The median-base metal
reference also transfers a correction as large as 15.5 codes around thin/bright
features: a median is not a valid material boundary model. It is rejected.

Point evaluation retains more separation but amplifies the captured noise
fixture by about 2.7–12.6%, depending on the region-derived gain. Native shelf
and timber differences remain subtle; no blind/user/gameplay acceptance is
claimed. Supplied region membership alone does not establish useful recovery.

## New mechanism: jointly allocate shading and fine-detail variance

Let c be current continuous luminance in sRGB code equivalents, k the region's
gated extra contrast and G a normalized smoothing kernel. Add

```text
delta = k*(c−pivot) − q*(c−G(c))
```

Choose the pivot so the complete correction has zero mean inside ownership.
The second term now attenuates existing finest variation, rather than only
restraining a proposed enhancement increment. The spectrum receives gain 1+k
at zero frequency, with a smaller response at higher frequencies.

For fixed k and stationary white noise, use the separable 3×3 binomial kernel.
Its center is 1/4 and squared impulse norm 9/64. The smaller nonnegative root of

```text
(1+k)^2 − 2*(1+k)*q*(3/4) + q^2*(41/64) = 1
```

keeps output noise variance equal to input variance in this model. This is our
analytic reference, not a fitted game-noise estimator. Source-dependent gates,
ownership changes and arbitrary noise spectra are outside that scalar contract.

The actual captured RGB noise field stays approximately unchanged, −0.03% to
−0.13% std across region gains. Shelf-gain synthetic clean/noisy ramp std gains
are about 11.98%/11.78%; tested monotone steps have no reversing rows, and mixed
source-black remains exact. But short correlated grain grows about 9.1% and
column banding 3.9%. Thus white-noise balance alone is inadequate.

## Fixed three-spectrum constraint

A second analytic design constrains white noise, two-small-binomial-blur grain
and independent-column banding together. Use a wider binomial kernel formed by
eight applications of the small kernel. For each stated noise kernel N, compute

```text
A = ||N−G(N)||² / ||N||²
B = <N, N−G(N)> / ||N||²
```

Solve the corresponding variance-budget quadratic and take the largest required
q. The tested gain interval 0–0.25 satisfies all three variance inequalities and
has nonnegative effective filter coefficients. This preserves DC gain while
trading away more fine-scale contrast. It is a fixed spectral envelope, not a
parameter sweep or proof for arbitrary game noise.

| Dense region | White-only budget: 4 px / 64 px gap change | Three-spectrum budget: 4 px / 64 px |
| --- | ---: | ---: |
| Wall | +1.06% / +1.90% | −0.37% / +1.25% |
| Metal | +0.42% / +0.30% | −2.18% / −0.55% |
| Held timber | +3.76% / +5.91% | −0.14% / +4.95% |

These are absolute source-signed code gaps on overlapping selected pairs,
not independent measurements or visual-effectiveness percentages. The wider
budget reduces captured white-like noise std about 1.3–6.2% but visibly useful
fine separation is not preserved consistently.

An explicit matched-spectrum check gives white std −6.19%, calibrated short
grain approximately unchanged (−0.002%), and banding −3.41% through the gated
affine reference at the shelf-derived gain. Longer-range grain still rises
**8.74%**. The spectral runner's main grain fixture uses two **wide** blurs
because it replaces the kernel function; it is this longer-range holdout,
not a failed matched short-grain contract. Both fixtures and the distinction are
preserved in `verification.json`. A period-128 sinusoid receives +12.58%: low
frequency grain and wanted shading can share the enhanced frequency range.

Noise-context results use the same preserved GZW noise field under different
region gains; they are not new noise captures for every material/game. Static
CPU fields cannot establish movement or temporal appearance.

## Decision and retained evidence

Do not implement these references or infer that automatic segmentation is the
only remaining step. Region ownership and a mean constraint improve the budget's
interpretability but do not establish clear cross-material appearance. Joint
fine-detail attenuation can pay for stronger broad shading under specified
spectra, yet its texture and correlated-grain tradeoffs remain unacceptable for
adoption on this evidence. Increasing the gain, widening the filter again or
silently removing texture is not a justified next step.

The analytic budget is useful as a finite benchmark: any future shading model
should retain useful structure beyond the spectrum it treats as unwanted
variation. These tests do not rule out a better material/shading representation,
and they do not demonstrate one. No automatic boundary producer, practical
runtime architecture or adoption-ready brightness candidate exists here.

Artifacts: `captures/shadow_region_budget_20261106/`, with region references,
separate `joint/` and `spectral/` results, native comparisons,
[review](../captures/shadow_region_budget_20261106/review.html), matched/holdout
controls, impulse/mean/black/bounds checks, input identities and manifest.
No new GPU process ran. Production shaders/profiles/configs/headers, histories,
resources, eight passes and ratings remain unchanged. No active runtime,
adoption question, commit or push is pending.
