"""Capture correctness checks; no golden images or visual-quality scores."""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import compare_frame as compare
import capture
from babylon_scene import background as motion
from types import SimpleNamespace
from headless_display import HeadlessDisplay
from analyze_delta import compute_relative


class FrameMetricsTests(unittest.TestCase):
    def test_marker_does_not_count_as_an_effect(self):
        before = np.full((8, 8, 3), 0.18)
        after = before.copy()
        after[:2, :2] = [1, 0, 0]
        result = compute_relative(before, after)
        self.assertEqual(result["mean_de"], 0)
        self.assertEqual(result["masked_pixels"], 4)
        after[4, 4] = [1, 0, 0]
        self.assertGreater(compute_relative(before, after)["mean_de"], 0)

    def test_endpoint_metrics_include_single_channel_clipping(self):
        black = np.zeros((4, 4, 3))
        red = black.copy()
        red[..., 0] = 1
        stats = compute_relative(black, red)["endpoints"]
        self.assertEqual(stats["before"]["black_pct"], 100)
        self.assertEqual(stats["after"]["any_channel_white_pct"], 100)
        self.assertEqual(stats["after"]["black_pct"], 0)

    def test_invalid_pairs_are_rejected(self):
        good = np.zeros((4, 4, 3))
        for bad in (np.zeros((3, 4, 3)), np.full_like(good, np.nan)):
            with self.assertRaises(ValueError):
                compute_relative(good, bad)


class MotionIdentityTests(unittest.TestCase):
    @staticmethod
    def label(frame, token):
        payload = frame | (token << 12) | (((frame ^ token ^ 0xa5) & 255) << 24)
        rgb = np.zeros((16, 256, 3), dtype=np.uint8)
        for i in range(32):
            start = i * 8 + (0 if (payload >> i) & 1 else 4)
            rgb[-4:, start:start + 4] = 255
        return rgb

    def test_identity_roundtrip_and_corruption(self):
        rgb = self.label(2160, 4095)
        self.assertEqual(motion.read_identity(rgb), (2160, 4095))
        rgb[-4:, :8] = 255 - rgb[-4:, :8]
        with self.assertRaisesRegex(RuntimeError, "checksum"):
            motion.read_identity(rgb)
        with self.assertRaisesRegex(RuntimeError, "contrast"):
            motion.read_identity(np.zeros_like(rgb))

    def test_mismatch_excluded_and_cut_coverage_required(self):
        frames = [420, 1080, 1420, 1452, 1620, 2140, 2172]
        captures = {f"{f}:1": {"frame": f, "image": str(f)} for f in frames}
        runs = {name: {"captures": dict(captures)} for name in ("baseline", "trial", "repeat")}
        runs["trial"]["captures"]["444:2"] = {"frame": 444, "image": "mismatch"}
        with patch.object(motion, "compare_images", return_value={"mean_de": 0}):
            summary = motion.summarize_motion(runs, 2220)
            self.assertEqual(summary["matched_frames"], 7)
            self.assertEqual(summary["unmatched_frames_excluded"]["trial"], 1)
            del runs["repeat"]["captures"]["1452:1"]
            with self.assertRaisesRegex(RuntimeError, "after_night_cut"):
                motion.summarize_motion(runs, 2220)

    def test_coverage_retry_preserves_captures_and_attempt_counters(self):
        runs = {}
        for name, frame in (("baseline", 0), ("trial", 4), ("repeat", 8)):
            runs[name] = {"captures": {f"{frame}:1": {"frame": frame, "image": f"original-{name}"}},
                          "playback": {"frame-drop-count": 0}, "sample_ranges": [(0, 48)]}
        extra = {"captures": {"8:1": {"frame": 8, "image": "new"}},
                 "playback": {"frame-drop-count": 2}, "sample_ranges": [(0, 48)]}
        with patch.object(motion, "replay_motion", return_value=extra), \
             patch.object(motion, "compare_images", return_value={"mean_de": 0}):
            result = motion.collect_motion({"route_frames": [0, 48]}, Path("unused"), runs, max_attempts=2)
        self.assertEqual(result["matched_frames"], 1)
        self.assertEqual(runs["repeat"]["captures"]["8:1"]["image"], "original-repeat")
        self.assertEqual(len(runs["baseline"]["attempts"]), 2)
        self.assertEqual(runs["baseline"]["attempts"][1]["playback"]["frame-drop-count"], 2)

    def test_cache_rejects_different_settling_before_hash_check(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "manifest.json").write_text(json.dumps({"pre_roll_s": 1}))
            with self.assertRaisesRegex(RuntimeError, "protocol differs"):
                motion.load_motion(Path(tmp), SimpleNamespace(settle=20, source_fps=15, stop_frame=2220))

    def test_temporal_pairing_rejects_another_update_of_the_same_pose(self):
        frames = [420, 1080, 1420, 1452, 1620, 2140, 2172]
        runs = {label: {"captures": {
            f"{frame}:1": {"frame": frame, "image": str(frame),
                             "render_phase": {"source_update": 1, "cut_update": 1}}
            for frame in frames}} for label in ("baseline", "trial", "repeat")}
        with patch.object(motion, "compare_images", return_value={"mean_de": 0}):
            summary = motion.summarize_motion(runs, 2220, require_render_phase=True)
            self.assertEqual(summary["render_phase_verified_frames"], 7)
            runs["repeat"]["captures"]["2172:1"]["render_phase"] = {
                "source_update": 2, "cut_update": 2}
            with self.assertRaisesRegex(RuntimeError, "after_return_cut"):
                motion.summarize_motion(runs, 2220, require_render_phase=True)
            coarse = motion.summarize_motion(runs, 2220)
            self.assertEqual(coarse["matched_frames"], 7)
            self.assertEqual(coarse["render_phase_verified_frames"], 6)
            self.assertIsNone(coarse["pairs"][-1]["render_phase"])

    def test_source_identity_and_host_time_do_not_supply_render_phase(self):
        capture = {"frame": 0, "image": "pose", "video_time_before": 20.0,
                   "video_time_after": 20.1}
        runs = {label: {"captures": {"0:1": dict(capture)}}
                for label in ("baseline", "trial", "repeat")}
        with self.assertRaisesRegex(RuntimeError, "measured render-phase"):
            motion.matched_motion(runs, 48, require_render_phase=True)


