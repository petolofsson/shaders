# Grade chroma headroom screen — 2026-11-01

**Closed with all four candidates rejected. Production is unchanged.** The user
requested reading the startup prompt and finding new improvement candidates.
This screen tests a new grade-stage cooperation hypothesis; it does not reopen
the completed inverse, print-toe or combined tonal-gain screens.

## Target and isolated candidates

The retained blue hue/gradient costs suggested checking whether automatic
grade-stage chroma additions unnecessarily drive the final SDR projection.
The hypothesis was that budgeting those additions before projection could
retain useful hue or color distinctions. This was a hypothesis, not an
established attribution of the remaining costs.

Both profiles have neutral optional vibrance. The initial pair therefore limits
the small memory-color additions above the existing `C_floor`, which already
includes the fixed midtone expansion. The broader pair also includes that
midtone expansion in the restrained contribution. All versions preserve the
intentional shadow desaturation and manual saturation factors.

Each isolated grade copy performs a fixed fourteen-step search between its
preserved base chroma and the existing pre-knee result, at the existing output
lightness and direction. Valid upper endpoints retain the existing result.
Otherwise the full variant caps the addition at the searched bound; the half
variant blends halfway toward that cap. The broader pair uses the input chroma
after shadow desaturation and manual saturation as its base. The search does
not replace final gamut projection or establish that an already invalid base
is in gamut. No general gamut or hue-preservation guarantee is inferred.

The four labels are `cap`, `half`, `mid_cap` and `mid_half`. Only isolated
`ApplyChroma` body code changes. Profiles, configs, headers, production shaders,
analysis, histories/rates, resources and pass counts remain unchanged.

## Evidence and decision

Three held cases cover vivid daylight/blue material with the GZW profile, Arc
interior cool/warm/dark materials, and Arc white/red emitters. The vivid source
is an Arc screenshot deliberately processed with GZW settings, retaining its
previous assessment identity; it is not a third game. Current baseline images
and their unchanged repeats are reused only after checking the latest weak-color
verification hashes, source, profile, normalized grade, isolated-file and clip
identities. All seven available baseline pairs are exact.

The initial pair leaves the interior pixel-identical and changes at most eleven
pixels in either other case, each by at most one code. Selected blue sky, blue
field, cool-window, warm-floor and dark-metal measurements do not improve. The
broader pair still changes only a few pixels in the vivid case: 23 pixels at up
to two codes for `mid_cap`, and 19 at one code for `mid_half`. Selected blue-sky
hue and color separation remain identical; blue-field color separation changes
only about 0.000012 on the Oklab ab ×100 scale. These numbers do not establish a
visible benefit or explain the retained blue costs.

| Case | `cap` changed pixels | `half` | `mid_cap` | `mid_half` |
|---|---:|---:|---:|---:|
| GZW-profile vivid | 6 | 11 | 23 | 19 |
| Arc interior | 0 | 0 | 325 | 118 |
| Arc emitters | 6 | 2 | 71 | 49 |

Counts exclude the activity marker. Every case is 2560×1440. All changes are at
most one code except the two-code vivid `mid_cap` result. Maximum sampled mean
change is 0.00000407 ΔE, using the established stride-four interior sampling;
sampling can miss isolated altered pixels and is not a maximum pixel error.
No candidate adds black or code-255 channel pixels. Interior selected material
measurements and emitter core/halo separation remain unchanged. Red-lamp hue
shifts by less than 0.001° relative to baseline. Native comparison crops show no
useful visible improvement. Candidate repeats were not run, so the small
differences are not assigned exclusively to shader behavior rather than render
variation or compilation roundoff.

The candidates are rejected because this held screen demonstrates no useful
target gain. Adding another gamut search is unjustified on this evidence.
This is scoped nonintervention evidence, not proof that grade chroma never
engages a gamut boundary. No adoption, effectiveness re-score or mandatory
follow-up sweep follows.

## Validation scope

Each new capture uses a fresh private headless GPU process, five seconds compile
wait and twenty seconds continuous settling. The intentional marker is excluded
from full-image metrics; source-selected region masks match the earlier reports.
Warmup alone does not prove universal convergence. Ordinary screenshots contain
no hidden history telemetry.

This is an early rejection screen. Candidate motion, zero bypasses, boundary
charts, independent numeric GPU contracts and actual-config adoption checks are
not claimed. Twelve fresh private processes have zero dropped/delayed frames.
The artifact audit verifies 104 isolated files and 26 images, including fourteen
reused baseline/repeat images. Shader/profile/trial-config and both active-config
hashes are unchanged. The existing production validation remains at the
weak-color checkpoint. The 22 diagnostic tooling tests and whitespace checks pass.

Local ignored evidence: `captures/grade_chroma_budget_20261101/report.json`,
`metrics.json`, `audit.json`, isolated configs/shaders, runtime log paths and native
comparison crops. Candidate scripts and media remain ignored; no commit or push
is made.

- [Vivid blue material](../captures/grade_chroma_budget_20261101/gzw_vivid_blue_field.png).
- [Cool-window material](../captures/grade_chroma_budget_20261101/arc_interior_cool_window.png).
- [Red emitter](../captures/grade_chroma_budget_20261101/arc_emitters_red_lamp.png).
