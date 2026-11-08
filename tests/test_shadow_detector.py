"""Offline tester contracts; no model download or visual reference images."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import shadow_detector

class ShadowDetectorTests(unittest.TestCase):
    def test_preprocessing_preserves_aspect_and_rgb_channels(self):
        image = Image.new('RGB', (200, 100), (255, 0, 0))
        tensor, size = shadow_detector.prepare(image, 64)
        self.assertEqual(size, (128, 64))
        self.assertEqual(tensor.shape, (3, 64, 128))
        self.assertGreater(tensor[0, 0, 0], 0)
        self.assertLess(tensor[1, 0, 0], 0)

    def test_probability_overlay_zero_is_identity(self):
        image = Image.new('RGB', (3, 2), (31, 47, 63))
        result = shadow_detector.overlay(image, np.zeros((2, 3), dtype=float))
        np.testing.assert_array_equal(np.asarray(result), np.asarray(image))

    def test_nonempty_output_refused_before_model_load(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            vendor, output = base / 'vendor', base / 'output'
            vendor.mkdir()
            (vendor / 'model.py').write_text('raise RuntimeError("must not load")')
            weights = base / 'weights.pth'
            weights.write_bytes(b'placeholder')
            output.mkdir()
            sentinel = output / 'keep.txt'
            sentinel.write_text('keep')
            result = subprocess.run([sys.executable, str(ROOT / 'tools/shadow_detector.py'),
                                     '--vendor', str(vendor), '--weights', str(weights), '--output', str(output)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('must be new or empty', result.stderr)
            self.assertEqual(sentinel.read_text(), 'keep')

if __name__ == '__main__':
    unittest.main()