class CaptureTests(unittest.TestCase):
    def test_private_cleanup_handles_a_compositor_that_already_exited(self):
        display = HeadlessDisplay.__new__(HeadlessDisplay)
        display.process = MagicMock()
        display.process.pid = 12345
        display.process.poll.return_value = 1
        display.log = MagicMock()
        with patch("headless_display.os.killpg") as kill_group:
            display.close()
        kill_group.assert_called_once()
        self.assertEqual(kill_group.call_args.args[0], 12345)
        display.process.wait.assert_called_once()
        display.log.close.assert_called_once()

    def test_private_capture_cannot_fall_back_to_desktop(self):
        with patch.object(compare, "CAPTURE_BACKEND", "headless"), \
             patch.object(compare, "_headless_display", None), \
             patch.object(compare, "take_screenshot") as desktop:
            with self.assertRaisesRegex(RuntimeError, "refusing a desktop capture"):
                compare._capture_frame(Path("unused.png"))
            desktop.assert_not_called()

    def test_private_capture_routes_control_to_its_own_display(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            display = HeadlessDisplay.__new__(HeadlessDisplay)
            display.width, display.height = 8, 8
            display.log_dir = root
            display.client_info = root / "display.json"
            display.client_info.write_text(json.dumps({
                "GAMESCOPE_WAYLAND_DISPLAY": "private-0", "XDG_RUNTIME_DIR": str(root),
            }))
            display.process = MagicMock()
            display.process.poll.return_value = None
            output = root / "frame.png"

            def capture_private(command, **kwargs):
                self.assertEqual(kwargs["env"]["GAMESCOPE_WAYLAND_DISPLAY"], "private-0")
                self.assertEqual(kwargs["env"]["XDG_RUNTIME_DIR"], str(root))
                self.assertNotIn("DISPLAY", kwargs["env"])
                self.assertNotIn("WAYLAND_DISPLAY", kwargs["env"])
                Image.new("RGB", (8, 8)).save(output)
                return subprocess.CompletedProcess(command, 0, "", "")

            with patch.dict("os.environ", {"DISPLAY": ":host", "WAYLAND_DISPLAY": "host-0"}), \
                 patch("headless_display.subprocess.run", side_effect=capture_private):
                display.screenshot(output)
            self.assertTrue(output.exists())

    def test_private_startup_failure_closes_the_display(self):
        with tempfile.TemporaryDirectory() as tmp:
            sock = Path(tmp) / "absent.sock"
            display = MagicMock()
            display.process.poll.return_value = 1
            probe = subprocess.CompletedProcess([], 0, '{"streams":[{"width":8,"height":8}]}', "")
            with patch.object(compare, "CAPTURE_BACKEND", "headless"), \
                 patch.object(compare, "_headless_display", None), \
                 patch.object(compare, "SOCK", sock), \
                 patch.object(compare, "_acquire_capture_lock"), \
                 patch.object(compare.subprocess, "run", return_value=probe), \
                 patch.object(compare, "HeadlessDisplay", return_value=display):
                with self.assertRaisesRegex(RuntimeError, "mpv did not start"):
                    compare._launch_mpv([Path("source.png")], Path("trial.conf"), 0)
                display.close.assert_called_once()
                self.assertIsNone(compare._headless_display)

    def test_paused_playback_is_rejected_as_temporal_warmup(self):
        with patch.object(compare, "_mpv_cmd", side_effect=[True, 0.0, 0.2]), \
             patch.object(compare.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, "did not advance"):
                compare._require_playback_advancing()
        with patch.object(compare, "_mpv_cmd", side_effect=[False, 0.2, 0.5]), \
             patch.object(compare.time, "sleep"):
            compare._require_playback_advancing()

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg is required")
    def test_lossless_loop_clip_preserves_source_rgb(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source.png"
            clip = Path(tmp) / "loop.mkv"
            pixels = np.arange(16 * 16 * 3, dtype=np.uint16).reshape(16, 16, 3)
            pixels = (pixels % 256).astype(np.uint8)
            Image.fromarray(pixels).save(source)
            compare._make_loop_clip(source, clip)
            decoded = subprocess.check_output([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(clip),
                "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
            ])
            self.assertTrue(np.array_equal(pixels, np.frombuffer(decoded, np.uint8).reshape(pixels.shape)))

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg is required")
    def test_transition_clip_switches_at_expected_times(self):
        with tempfile.TemporaryDirectory() as tmp:
            first = Path(tmp) / "first.png"
            second = Path(tmp) / "second.png"
            Image.fromarray(np.full((16, 16, 3), [255, 0, 0], np.uint8)).save(first)
            Image.fromarray(np.full((16, 16, 3), [0, 0, 255], np.uint8)).save(second)
            clip = compare._make_transition_clip(first, second, Path(tmp))
            for position, expected in ((18, [255, 0, 0]),
                                       (21, [0, 0, 255]), (29, [255, 0, 0])):
                frame = subprocess.check_output([
                    "ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", str(position),
                    "-i", str(clip), "-frames:v", "1", "-f", "rawvideo",
                    "-pix_fmt", "rgb24", "-",
                ])
                pixel = np.frombuffer(frame, np.uint8).reshape(16, 16, 3)[0, 0]
                self.assertEqual(pixel.tolist(), expected)

    def test_capture_requires_active_shader_marker(self):
        frame = np.zeros((8, 8, 3))
        with self.assertRaisesRegex(RuntimeError, "marker missing"):
            compare._require_activity_marker(frame)
        frame[:2, :2, 0] = 1
        compare._require_activity_marker(frame)

    def test_screenshots_cannot_be_decoded_as_telemetry(self):
        frame = np.zeros((4, 256, 3))
        for decoder in (capture.decode_scalars, capture.decode_luma_hist,
                        capture.decode_hue_hist):
            with self.assertRaisesRegex(RuntimeError, "offscreen"):
                decoder(frame)

    def test_optional_defaults_and_required_knobs(self):
        with tempfile.TemporaryDirectory() as tmp:
            profile = Path(tmp) / "creative_values.fx"
            original = "#define FILM_CURVE 0.65\n"
            profile.write_text(original)
            self.assertTrue(compare._ae_knobs_at_passthrough(profile, {"VIBRANCE": 0}))
            self.assertFalse(compare._ae_knobs_at_passthrough(profile, {"FILM_CURVE": 0}))
            with patch.object(compare, "_acquire_capture_lock"):
                compare._ae_write_knobs(profile, {"SAT_RED": 0})
                self.assertEqual(profile.read_text(), original)
                with self.assertRaises(SystemExit):
                    compare._ae_write_knobs(profile, {"MISSING_REQUIRED": 0})
                self.assertEqual(profile.read_text(), original)

    def test_fallback_guard_matches_shader(self):
        partial = "#define LUMA_CONTRAST_RED 0.0\n"
        self.assertIsNone(compare._optional_default(partial, "SAT_RED"))

    def test_ipc_error_is_not_silenced(self):
        reply = json.dumps({"request_id": 1, "error": "property unavailable"}) + "\n"
        connection = MagicMock()
        connection.makefile.return_value.__enter__.return_value = iter([reply])
        with patch.object(compare.socket, "socket") as socket:
            socket.return_value.__enter__.return_value = connection
            with self.assertRaisesRegex(RuntimeError, "property unavailable"):
                compare._mpv_cmd(["set_property", "playlist-pos", 1])

    def test_ipc_skips_events_and_checks_acknowledgement(self):
        replies = [json.dumps({"event": "file-loaded"}) + "\n",
                   json.dumps({"request_id": 1, "error": "success", "data": 1.25}) + "\n"]
        connection = MagicMock()
        connection.makefile.return_value.__enter__.return_value = iter(replies)
        with patch.object(compare.socket, "socket") as socket:
            socket.return_value.__enter__.return_value = connection
            self.assertEqual(compare._mpv_cmd(["get_property", "time-pos"]), 1.25)
            connection.sendall.assert_called_once()


if __name__ == "__main__":
    unittest.main()
