# Changelog

Adopted changes only. Dated reports retain validation, rejected variants and
tradeoffs; their profile values describe their own evidence epochs. Current
profiles and scores are in [HANDOFF.md](HANDOFF.md). The former detailed ledger
is preserved in [research](research/2026-11-06_root_document_history.md).

## 2026-11-08 — Shadow surround tint

Adopted the [shadow surround tint](research/2026-11-08_shadow_tint_candidate.md):
shaded areas take a slight tint of the surrounding surface colour. It uses one
equal-perceived Oklch+ step and a Helmholtz–Kohlrausch darkening, computed on
the regional colour so pixel noise is not amplified. The darkening fades out near
emitters and on lit spots. Five low-resolution grade passes were added. The new
`SHADOW_SURROUND_TINT` control is set to 1.0 in both profiles. Known limitation:
dark background behind bright foreground objects can receive a tinted halo
(colour-only; depth is unavailable).

## 2026-11-08 — Review fixes

Applied all six findings of the [full-shader review](research/2026-11-08_ultrareview_fixes.md):
bounded the R60 shadow-lift context ratio, removed the unreachable fallback lift and
unused per-hue chroma Kalman, gave each optional color control its own default,
shared one clamped spatial-lane read, and retired the standalone inverse-grade debug
overlay that could not read the combined pipeline's highway.

## 2026-11-06 — Documentation

Shortened root guides, separated rules/priorities/state, moved technical contracts
to [the pipeline reference](docs/pipeline.md), and archived duplicated history.
No production change. November 4–6 shadow experiments remain unadopted.

## 2026-11-03

Adopted [shared-component CC](research/2026-11-03_neutral_component_cc_adoption.md):
retain gray correction while reducing colored-material hue steering.

## 2026-11-02

Adopted [one guarded tonal base](research/2026-11-02_tonal_architecture.md) for
Retinex, zone shaping and lift, retaining corrected-pixel detail and source-range
protection. The [requested review](research/2026-11-02_effect_ratings.md) estimates
chain/grade 78 and joint tonal behavior 80, provisionally.

## 2026-11-01

The user set BLACKS=.0025 in both profiles. The
[Arc trial](research/2026-11-01_arc_black_trial.md) supports its Arc scope;
post-edit actual-config verification completed November 2.

## 2026-10-29–31

- [Weak-material color preservation](research/2026-10-31_weak_material_colors.md):
  protect subtle lower-tone print colors while retaining bright palette behavior.
- [Highlight cooperation](research/2026-10-31_highlight_cooperation.md): relieve
  overlapping FilmCurve/print shoulders while retaining the print toe.
- [Print/inverse color preservation](research/2026-10-31_print_inverse_color_preservation.md):
  preserve print color ratios above deep shadows; bound added inverse chroma
  with per-pixel SDR headroom.
- [Inverse chroma restraint](research/2026-10-31_inverse_chroma.md): preserve
  incoming chroma and abstain above the reconstruction budget.
- [Three-way CC profile tuning](research/2026-10-31_three_way_cc.md): user-authorized
  half-strength shadow correction; later external GZW choices supersede its values.
- [Gentler print shoulder](research/2026-10-30_print_look_preservation.md).
- [Guarded inverse shadow reconstruction](research/2026-10-29_shadow_stage_preservation.md).

## 2026-10-28 — v1.0

Stable combined SDR checkpoint, `1724bb6`. Later changes are listed above.

## 2026-10-24–27 — Technical foundation

- [Retinex material preservation](research/2026-10-27_retinex_material_preservation.md)
  and [source-aware inverse restraint](research/2026-10-27_tonal_selectivity.md).
- [Current-source lift and combined-chain activation](research/2026-10-27_lift_transition_repair.md),
  following [cut-gate recovery](research/2026-10-27_gate_recovery.md).
- [Integer-dimension filter spacing](research/2026-10-27_filter_kernel_resolution.md)
  and [continuous blue-cusp projection](research/2026-10-27_gamut_continuity_repair.md).
- [Original-source Retinex guide](research/2026-10-26_retinex_sky.md),
  [zone scene pivot/black tail](research/2026-10-26_zone_scene_pivot.md), and strict
  [render-phase matching](research/2026-10-26_return_cut_alignment.md).
- [Statistics/gamut contracts](research/2026-10-25_signal_contracts.md),
  [live-history precision](research/2026-10-25_remaining_histories.md),
  [slow-key precision](research/2026-10-25_slow_key_precision.md), metadata,
  percentile initialization and median-chroma corrections.
- Retinex halo, zone precision and shadow-tail repairs. Earlier sRGB, signed
  Oklab, reconstruction, dither and adaptation work is recorded in the
  [implementation report](research/2026-10-23_fidelity_implementation.md).
  Diffusion, temporal grain and golden-image testing were removed.
