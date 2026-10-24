# Background image analysis — 2026-10-24

`compare_frame.py` now defaults to a private headless GPU display. Normal
single-reference, batch, effect-attribution and scene-cut capture paths route
through the same backend. It opens no host window, changes no desktop focus
or physical monitor mode, and never silently falls back to a desktop shot.
`--capture-backend desktop` explicitly selects the previous visible path.

## Implementation

[headless_display.py](../tools/headless_display.py) starts Gamescope with
`--backend headless`, a private 0700 runtime directory and source-sized output.
Host display environment variables are removed. The client runs mpv through
X11 Vulkan inside Gamescope's own Xwayland server. vkBasalt is enabled on that
client, while the compositor has it disabled. This matters because the
[headless backend has no Vulkan presentation swapchain](https://github.com/ValveSoftware/gamescope/blob/master/src/Backends/HeadlessBackend.cpp).
The [Gamescope control protocol](https://github.com/ValveSoftware/gamescope/blob/master/protocol/gamescope-control.xml)
provides a screenshot request; `gamescopectl screenshot` saves the composited
client image after vkBasalt. This is not mpv's pre-presentation screenshot path.

Private captures validate dimensions and PNG completion. Shader runs still
require the red activity marker and an advancing source before temporal
capture. Compositor/client process groups are cleaned up on normal exit and
startup/capture failure; cleanup also handles an already-exited group leader.
The renderer logs and private-display metadata remain in the printed
`/tmp/shader-runtime-*/` directory. Reports identify the capture backend.
`--baseline` captures a single reference with vkBasalt disabled to validate
transfer, and is rejected in effect-attribution mode.

## Runtime validation

- A 2560×1440 shader-disabled target includes all 256 neutral code levels,
  black/white, primaries/secondaries, orange and near-black patches. Maximum
  difference is one 8-bit channel code; 97.93% of channels are exact. Source
  black stays 0 and white stays 255. The default-backend cleanup smoke run
  reproduced the same result.
- Dark GZW combined-trial full/repeat captures use fresh processes, 5-second
  compile wait and 20-second continuous settle. The [headless report](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_151656.json)
  has unchanged-repeat mean ΔE 0.0000233 and the active shader marker.
  Desktop→headless mean ΔE on 4× spatial sampling is 0.00256 (p99 0.17546).
  This is close, not pixel-identical; compare small effects against a repeat
  from the same backend instead of mixing historical methods.
- A second run omitted the backend flag, verifying the new default. The
  vivid Arc input under GZW tuning used full/repeat/SATURATION bypass and
  20-second settling. [Report](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_152514.json):
  repeat ΔE 0.0000201; saturation contribution 0.92176. All three captures
  contained the activity marker. This establishes processed output, not only
  successful creation of a virtual display.
- Private Wayland control sockets were removed after the observed runs.
  Sixteen diagnostic tests pass, including private socket routing, refusal
  of desktop fallback, startup cleanup and cleanup after compositor exit.
- Shader sources, tuning profiles and both GZW configs match their hashes
  before this tooling work. This continuation makes no shader changes.

The transfer target/output and numerical record are retained under ignored
`captures/headless_capture_20261024/`. The retained full/repeat images are
linked by each report's `retained_capture_dir`.

## Speed and scope

The verified improvement is unattended capture. Twenty seconds of settling
still means twenty seconds of real rendered time; reducing it would change
the temporal test. Direct capture removes desktop screenshot tool retries,
window-occlusion failures, and fullscreen-restoration warmups. In the single
observed dark two-capture pair, report timestamps span about 55 seconds
headless versus 75 seconds for the earlier desktop run at the same 5/20
compile/settle settings. This is an observation, not a repeatable speed claim.
GPU work still runs alongside other applications.

The separate [Babylon runner](../tools/babylon_scene/README.md) now also uses
private source capture and matched lossless replay. Its conversion and exact
identity/coverage validation are documented in [the continuation](2026-10-24_background_motion_resume.md).
Live `tune`, game `capture`, and legacy `stage_isolate` retain visible-desktop
behavior; they are not unattended headless validation paths.
