# Spatial and color attribution — 2026-10-26

Continues PLAN 3 after the completed history and signal-contract audits.
Current shared code is assessed using private headless captures and isolated
shader/profile copies. Existing profiles, active configs, shader headers and
prior corrections remain intact.

## Protocol

Each capture starts a fresh process, waits five seconds for compilation and
plays a lossless 30 fps held-source clip continuously for twenty seconds before
capture. Playback advancement, dimensions and the activity marker are checked.
Held Babylon pose 1044/token 262 additionally checks its exact decoded identity.
Source, shared-code, profile, config, isolated-shader, clip and image hashes are
retained. Runtime logs are indexed per capture. Equal warmup is a reproducible
protocol, not proof of convergence.

Ignored [captures/spatial_color_20261026/](../captures/spatial_color_20261026/)
contains capture/analysis scripts, isolated copies, manifests, images and crops.
The combined GZW trial is used throughout, including the vivid Arc input under
GZW tuning. This does not validate the active separate-effect data path or a
unified cross-game preset. There is no new dense-motion or high-refresh claim.

Measurements use Oklab L/C on the ×100 scale. Material selections come from
source pixels; bypasses share those selections. Lightness group gaps compare
the median output of fixed source bottom/top quintiles. These measurements
describe redistribution, not fidelity or aesthetic effectiveness.

## Coarse-zone interior gradients

Seven fresh captures compare full/repeat, zone-off, Retinex-off and three
diagnostics: hold only zone median, only IQR, or both at the purple face's
center UV (0.626171875, 0.530555556). This changes only the consumer's field
lookup; histogram production, history, global context and strength remain.
Frozen fields are diagnostic interventions, not deployment candidates.

Exact source-RGB masks are eroded eight pixels from boundaries on the full
source raster, then intersected with ROI (800,700)–(1840,870). All selected
source interiors have zero lightness spread. Full/repeat images are byte
identical and all seven captures have zero dropped/delayed frames.

| Source material | Full L95−L5 | Fixed median | Fixed IQR | Fixed both | Zone off | Retinex off |
|---|---:|---:|---:|---:|---:|---:|
| Purple (113,86,239) | 0.455 | 0.301 | 0.455 | 0.301 | 0.310 | 0.412 |
| Magenta (247,84,211) | 0.591 | 0.348 | 0.591 | 0.348 | 0.404 | 0.393 |
| Blue background (89,140,199) | 0.912 | 0.323 | 0.912 | 0.323 | 0.102 | 0.911 |
| Orange (254,162,28) | 0.311 | 0.312 | 0.311 | 0.312 | 0.312 | 0.503 |
| Green (99,229,64) | 0.299 | 0.266 | 0.299 | 0.266 | 0.300 | 0.296 |

Pixel spread includes spatial dither and code quantization. An additional
measurement averages L in aligned 8×8 blocks wholly inside the eroded mask,
then takes the same 95th−5th percentile spread across those block means:

| Material | Full block spread | Fixed median | Fixed IQR | Zone off | Retinex off |
|---|---:|---:|---:|---:|---:|
| Purple | 0.259 | 0.016 | 0.259 | 0.016 | 0.248 |
| Magenta | 0.469 | 0.164 | 0.469 | 0.192 | 0.291 |
| Blue background | 0.564 | 0.019 | 0.564 | 0.021 | 0.643 |
| Orange | 0.157 | 0.018 | 0.157 | 0.020 | 0.182 |
| Green | 0.238 | 0.014 | 0.238 | 0.014 | 0.162 |
| Cyan | 0.301 | 0.019 | 0.301 | 0.020 | 0.211 |

The median field explains most low-frequency variation on purple, background,
orange, green and cyan; pixel spread alone had hidden some of that contribution.
Magenta retains a larger non-zone contribution. The IQR-only intervention
leaves these measured spreads unchanged; this does not mean IQR is universally
inactive or that its full output is byte-identical. Retinex is not the chief
cause of the uniform background's gradient. Its effects differ across faces,
and nonadditive downstream processing prevents summing bypass contributions.

The zone expression uses `delta = luma_orig - zone_median`. For a uniform
input, a spatially varying median therefore creates a varying adjustment even
when input detail is zero. Bilinear interpolation of a 4×4 median field is
smooth but does not preserve uniform material interiors. This is a spatial
model limitation after the prior numerical/history repairs, rather than
evidence to accelerate histories or restore boundary-dependent strength fades.
The magenta residual prevents treating median freezing as a complete flatness
repair; other faces approach their zone-off block spread. These averages reduce
dither sensitivity but do not supply an independent transfer uncertainty bound.
Inspected native crops retain the prior rim removal;
freezing all zones at one face also changes other materials' tonal placement.

## Blue-sky shade separation

The vivid Arc source is assessed with the retained GZW profile and combined
trial. Six fresh processes compare full/repeat and corrective, tonal, chroma
and look bypasses. The fixed sky ROI is (1500,100)–(2100,360), 156,000 pixels.
Source bottom/top lightness quintiles stay fixed for every output.

| Output | Median L | Median C | Source-group L gap | Median hue shift |
|---|---:|---:|---:|---:|
| Source | 67.448 | 10.233 | 9.709 | 0° |
| Full | 62.047 | 12.653 | 6.939 | +3.472° |
| Corrective off | 63.850 | 12.257 | 5.556 | +2.596° |
| Tonal off | 61.882 | 12.662 | 11.234 | +3.578° |
| Chroma off | 62.041 | 10.241 | 7.035 | +3.470° |
| Look off | 65.560 | 14.377 | 6.763 | +0.154° |

