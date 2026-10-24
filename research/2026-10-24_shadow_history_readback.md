# Shadow history readback — 2026-10-24

After accepting the [private matched motion course](2026-10-24_background_motion_resume.md),
a temporary combined technique explicitly renders selected offscreen history
values into an 8×8 diagnostic tile grid. This is deliberate shader readback,
not the unsupported `capture --dump` screenshot path. Shared shaders, header
comments, both creative profiles and GZW configs remain unchanged.

Each normalized scalar is packed into three six-bit digits spaced four SDR
codes apart. Median decoding tolerates the previously measured one-code
compositor transfer discrepancy. Seven fixed test values, including endpoints
and 0.0001/0.003, decode within 0.000003 in every capture. Adaptive strengths
use a /2 scale at the boundary. Instrumented output is deliberately encoded
statistics and must not be scored as rendered-image fidelity.

The diagnostic preserves the full combined pass order and appends only its
readback pass. Four fresh private processes cover dark→sunset→dark twice and
an unchanged static dark source twice. The source hashes match the preceding
cut probe. The transition plays dark for 20 seconds, sunset for eight seconds,
then dark for 52 seconds at 30 fps. Five seconds of compile wait precedes a
seek to clip start. Snapshots occur during continuous playback without pauses.
All four processes report zero dropped/delayed mpv frames.

Artifacts, preparation/capture scripts, diagnostic shader/config, source hashes
and [readback report](../captures/history_probe_20261024/report.json) remain in
ignored `captures/history_probe_20261024/`. The temporary diagnostic's first
compile used the reserved HLSL identifier `packed`; changing it to `code_word`
resolved the compile failure. No shared shader fix was needed.

## Measured state

| Dark sample | Slow key, transition | Slow key, transition repeat | Static dark key |
|---|---:|---:|---:|
| Before cut | 0.029816 | 0.029816 | 0.029816 |
| Return +0.5 sec | 0.044892 | 0.044769 | 0.029816 |
| Return +6.5 sec | 0.039368 | 0.039276 | 0.029816 |
| Return +18 sec | 0.030060 | 0.030014 | 0.029816 |
| Return +50 sec | 0.029816 | 0.029816 | 0.029816 |

All 16 raw zone medians and their 16 history medians match the static dark
reference at every captured dark point, including return +0.5 seconds.
Global zone key and zone standard deviation also match. The long tail is
therefore not continuing local-zone convergence in these measured snapshots.
The shadow adaptive history is 1.499022 both before the cut and at +6.5/+18/+50;
its computed target is about 1.499968. It does not carry the long residual.

Histogram mode has a smaller persistent difference: 0.039063 before the cut
versus 0.038910 at +6.5, +18 and +50 seconds, identically in both transition
runs. Static mode remains 0.039063. This offset needs separate attribution;
its presence alone does not establish a material output defect.

The slow key uses a deliberate 20-second half-life, with a faster response
weighted by scene-cut confidence. Its measured response also passes through
half-float texture storage. These readbacks do not establish that arbitrarily
speeding it up would improve fidelity. The next attribution intervention holds
only grade's slow-key consumer at the measured settled dark value while
upstream histories continue normally, and compares output residuals with two
normal and two intervention runs.


## Isolate the output residual

A second temporary technique replaces only `ctx.slow_key` in grade with the
measured initial dark value, 0.029815673828125. Upstream slow key, zone history,
analysis and adaptive history continue to run. This is an attribution
intervention, not a proposed general shader correction: holding this constant
would remove useful scene adaptation elsewhere.

Four fresh normal-output runs (normal/repeat and fixed-consumer/repeat) use the
same source transition, five-second compile wait and continuous 30 fps
playback. Comparisons crop eight pixels and sample every fourth pixel.

| Output | Before→return +6.5 sec ΔE | Before→return +18 sec ΔE |
|---|---:|---:|
| Normal | 0.340970 | 0.013270 |
| Normal repeat | 0.340973 | 0.014158 |
| Fixed slow-key consumer | 0.000024 | 0.000018 |
| Fixed-consumer repeat | 0.000019 | 0.000020 |

The intervention reduces the residual to capture/repeat scale. Together with
the direct readbacks this identifies the slow-key consumer as the material
cause on this matched dark/sunset pair. Local zone lag is ruled out at the
measured points. The smaller mode/history offsets are not material here.
The normal tail largely reflects deliberate slow ambient adaptation; no
adaptation rate, profile or shared shader is changed on this evidence alone.
All four output runs report zero dropped/delayed frames. Normal unchanged
repeat differences are 0.000013/0.000017/0.000907 ΔE before/+6.5/+18; fixed
consumer repeat differences are 0.000001/0.000009/0.000002. The nonzero normal
+18 variation is consistent with sampling a slowly changing history.
[Attribution report](../captures/history_probe_20261024/isolation_report.json).
