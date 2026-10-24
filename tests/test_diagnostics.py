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


class CaptureTests(unittest.TestCase):
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