Full and repeat are byte-identical. Tonal processing is the main source of
the narrower selected shade gap. Print chiefly changes brightness and hue
here; its bypass does not restore separation. Chroma bypass changes the gap
only slightly. Corrective bypass narrows it further, so undoing the earlier
inverse-luma units repair would confuse a numerical correction with this
remaining model interaction. FilmCurve remains separately active under the
tonal gate, as required by the existing control contract.

Four additional fresh captures separate local tonal contributions:

| Targeted bypass | Median L | Source-group L gap |
|---|---:|---:|
| Retinex off | 61.827 | 11.577 |
| Zone contrast off | 62.147 | 6.461 |
| Retinex and zone off | 61.908 | 11.161 |
| Shadow lift off | 61.992 | 6.991 |

Retinex is the dominant cause on this selected crop. Zone contrast slightly
counteracts the compression, and shadow lift is a small contribution. The
native-luma guided reconstruction fixed material rims, but its bounded
illuminant-normalization gain still reduces broad sky/cloud lightness
variation. A gain bound does not guarantee retained local shade separation.
This points to an illumination-model question, not a reason to restore the
previous halo-producing coarse-edge strength fade. Retinex-off also overshoots
the source gap, so a blanket bypass is not demonstrated to be a complete remedy.
Inspected crops show the source-defined cloud structure retained but less
separated in full output; more games/motion remain necessary for any repair.

## Overcast green hue

Six fresh captures use the GZW overcast source, its original GZW profile and
the same combined trial. ROI (300,300)–(2200,1200) selects source Oklab hue
100°–180°, C>2, L<65. Hue shifts additionally require source C>3, matching the
earlier stage-review selection. Full/repeat are byte-identical.

| Output | Median L | Median C | Source-group L gap | Median hue shift |
|---|---:|---:|---:|---:|
| Source | 27.568 | 3.685 | 16.570 | 0° |
| Full | 26.053 | 4.034 | 17.570 | +10.210° |
| Corrective off | 26.025 | 4.482 | 17.595 | −0.706° |
| Tonal off | 24.384 | 3.968 | 16.109 | +10.928° |
| Chroma off | 26.025 | 3.189 | 17.572 | +9.705° |
| Look off | 29.191 | 4.243 | 18.015 | +12.116° |

The corrective stage dominates this selected hue displacement. Disabling
chroma leaves most of it intact; disabling print increases it. The source
palette remains restrained and the full output retains source-group lightness
separation, but neither fact cancels the measured palette shift. The mask
contains 594,939 pixels; it is a material selection, not an entire-scene hue score.

Two targeted fresh captures distinguish the existing profile from the small
baked green rotation:

| Targeted bypass | Median L | Median C | Median hue shift |
|---|---:|---:|---:|
| Three-way CC only off | 26.025 | 4.480 | −0.705° |
| Green hue rotation only off | 26.052 | 4.036 | +10.042° |

Neutralizing only the six three-way temperature/tint values nearly reproduces
the corrective-stage bypass's hue result. The original GZW profile has
SHADOW_TEMP=−0.15, SHADOW_TINT=−0.05, neutral midtones and HIGHLIGHT_TEMP=+0.10.
The three-way helper adds the selected zone's Oklab a/b offset, so a small
absolute offset can rotate low-chroma foliage appreciably. This is a measured
consequence of the existing manual grade, not demonstrated hue-wrap corruption
or the green rotation creating a ten-degree displacement. The rotation-only
bypass changes the selected median shift by about 0.168°. Native crop review
shows the expected cooler foliage in full output. Preserve the profile; this
attribution does not justify rewriting its manual color choices.

## Verification and next work

All 25 captures have zero dropped/delayed frames and no vkBasalt error in their
completed logs. Each of the three full/repeat pairs is byte-identical. Offline
verification confirms exact source RGB in the first decoded lossless-clip frame,
all recorded hashes, Babylon identities and unchanged shared sources/profiles
across all five batches. [Verification manifest](../captures/spatial_color_20261026/verification.json).
The early foliage launch was refused by the capture lock while sky owned it;
it rendered nothing and the later serialized run completed normally.

No shared shader change is adopted from the diagnostic freezes or broad
bypasses. They establish causes, not general remedies. Next prioritize a zone
median-field reconstruction that preserves uniform interiors, and Retinex
restraint that preserves broad cloud/sky structure without restoring the prior
boundary-strength halos. Any candidate needs current-code Arc/GZW regressions,
unchanged repeats, dark-material/colored-highlight checks and matched motion.
Neither speeding histories nor global saturation/print retuning follows from
these results. The existing manual green treatment is explained independently
and need not block that technical work.

PLAN 3's initial three-way attribution is complete; spatial remedies, broader
hue/gamut continuity and illumination-boundary coverage remain open. Twenty
diagnostic tooling tests and the whitespace check pass. These checks do not
establish overall visual acceptance, active-chain integration or a higher
effectiveness score. No new effect or profiling is introduced.

The subsequent [zone follow-up](2026-10-26_zone_scene_pivot.md) applies a bounded
scene-adaptive curve after rejecting two simpler candidates. Use its applied
captures as the post-zone baseline; the attribution captures above predate
that repair. The subsequent [Retinex sky repair](2026-10-26_retinex_sky.md)
restores measured sky separation with source-domain guide reconstruction and
restrained gain. Broader spatial/temporal coverage remains open.
