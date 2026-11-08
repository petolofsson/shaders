"""Oracle-test contracts: helper arithmetic and output safety; no rendering."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import shadow_oracle as so

class ShadowOracleTests(unittest.TestCase):
    def test_current_helper_matches_shader_formula(self):
        rgb = np.array([[[0.012, 0.006, 0.004]]])
        y = float(rgb[0, 0] @ so.LUMA)
        gate = so.smooth(0.00025, 0.0025, y) * (1 - so.smooth(0.01, 0.04, y))
        expected = rgb * (so.WHITES - so.BLACKS) + so.BLACKS + 1.10 * so.OFFSET * gate * (rgb / y - 1)
        out, _ = so.variants(rgb, np.full_like(rgb, 0.3), np.zeros(rgb.shape[:2]), 1.0)
        np.testing.assert_allclose(out['current'], expected, rtol=1e-12)

    def test_oracles_inactive_when_lit_and_current_inactive_when_bright(self):
        rgb = np.array([[[0.5, 0.3, 0.2]]])
        base = rgb * (so.WHITES - so.BLACKS) + so.BLACKS
        out, _ = so.variants(rgb, np.array([[[0.6, 0.3, 0.2]]]), np.zeros((1, 1)), 2.0)
        for name in out:
            np.testing.assert_allclose(out[name], base, rtol=1e-12)

    def test_headroom_budget_caps_channels_at_one(self):
        lin = np.array([[0.9, 0.5, 0.1]])
        out = so.apply_delta(lin, np.array([[0.4, 0.0, -0.05]]))
        self.assertLessEqual(out.max(), 1.0 + 1e-12)
        np.testing.assert_allclose(out, [[1.0, 0.5, 0.1 - 0.05 * 0.25]])

    def test_nonempty_output_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            keep = Path(tmp) / 'keep.txt'
            keep.write_text('keep')
            r = subprocess.run([sys.executable, '-B', str(ROOT / 'tools/shadow_oracle.py'), '--output', tmp],
                               capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn('new or empty', r.stderr)
            self.assertEqual(keep.read_text(), 'keep')

if __name__ == '__main__':
    unittest.main()
