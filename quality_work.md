# Quality Work

Date: 2026-09-02

Pipeline/test changes, not tuning changes.

## Implemented

- `analysis_frame.fx`: `SceneCutPS` combines p50 delta with raw histogram entropy
  delta, catching cuts with similar median luminance but different tonal distribution.
- `grade.fx`: guided-filter epsilon depends on local log-luma variance. Flat
  windows get stronger damping; structured windows preserve more detail.
- `tools/compare_frame.py`: effect isolation no longer includes removed DIR/toe
  knobs, disables the active `FILM_CURVE` gate for FilmCurve tests, and fails on
  missing knob names.
- `tools/noise_floor.py`: added EXR high-frequency measurement for one frame or
  `after-before` pairs.

## Verified Without Change

- `LFDownscale1PS` uses `4 / BUFFER_WIDTH` horizontally and `0.5 / TEX_HWY_TOTAL_H`
  vertically. That is symmetric in the packed source texture: the spatial lane is
  `BUFFER_WIDTH/8` wide and embedded inside full `TexHwyTex` height.

## Test Results

Static/local checks passed:

```text
python3 -m py_compile tools/compare_frame.py tools/noise_floor.py tools/analyze_delta.py tools/test_golden.py
git diff --check
rg -n "DIR_COUPLER|CURVE_[RB]_TOE|#define GF_EPS\b|0\.10 \+ eff_diff" general gamespecific/*/shaders tools
```

Runtime check passed:

```text
python3 tools/compare_frame.py --all-effects --game arc_raiders --max-frames 1 --only FILM_CURVE --delay 5
```

Output: `gamespecific/arc_raiders/full_analysis/effects_2026-09-02_192729.json`.
FilmCurve contribution on that frame: `DeltaE 1.12`.

Golden check failed 4/4 versus old `dcc712f` baselines:

| Image | MAE |
|-------|-----|
| gradient | 0.22923 |
| colorchecker | 0.27139 |
| highlights | 0.21470 |
| skintones | 0.34145 |

Interpretation: current output has broad tonal/chroma drift from old goldens.
Review visually before reblessing.

Noise-floor sanity passed:

```text
python3 tools/noise_floor.py tests/golden/gradient.exr gamespecific/test/captures/session_20260902_192851_test.exr
```

Luma highpass RMS: `0.04911286`. This comparison is dominated by pipeline drift,
so it is not a clean dither/grain isolation measurement.

## Remaining

- Decide Arc Raiders `LOOK_STRENGTH 000`.
- Run full all-effects attribution after that decision.
- Mask or ignore the intentional 2x2 red activity marker in strict image tests.
