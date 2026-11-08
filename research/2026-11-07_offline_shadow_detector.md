# Offline shadow detector tester

The user requested an offline tester before deciding on any runtime approach.
[`tools/shadow_detector.py`](../tools/shadow_detector.py) runs the published
[BDRAR shadow detector](https://github.com/zijundeng/BDRAR) locally on CPU and
produces probability maps, 0.5 threshold previews and red overlays. It does not
modify images used by the game, use a GPU/display, infer material color, or
introduce an effect into the shader. The current five-image gallery is
`captures/shadow_detector_bdrar_20261107/final_review/review.html`.

## Provenance and inference

The authors' source was cloned into ignored local research storage at commit
`37deea38e818b6579e7dfd1071b97556a7545c56`; their published full BDRAR
checkpoint is `captures/shadow_detector_bdrar_20261107/model.pth`, SHA-256
`53b0b3a0e089424ba3bf5170eee6772f57b0aabdae86d369d923727a6e212fea`.
The initial Google Drive download returned an HTML large-file warning, retained
as `download_warning.html`; the subsequent checkpoint is the 162.6 MiB file,
loaded with `weights_only=True`. Strict state-dict loading reports all keys
matched. The original Python 2 package imports were made relative, and the
separate backbone checkpoint load removed because the complete BDRAR checkpoint
is loaded afterward. The checked-out vendor diff records those two changes.

An ignored Python 3.14 virtual environment with access to system packages has
CPU-only PyTorch 2.15.0+cpu; inference explicitly uses `.cpu()`. The tester
uses the original inference's short-side 416 resize and ImageNet RGB
normalization, then saves the raw sigmoid as a float32 array resized to input
resolution with bilinear interpolation. Unlike the authors' original script,
this review uses no CRF, no per-image normalization, and resizes float
probabilities rather than an 8-bit PIL image. These choices are recorded, not
claimed equivalent to published benchmark results. The mask is a model score,
not a calibrated physical probability, and .5 is only a displayed reference.

Each `report.json` records input/output hashes, source and inference dimensions,
checkpoint and source-code hashes, tester hash and model environment. The
tester requires a new/empty output directory and never downloads anything.
The initial smoke and final batch daylight floating arrays match exactly; all
five final images and saved artifacts pass hash checks. Three focused tester
contracts exercise aspect/channel preprocessing, the zero overlay and refusal
to overwrite a nonempty directory. This is not golden-image regression.

## Preliminary observations

In the GZW daylight image the model highlights much of the shadowed paving, but
also marks portions of the weapon, foliage and other dark surfaces. In the GZW
shelf scene it extends across much of the wall and weapon. In the warm interior
and Arc colored-light view it marks broad regions, including much of the dark
scene. These are observer descriptions of one model's photographic-domain
outputs, not annotated false-positive rates or proof that every marked surface
is non-shadow. Its resized masks have soft spatial boundaries. The gallery lets
the user judge where its definition matches the intended look.

The model is a still-image offline reference, not a selected game-time shadow
detector. No cross-game validity, temporal stability, latency or real-time
performance follows, and a mask does not reveal hidden material color. The
upstream checkout is local and ignored; no model files are being published.
The tester requires its supplied, inspected vendor checkout and checkpoint to
remain present; it deliberately does not silently fetch code or weights.
