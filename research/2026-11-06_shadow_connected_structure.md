# Connected level sets as a shading representation

The user requested continued shadow-brightness research. A new geometric
representation preserves the tested ramps, steps and long thin lines without
window averaging, but fails to establish useful shading ownership. Longer grain
and banding survive, useful fine material gaps shrink, and a one-pixel bridge
changes the representation at 64 otherwise unchanged pixels. Do not develop a
brightness correction or GPU port from this fixed model.

This is a CPU representation screen, not a rendered candidate or an adoption.
Brightness remains ~45/100; the isolated half-color helper remains ~70–75 and
unadopted. Production chain/grade 78 and tonal-model 80 retain their prior scope.

## Hypothesis and reference

Earlier windowed bases crossed thin bright features; RGB agreement passed
common-mode noise. Test whether connected geometry supplies different evidence:
retain sufficiently large connected bright/dark level sets regardless of width.
A long thin ridge can survive even where a median filter would remove it.

[Salembier and Wilkinson’s connected-operator review](https://upcommons.upc.edu/bitstream/handle/2117/8354/ConnectedOp%C3%A8rators.pdf)
describes filtering through flat-zone merging and component-tree attributes,
with boundary-preservation properties. Those properties do not identify shading,
establish noise rejection or guarantee safe enhancement. Our symmetric base
below is not a complete tree-of-shapes intrinsic decomposition or their proposed
enhancement system.

## One fixed geometric model

Convert preserved source linear Y to continuous sRGB code equivalents. Compute
an exact four-connected area opening with minimum area **64 pixels**, then its
dual area closing. Their average is the tested base. Area 64 is one exploratory
8×8-equivalent support criterion, not a calibrated significance/noise threshold;
there is no area/connectivity/strength sweep or intensity quantization.

The standalone union/find implementation sorts source pixels, builds upper
component ancestry, accumulates area and reconstructs surviving levels. It
matches independent brute-force threshold-component enumeration exactly on
integer and floating toy images across four area values. Those four values
check the implementation, rather than selecting the research model. The opening
passes tested idempotence, anti-extensivity and increasingness; the averaged
base passes duality and positive-affine equivariance. These properties are not
arbitrary pair-order preservation or output-image contracts.

Use the same 512² floating source observations for wall, metal and held timber,
with the existing interior target rectangles. Rectangles define evaluation only;
there is no region-owned correction or supplied material segmentation. A separate
256² captured GZW RGB-noise fixture checks nuisance response. All four array
identities match their frozen capture metadata. No historical generator is imported.

## What it preserves and loses

| Synthetic scalar code field | Base std / input std |
| --- | ---: |
| Ramp, straight step, 128-pixel-long one-pixel ridge | 1.000; exact input identity |
| Broad periodic shading, connected fine stripe texture | 1.000 |
| Independent white noise | .473 |
| Two-small-blur correlated grain | .689 |
| Longer grain, sixteen small blurs | .900 |
| Independent-column banding | 1.000; exact input identity |

The flat field is exact. An isolated 16-code positive dot loses half its amplitude
in the averaged base. Synthetic fields are 128×256 with one fixed seed; they are
not full-chain GPU outputs or calibrated real-game noise. The separate captured
RGB-noise fixture retains .4685 of source code-Y std and shifts mean by −.0018
code. These describe the **base**, not attenuation of existing output detail or
noise amplification in a brightness candidate.

For horizontal/vertical source pairs, require both source code-Y values in 8–100
and source absolute gap .25–8 codes. Measure the base’s source-signed code gap
divided by the source absolute gap on that same population:

| Target | 4 px | 16 px | 32 px | 64 px |
| --- | ---: | ---: | ---: | ---: |
| Wall | .676 | .754 | .791 | .860 |
| Metal | .799 | .906 | .940 | .979 |
| Held timber | .799 | .885 | .912 | .951 |

Thus the geometry retains broad variation better than fine variation, but it
also loses selected useful material structure. Pair reversals remain: 1,292 wall,
1,800 metal and 1,663 timber at four pixels. These are representation/source
comparisons, not new production defects. Populations differ from earlier Oklab/
log-gap selections; do not rank these ratios against those reports’ percentages.

Native scalar-Y previews show contour retention alongside flattening of fine
metal/timber structure. The base changes selected dark metal pixels by up to
38.56 codes and bright metal pixels by up to 98.27 codes. These are changes in
the estimated source base, not screenshot corrections or boundary halos. They
prevent treating geometric connectivity as trustworthy material/lighting ownership.
No new RGB candidate or visible output improvement is claimed.

## Connectivity and context stresses

Two disconnected 32-pixel bright ridges fall below the area criterion. Changing
one intervening source pixel from code 16 to 32 joins them into one 65-pixel
component. All **64 unchanged ridge pixels** change base by **8 codes**. This
tests a local topology change; it is not an infinitesimal input perturbation or
a measured motion/flicker result.

An independent context control leaves a central source crop exact while extending
its thin line outside that crop. The estimated base inside changes by 8 codes.
This exposes dependence on connected support, which a local approximation must
account for. It does not establish that all connected operators are unstable or
that smoothing the area criterion would have the same exact counterexample.

## Decision and range/runtime constraint

Reject this fixed area-opening/closing average as the missing shading producer.
It improves geometric behavior on some controls while retaining substantial
correlated nuisance variation and changing real material structure. Do not
increase the area, tune connectivity or turn these components into segmentation
just to obtain lower noise. Source residual reinsertion alone would not prove
that a later correction avoids the base’s topology/context errors.

A surviving representation would still need an explicit contrast budget: which
levels pay for extra separation, black/lighting protection and final boundary
behavior. No such correction is constructed from this rejected base. In
particular, source-base ratios do not restore broad shading merely because the
base preserves a ramp. A sorted union/find CPU algorithm also has no established
data path in the eight-pass HLSL chain. A bounded approximation would require
its own representation and visual evidence; this is not a request to port the solver.

Artifacts: `captures/shadow_connected_structure_20261106/` contains standalone
probe/audit, report, independent checks, source/base scalar previews, arrays,
connectivity counterexamples and manifest. All 17 production identities remain
unchanged. No new GPU, temporal, actual-config, performance, output-bounds or
black-preservation validation is claimed. No shader/profile/config/header,
history/resource/pass, adoption, commit or push changes follow.
