"""Brightness-oracle contracts: curve anchors and output ceiling; no rendering."""
import sys
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import brightness_oracle as bo

class BrightnessOracleTests(unittest.TestCase):
    def test_curve_keeps_lit_levels_and_black(self):
        self.assertAlmostEqual(float(bo.gain_stops(np.array(0.5))), 0.0)
        out = bo.apply_gain(np.zeros((1, 3)), bo.gain_stops(np.zeros(1)))
        np.testing.assert_array_equal(out, 0.0)

    def test_curve_lifts_partial_band_and_deepens_deepest(self):
        self.assertAlmostEqual(float(bo.gain_stops(np.array(0.03))), bo.LIFT_STOPS)
        self.assertAlmostEqual(float(bo.gain_stops(np.array(0.001))), -bo.DEEPEN_STOPS)

    def test_ceiling_preserves_channel_ratios(self):
        lin = np.array([[0.9, 0.45, 0.09]])
        out = bo.apply_gain(lin, np.array([1.0]))
        self.assertAlmostEqual(float(out.max()), 1.0)
        np.testing.assert_allclose(out / out.max(), lin / lin.max())

    def test_production_base_flat_and_hard_edge(self):
        flat = np.full((40, 40), -3.0)
        np.testing.assert_allclose(bo.production_base_log(flat), flat)
        edge = np.where(np.arange(64)[None, :] < 32, -6.0, -2.0).repeat(64, 0)  # 4-stop step
        np.testing.assert_allclose(bo.production_base_log(edge), edge)       # range weight blocks mixing

    def test_production_base_smooths_small_texture(self):
        rng = np.random.default_rng(0)
        tex = -3.0 + 0.1 * rng.standard_normal((64, 64))
        base = bo.production_base_log(tex)
        self.assertLess(base[16:48, 16:48].std(), tex[16:48, 16:48].std() * 0.5)

if __name__ == '__main__':
    unittest.main()
