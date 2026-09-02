# Changelog

Chronological record of recent code changes. Older detail lives in git history and
research notes.

## 2026-09-02

- **Stable minimal checkpoint**: Arc Raiders now exposes only the core tonal controls;
  removed game-specific hue, saturation, shadow-cast, and perceptual color design knobs.
  The reduced chain passed a one-frame vkBasalt compile/render check.
- **Root docs renamed/trimmed**: `CLAUDE.md` renamed to `AGENTS.md`; root docs
  compressed to operational state, current risks, and validation commands.
- **Pipeline correctness**: fixed diffusion zero bypass, exact-white histogram
  binning, and exposure order. The 2x2 red activity marker is intentionally restored.
- **Quality pass**: scene cuts now use p50 plus raw histogram entropy delta;
  guided-filter epsilon is local-variance adaptive.
- **Pipeline reduction**: removed halation, clarity, negative matrix, chromatic
  induction, Bezold-Bruecke, Abney, H-K, HELMLAB, gamut-density darkening, and
  bleach bypass. Rebuilt game profiles around the remaining controls.
- **Testing tools**: `compare_frame --all-effects` no longer references removed
  DIR/toe knobs and fails on missing knobs; added `tools/noise_floor.py`.
- **Validation**: one-frame runtime `compare_frame --all-effects --only FILM_CURVE`
  passed with FilmCurve contribution `DeltaE 32.94`; `bless_all --check` fails 4/4
  against old `dcc712f` goldens, pending visual review/rebless.

## 2026-05-20

- **R205 FilmCurve**: removed display-referred rational toe, reparameterized body
  lift to track `fc_knee`, removed redundant `fc_w`, added WHITES taper, and removed
  `CURVE_R/B_TOE` knobs.
- **BLACKS/WHITES**: replaced separate clips with one linear remap at the top of
  `ColorTransformPS`.
- **Print stock fixes**: gated masking coupler and dye matrix by `PRINT_STOCK`;
  fixed `ApplyPrintStock` midtone desaturation from shadow-only to bell-shaped.

## 2026-05-18

- **3-way CC**: rewritten in Oklab a/b axes; temp and tint are orthogonal and need
  recalibration per profile.
- **Bleach bypass**: moved before print stock and converted to linear-luma
  retained-silver modeling.
- **Temporal dither**: switched from broken `framecount` to `FRAME_TIMER`.
- **Cleanup**: removed unused HSV helper and stale analysis scope/low-frequency docs.

## 2026-05-17

- **INVERSE_LUMA**: replaced flat ACES luma inverse with Mertens bell weighting.
- **Halation**: changed to luma-neutral orange tint with sky suppression.
- **CLARITY**: implemented documented upper highlight rolloff.
- **DIR_COUPLER**: removed user knob; shader uses hardcoded designed strength.
