# Filter-kernel spacing at truncated resolutions — 2026-10-27

Continues PLAN 4 after the completed material/highlight assessment. This checks
the low-frequency downscales and guided-filter tap spacing, separately from the
already completed metadata addressing audit. Dense motion, cuts, variable timing
and physical high-refresh behavior remain open.

## Contract and isolated candidate

The low-frequency and guided textures allocate integer dimensions:
`BUFFER_WIDTH / 8`, `/16`, `/32` and the corresponding heights. A source-texture
texel step is the reciprocal of that allocated dimension. The previous steps
instead divided the nominal scale by the full framebuffer size. At widths or
heights with a remainder, those taps land short of their intended neighbors.

For example, at 1919×1079 the guided textures are 239×134. The old vertical step
lands 1072/1079 = 0.993513 source texels away; the radius-three tap is about
0.01946 texels short. At 1920×1080, the guided dimensions divide exactly but
the first low-frequency texture is 120×67, so its second-downscale vertical
half-texel step is still short. Divisibility by eight does not establish every
downscale's spacing contract.

The isolated candidate changes five expressions in `general/grade/grade.fx`:

- First downscale: horizontal half-texel offset uses `0.5 / (BUFFER_WIDTH / 8)`.
- Second downscale: half-texel offsets use `0.5 / float2(BUFFER_WIDTH / 16,
  BUFFER_HEIGHT / 16)`.
- Guided coefficients: horizontal whole-texel step uses `1 / (BUFFER_WIDTH / 8)`.
- Guided averaging: both whole-texel steps use the allocated eighth-resolution
  width and height.

The spatial-lane vertical offsets already use the allocated highway height and
remain correct. Source observation's physical-pixel taps, texture sizes, filter
radius, formulas, formats, histories/rates, pass count, profile values and
processing order remain unchanged. A radius fixed in source texels is not a
promise of equal relative-screen support at every output resolution.

## Explicit GPU function readback

Nine fresh private headless processes cover before/candidate at 1366×769,
1919×1079, 1920×1080 and 2560×1440, plus an unchanged 1366×769 candidate repeat.
Each runs five seconds of compilation wait and twenty seconds of continuous
playback. All report zero dropped/delayed frames. Binary readback verifies the
actual compiled framebuffer dimensions in every capture.

The diagnostic writes deterministic, exactly half-representable spatial, mip
and coefficient fields. It calls the four actual production pixel functions at
sixteen selected output-texel centers each. Results are stored in RGBA32F and
explicitly displayed as 24-bit binary fields over [-16,16]. This provides
64 four-channel records per capture, not inferred screenshot telemetry.
An independent CPU bilinear sampler uses the actual integer source shapes and
the documented whole/half-texel offsets. Guided moments and reconstruction are
computed independently in double precision; the three regularization constants
come from the tested source. Diagnostic values stay inside the encoding range.

| Dimensions | First downscale max error, before→candidate | Second downscale | Guided coefficients | Guided averaging |
|---|---:|---:|---:|---:|
| 1366×769 | 0.000001→0.000001 | 0.000521→0.000140 | 0.000151→0.000002 | 0.000530→0.000002 |
| 1919×1079 | 0.000286→0.000103 | 0.001213→0.000177 | 0.000115→0.000002 | 0.000852→0.000002 |
| 1920×1080 | 0.000229→0.000229 | 0.000534→0.000134 | 0.000002→0.000002 | 0.000002→0.000002 |
| 2560×1440 | 0.000001→0.000001 | 0.000001→0.000001 | 0.000001→0.000001 | 0.000002→0.000002 |

Errors are maximum absolute channel differences in each function's own units;
they are not interchangeable image-quality measurements. At fractional
downscale phases the CPU's ideal bilinear values and GPU sampling still differ
by up to 0.000229. The correction does not eliminate that sampling uncertainty.
Guided candidate errors are at most 0.000002002. All decoded candidate/repeat
records are identical, and all native 2560×1440 before/candidate records are
identical. The first downscale is also unchanged on the selected 1366/1920
positions; the odd 1919 width exposes its spacing difference.

