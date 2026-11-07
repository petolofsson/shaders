# RGB-consistent shading representation: finite falsification

Resuming from the consolidated checkpoint, test a different source of evidence:
whether equal fractional changes across RGB can identify shading independently
of scalar luminance structure. This is a representation test, not another
curve/filter/gain sweep, a rendered candidate or automatic segmentation.

The proposed cue fails as a standalone selector. It preserves much of the
selected material's missing contrast, but also assigns full shading support to
common-mode brightness noise and scalar reflectance variation. No production
change, new GPU campaign or score increase is justified. Brightness remains
approximately 45 and the isolated, unadopted color helper approximately 70–75.

## Reason for the test

Native preserved metal and timber comparisons retain the relevant challenge:
dark shading shares pixels with useful texture, colored materials and thin
bright structures. Previous scalar models did not establish a reliable
distinction between useful shading and correlated noise. Rather than modifying
their confidence thresholds, test information those models did not explicitly
use: the direction of each gradient in three-channel log RGB.

[Tappen, Freeman and Adelson](https://people.csail.mit.edu/mtappen/nips02_final.pdf)
model intrinsic decomposition through shading/reflectance derivative
classification and propagate ambiguous local evidence. Their method is not
implemented here. [Janner et al.](https://rin.csail.mit.edu/) describe the
ambiguity of single-image intrinsic decomposition and use learned shape,
reflectance and lighting representations. Neither establishes that a local
RGB cue is sufficient for SDR game output. The test below is our own deliberately
limited inference from a multiplicative shading model, not either paper's method.

## Fixed representation and data

For a source-pixel pair, let d be its three-channel log2 RGB difference and
m its channel mean. Define shading support as

```text
q = m² / mean(d²)
```

This is the energy fraction projected onto the common log-RGB direction;
q lies between zero and one for nonzero differences. Uniform multiplicative
RGB change has q=1. No classifier threshold, learned parameter, spatial filter,
correction strength or gain search is introduced.

Use preserved same-update floating source/current/half-color observations for
wall, metal and held timber. Reuse the earlier supplied target rectangles,
without calling them material boundaries. Evaluate horizontal and vertical
pairs at 4/16/32 native pixels. Require both source code-equivalent Y values
between 8 and 100 and source absolute log-Y difference between .02 and .5 stops.
These eligibility rules do not establish material or noise membership.

For each pair, measure the positive part of source absolute code-Y gap minus
the color-output source-signed gap. Report how much of that missing-gap sum
survives multiplication by q. This is an evidence-weighting diagnostic, **not
recovered output contrast**. It does not reconstruct an integrable image or
assign the range/black budget needed by a brightness implementation.

## Results

| Population | Mean q, 4 px | Missing code-gap sum retained, 4 px |
| --- | ---: | ---: |
| Wall | .855 | 91.65% |
| Metal | .766 | 83.56% |
| Held timber | .773 | 87.45% |
| Captured independent RGB-noise fixture | .355 | 39.70% |

At 32 pixels, the retained fractions are wall 93.02%, metal 74.96%, timber
87.74% and captured noise 39.76%. Those are overlapping selected pairs, not
independent observations, fidelity, improvement or noise-amplification results.
The actual fixture is one preserved GZW input, not independent game/material
noise coverage. Its stored repeat variation remains in the original reference.

Independent synthetic log-RGB noise gives mean q=.353 and retains 40.68% of
the affine stage's missing code gap. Multiplicative common-mode white noise,
two-small-binomial-blur grain and smooth periodic shading all give q=1 and
retain 100%. Synthetic fields use a fixed colored linear base, .12-stop
variation, the configured affine `.9925*RGB+.0025`, and one seeded realization.
They are not GPU grading or calibrated real-game noise spectra.

An exact ambiguity control gives identical input RGB for varying scalar
reflectance under constant light and constant reflectance under varying scalar
light. A brightness disturbance can produce that same observation. Chromaticity
alone therefore cannot select among those explanations. This does not rule out
methods using additional priors, geometry, semantics or temporal evidence.

## Decision, runtime implications and verification

Do not use RGB consistency as the missing shading-confidence producer. It can
reject some chromatic disturbances while passing all of the tested common-mode
grain. Raising a confidence threshold cannot distinguish q=1 shading from q=1
noise. Requiring weak chromaticity change could also exclude legitimate colored
lighting and material distinctions. This cue does not justify an intrinsic-image
solver, learned model or segmentation implementation.

A bounded neighborhood RGB comparison is conceivable in a shader, but no
supported shading representation or complete range allocation survives here.
Consequently no output correction is generated and there is no claimed native
benefit, black/boundary contract, thin-feature protection, temporal result or
runtime-cost evidence. Do not combine this result with earlier rejected models
and silently infer those missing properties. A new representation still needs
an independent reason to preserve useful structure while controlling nuisance
variation, followed by an explicit range budget and native visual evidence.

Artifacts: `captures/shadow_rgb_shading_20261106/`, with standalone `probe.py`,
`report.json`, approximate native float previews, independent numerical audit
and manifest. All three material values hashes and the noise values hash match
their frozen metadata. All 17 current production/include/profile/config hashes
match before and after. The audit checks projection identities/bounds, synthetic
common-mode results and retained input identities. No historical generator is
imported or rerun. Previews are CPU encodings without added dither, not new
screenshots. No shader, profile, config, header, history, resource or pass changes,
adoption, commit or push follows.
