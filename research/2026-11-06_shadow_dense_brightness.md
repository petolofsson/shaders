# Combined brightness and subtle-color reference

The user requested starting brightness-gradient work and seeing whether both
shadow improvements can be combined. Four-way comparisons now cover current,
half-color, brightness-only and combined output on dense floating GPU inputs.
The selected combined material response improves, but noise, shade reversals
and synthetic rims reject this brightness version for shader implementation.
The isolated color option remains; no production shader, profile, config or
rating changes.

## What is different from the earlier Laplacian screen

The earlier [limited reference](2026-11-05_local_laplacian_limited.md) worked on
8-bit screenshots containing output dither. This experiment captures dense
pre-dither output and adds a source-support cap to each proposed detail increase.
It does not reuse the old one-code pixel threshold or iterative pair projection.
The distinct [source-common reconstruction](2026-11-06_shadow_source_component.md)
was rejected before this test.

Twelve new private, headless GPU processes capture post-inverse source RGB,
current pre-dither RGB and half-color pre-dither RGB in the same pass/update.
A frozen RGBA32F snapshot is acquired after at least 25,000 measured shader
milliseconds and 600 render updates. Binary pages encode nine normalized
24-bit values per pixel with step 1/(2^24−1). The page header identifies the
frozen render update/time separately from the current presentation. All selected
pages agree on snapshot identity; all twelve processes report zero dropped or
delayed frames. This is a finite still protocol, not convergence, game noise,
dense motion or GPU performance evidence.

`captures/shadow_dense_float_20261106/` contains 256×256 wall, metal and synthetic
code-16 ±1 RGB-noise patches, each with an independent repeat. The later
`captures/shadow_dense_material_20261106/` contains 512×512 wall, metal and an
independent held timber patch, also with repeats. Both wall and metal dense
arrays repeat exactly at encoded precision. Noise and held timber vary by at
most 3.58e-7 and 9.54e-7 linear RGB respectively; do not call those pairs exact.
The source/clip, isolated shader/config/profile and production identities are
recorded in the respective `report.json`. The later audit verifies 680 unique
files and all twelve page/state/counter records.

## Fixed reconstruction

CPU evaluation uses the existing four-level 5-tap Gaussian/Laplacian pyramid,
129-anchor local-Laplacian remapping (strength 0.5, sigma 0.5 stops) on log Y
with a 1e-5 floor. Forty-eight independent exact-anchor coefficient checks per
image bound interpolation error; the largest material error is about 0.00069
stops. Source coefficients use the same pyramid on actual post-inverse log Y.
For current coefficient c, proposed coefficient p and source coefficient s:

```text
extra = min(abs(p-c), max(abs(s)-abs(c), 0), 0.5*abs(c))
extra *= agreement(s*c > 0 and (p-c)*c > 0)
chosen = c + sign(c)*extra
```

The original coarsest current base is retained. Reconstructed log gain is bounded
to ±0.5 stops and multiplied by the color candidate's source-luminance window:
smoothstep(0.0005,0.005,Ysource) times
(1−smoothstep(0.08,0.15,Ysource)). A common RGB gain/headroom bound follows.
Each individual coefficient stays within max(abs(current),abs(source)); its
extra vanishes continuously as c approaches zero. These are coefficient bounds,
not final-output noise, gradient-order or halo guarantees.

## Larger native material comparison

The fixed material crops are wall (1500,250)–(1750,550), metal
(100,988)–(438,1288), timber (720,416)–(1040,672). Dense pair metrics select
source Oklab L 12–65, source log-Y gaps 0.02–0.5 stops, source ab distance below
2, both axes and offsets 1/4/16 pixels. They differ from prior sparse-patch and
material-mask populations; counts overlap and are not independent events.

| Larger crop | Current 4-px signed gap | Combined | Change | Mean L change | Current → combined reversed 4-px pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| Wall | 0.076027 | 0.083566 | +9.9% | +0.0134 | 47 → 54 |
| Metal | 0.134706 | 0.155201 | +15.2% | +0.0302 | 302 → 531 |
| Held timber | 0.147634 | 0.175049 | +18.6% | +0.0621 | 6 → 132 |

Brightness-only results are close to combined. The color-only material response
remains subtle. Native CPU previews suggest slightly more visible wall/timber
texture and dark-metal detail, rather than a major dimensional improvement.
They do not establish clear overall naked-eye superiority. A larger selected
gap is not itself an appearance score. At 16 pixels held timber reversals rise
16→930, with maximum reversed gap about 0.089 stops. All selected material RGB
gains stay within available headroom in this reference.

The earlier 64×64 center patches suggested larger wall/metal gap gains of about
19%/17% and almost no reversals. Preserve them as limited samples, not evidence
that clears the surrounding material. Dense coverage changes that conclusion.

## Noise and per-band attribution

In the code-16 fixture center, continuous sRGB-code-equivalent luminance standard
deviation is 0.61004 input, 0.47275 current, 0.47210 color-only, 0.65411 combined.
Thus the combined reference increases luminance variation about 38% over current
and 7% over input. This uses floating output before simulated screenshot
quantization; it is not noise inferred from an 8-bit PNG. The synthetic fixture
is not a calibrated model of real gameplay grain or texture. Color-only retains
the previously documented chromatic-noise cost independently.

`band_attribution.py` isolates each fixed coefficient band's contribution as a
diagnostic, without selecting a new strength. Removing the finest band reduces
the brightness-only noise standard deviation to 0.48695, still about 3% above
current. It reduces wall/metal/timber 4-px gap improvements to roughly 3%/5%/8%
and leaves 16-px timber reversals at 585 versus 16 current. It therefore does
not establish a viable coarse-only replacement.

Separate scalar CPU controls use the configured affine black mapping rather
than the complete grade. Exact black and a constant field remain unchanged.
A clean ramp remains ordered but barely changes. Small, large and softened
steps create local overshoot/undershoot and reversals; the small-step correction
reaches about 0.034 stops. Coefficient/source caps do not prevent reconstructed
rims. These finite controls are neither GPU nor whole-chain endpoint proofs.

## Decision and retained artifacts

Do not port this reference, its coarse-only ablation, or a Gaussian-moment
approximation into production on this evidence. No approximation was implemented.
Source support answers whether detail existed, but cannot identify whether it
is useful shading, noise or a boundary; independent coefficient caps also do
not constrain the reconstructed neighboring shades. Earlier rejected threshold
and order-projection variants already lost useful response. Another threshold,
strength sweep or extra motion campaign is not justified for this version.

Local [four-way review](../captures/shadow_dense_material_20261106/review.html)
contains native-size selectors. Preview encoding and spatial dither are CPU
approximations, not screenshots of a compiled brightness shader or a 10-bit
swapchain transfer. `reference.json`, `band_attribution.json`, `synthetic.json`
and `verification.json` hold the measurements and audit. Capture generators,
readback pages, arrays and logs remain ignored local artifacts. No full-frame
brightness GPU candidate, temporal/zero-bypass/actual-config validation or
performance claim follows. Production grade remains SHA-256
`efea23e8c8e061a77619c8c42f89f1d73c35523623ea90a1f3ee4028e8f40c56`.
The two-part goal stays open, with brightness design still the limiting part.
