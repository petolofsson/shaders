# Babylon.js Firefox/vkBasalt smoke test — 2026-10-24

The user requested a fully automated real-time scene and observed the red activity marker in a Gamescope window. A minimal Babylon.js WebGPU scene was served on localhost from an isolated `/tmp` directory. It rendered a moving camera, nine colored/emissive spheres, a ground plane, and an SDR sRGB canvas. The local Babylon.js library came from `https://cdn.babylonjs.com/babylon.js` and had SHA-256 `5e162a4179028c7aa6e110879039a173f67337c170d0788a8733a20d00231f83`. The Firefox test used a temporary profile with `dom.webgpu.enabled=true`; the user's normal browser profile was untouched. No plugin or second Mozilla browser was needed. See [Babylon WebGPU setup](https://doc.babylonjs.com/setup/support/webGPU) and [Mozilla's Linux WebGPU status](https://developer.mozilla.org/en-US/docs/Mozilla/Firefox/Experimental_features).

| Presentation path | Babylon WebGPU | vkBasalt effect | Evidence |
|---|---|---|---|
| Native Firefox Wayland kiosk | Rendered 60 frames | No | vkBasalt parsed the GZW trial config, but created no ReShade effect; fullscreen capture had no red marker. |
| Firefox in Gamescope Wayland backend | Rendered 60 frames | No | vkBasalt log stopped after Vulkan device/queue setup. |
| Firefox in Gamescope SDL backend, 1920×1080 window | Rendered 60 frames | Yes | vkBasalt logged fake swapchain images, effect creation, and repeated application; user saw the red marker. |
| Firefox in Gamescope SDL backend, fullscreen 2560×1440 | Rendered 60 frames | Yes | Log again shows effect creation/application with no errors; captured top-left 2×2 pixels are exactly `(255, 0, 0)`. |

The successful command shape was:

```text
ENABLE_VKBASALT=1 VKBASALT_CONFIG_FILE=<absolute gzw_stronger_trial.conf> \
gamescope --backend sdl -W 2560 -H 1440 -w 2560 -h 1440 -f -- \
env ENABLE_VKBASALT=0 MOZ_ENABLE_WAYLAND=0 \
firefox -no-remote -profile <temporary WebGPU-enabled profile> --kiosk http://127.0.0.1:8768/
```

Here vkBasalt processes **Gamescope's Vulkan output**, not Firefox's WebGPU canvas directly. The canvas requested standard SDR tone mapping and sRGB; Gamescope HDR was off. The [1440p screenshot](../captures/babylon_firefox_smoke_2026-10-24/gamescope_1440_focused.png), [vkBasalt log](../captures/babylon_firefox_smoke_2026-10-24/gamescope_1440_vkbasalt.log), and smoke-test HTML/server are retained locally under ignored `captures/babylon_firefox_smoke_2026-10-24/`. The trial config and user tuning hashes remained unchanged (`82d2b63e…` and `ed371ec3…`), and `gzw.conf` was not switched.

This establishes a working delivery path for repeatable scene stress tests at native 1440p. It does **not** establish pixel-exact color transfer through Firefox and Gamescope, stable frame matching, or shader GPU cost. The test page's reported 60 fps is a presentation-limited observation, not an overhead measurement. Next implementation work is a fixed-timestep camera/cut sequence, explicit SDR color bars for transfer validation, frame-indexed captures, and paired GPU timings with the same Gamescope/Babylon workload. The temporary browser, Gamescope instances, local server, and KWin focus script were stopped/unloaded after the test.