The first CPU analysis mistakenly parsed `GF_ETA=1e-8` as `1` and rounded an
exact rational sample index downward through double precision. Both analysis
issues were corrected before assessment. Retained GPU captures and shader
snapshots are unchanged; corrected oracle values are in `probe_report.json`.

## Full-chain regression

Fifteen fresh private headless processes cover before/candidate/repeat for vivid
Arc imagery with the unchanged GZW profile, Arc clouds with the Arc profile,
and a GZW sunset with GZW tuning. The first two cover both 1366×769 and
2560×1440; the sunset adds native-game lighting coverage at 1366×769. Source
and prepared-image hashes are retained. Prepared sources use Pillow LANCZOS RGB
resampling, including the no-size-change 2560×1440 control. Comparisons match
the exact prepared source within each resolution; they do not compare native
pixels across resolutions. Every process uses the same five-second compilation
wait and twenty-second continuous settle, with zero dropped/delayed frames.

| Input / profile / dimensions | Mean before→candidate ΔE | Changed pixels | Maximum code change | Candidate/repeat changed pixels |
|---|---:|---:|---:|---:|
| Vivid Arc / GZW / 1366×769 | 0.000053145 | 139 | 1 | 0 |
| Vivid Arc / GZW / 2560×1440 | 0 | 0 | 0 | 0 |
| Arc clouds / Arc / 1366×769 | 0.000011814 | 48 | 1 | 0 |
| Arc clouds / Arc / 2560×1440 | 0 | 0 | 0 | 0 |
| GZW sunset / GZW / 1366×769 | 0.000037904 | 144 | 1 | 0 |

ΔE uses the existing motion-tool spatial sample, every fourth pixel after an
eight-pixel border crop, with its standard four-sample mask. Changed-pixel,
maximum-code and clipping checks use
the full raster with only the 2×2 marker excluded. All five candidate/repeat
images are pixel-identical. Neither native-resolution control changes. No case
adds a black or white pixel; no output channel reaches 255 before or after.
The inspected odd-resolution before/candidate/difference overviews retain scene
structure without an obvious new artifact. This is a numerical sampling repair
with a small quantized output footprint, not a demonstrated perceptual benefit
or a reversal of the previously documented material/light costs.

## Adoption

The five tested expressions are applied in `general/grade/grade.fx`. The rest
of the shader, including header comments and previous Retinex/zone/gamut fixes,
is preserved. Profiles, active configs, HDR/SDR boundaries and history rates
remain unchanged. No new control, texture, pass or temporal behavior is added.

Three final fresh private headless captures run the shared grade include under
both profiles on the three odd-resolution inputs. Each is pixel-identical to
its isolated candidate and reports zero dropped/delayed frames. The applied
source matches the tested snapshot after include-path normalization. All 22
diagnostic tooling tests and the whitespace check pass.

The read-only artifact audit verifies 105 distinct retained files across all
27 runtime captures: nine function probes, fifteen held comparisons and three
shared-path checks. Image/source/clip/config/profile/shader hashes, completed
vkBasalt logs, measured dimensions, guided-oracle bounds and the native control
are checked. Runtime source hashes are unchanged within each batch; the only
production shader change between isolated validation and final verification is
the five tested spacing expressions.

## Artifacts and limits

Ignored [captures/kernel_resolution_20261027/](../captures/kernel_resolution_20261027/)
retains the runner, isolated shaders/configurations/profiles, source clips,
captures, source/config/profile/shader/image hashes, runtime log paths and CPU
oracle records. These arithmetic contract probes are not a golden-image suite.
Profiles, active configs and shader header comments are preserved.

The twenty-second held protocol bounds the particular repeat comparisons;
elapsed settling alone does not prove convergence of every slow history.

This audit does not certify the active four-effect chain's unavailable shared
resources, arbitrary aspect ratios, cross-resolution visual invariance, dense
gameplay, cut handoffs or physical high-refresh behavior. The earlier material,
normalization, hue and blue-gradient costs remain; no effectiveness re-score
follows from correcting tap spacing.
