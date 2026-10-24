# Electric Dreams trailer probe — 2026-10-24

Source: [Electric Dreams Environment Sample Project Unreal Engine](https://www.youtube.com/watch?v=8tBNZhuWMac), video ID `8tBNZhuWMac`. The downloaded video-only stream is 1920×1080, 30 fps, H.264, 28.633 seconds, SDR BT.709, SHA-256 `cb82f4f57da75e35ca12e0726f1af8bcc4902e5551f87da79030fff7207e2977`. A local copy and selected captures are under ignored `captures/electric_dreams_2026-10-24/`. This is edited promotional footage with editor UI, black title cards, and intentional glitch frames; it is neither raw GZW gameplay nor a running Unreal world.

The runtime was `gamespecific/gzw/gzw_stronger_trial.conf` with the user's current GZW values. `gzw.conf` and `creative_values.fx` retained their pre-run hashes (`77b33ac8…` and `ed371ec3…`). Only diagnostic ablations temporarily changed the profile; the script restored it. The display was temporarily switched from 2560×1440 at 143.97 Hz to 1920×1080 at 60 Hz for pixel-matched captures, then restored. HDR stayed disabled and the KDE color profile source was sRGB. A first run at 1440p was rejected for capture-size mismatch and stopped before attribution.

## Matched stills from the trailer

FFmpeg extracted clean forest frames at 3.5 seconds and source frame 717 (23.9 seconds). Each ablation used a fresh mpv/vkBasalt process, lossless 30 fps loop of the extracted PNG, `--settle 20`, and an unchanged full repeat. The 2×2 activity marker was checked. The [sunlit-frame report](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_081636.json) and [moving-forest-frame report](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_082732.json) include captured output paths.

| Frame | Full vs source ΔE | Unchanged repeat | Bypass result |
|---|---:|---:|---|
| 3.5 s sunlit forest | 2.19 | 0.001 | FilmCurve <0.01; Retinex 0.07 |
| 23.9 s forest | 7.15 | <0.001 | Contrast 1.64; zone contrast 1.64; shadows 0.18; shadow lift 0.18 |

The clean 3.5-second forest frame has only 0.57% of pixels with a channel above 0.9 and no pixels with RGB channel spread above 0.6. The 0.5-second sky frame is still less extreme. This clip therefore cannot answer the bright saturated object or emitter questions. FilmCurve being quiet here is consistent with insufficient bright-tail input, not a disconnected control.

The 23.9-second forest reveals black clipping under this **GZW profile applied to another game's demo**. In the settled still, pixels with every channel below code value 5 rose from 0.003% of source to 1.803% of full output. Bypassing either `CONTRAST` or `ZONE_CONTRAST` reduced that to 0.069%; bypassing shadow lift did not. The two contrast bypasses produce the same result because the local contrast path depends on both gates. In the real-time video capture, the same source frame was matched against frame 717 by edge comparison, and near-black coverage increased from 0.017% baseline to 5.939% trial. The still and video playback use different source transfer paths and histories, so their black percentages are not directly comparable as a temporal effect. The clipping is a concrete cross-game stress finding; it does not by itself establish a shader algorithm defect or justify changing the user's GZW tuning.

## Real motion and cuts

The [motion report](../gamespecific/gzw/full_analysis/alternate/electric_dreams_motion_2026-10-24.json) records baseline and trial snapshots at 12 target times during continuous playback. Most pairs differ by one 30 fps frame, so direct pixel metrics are restricted to identical source frames. The 23.9-second pair was confirmed to match source frame 717; its raw/trial side-by-side image is `captures/electric_dreams_2026-10-24/forest_frame717_pair.jpg`. The 10.9-second black title card is time-matched and shows no residual forest image. On baseline-black pixels at 10.9 and 15.6 seconds, the trial's 99th percentile remains code value 0. The 19.9-second moving-text pair falls on adjacent source frames and cannot be used to infer ghosting from its difference.

Both continuous passes reported zero mpv dropped and delayed frames at 30 fps on the temporary 60 Hz display. This establishes playback headroom for this workload, **not shader GPU cost**: decoding, presentation, and the 30 fps source cap confound timing, and the earlier untimed mpv/MangoHud pairs were CPU/compositor limited. A running real-time world or game is still needed for a defensible GPU-cost measurement. Twelve retained screenshots are spot checks, not a full-frame flicker scan.

No shader or tuning edit was made. The exact-black increase warrants review with raw GZW footage before any change to the contrast path. The full working tree, the staged deletion of `startprompt-2026-10-23.md`, and the unswitched `gzw.conf` were preserved.
