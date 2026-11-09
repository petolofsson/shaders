# Effect visibility: each knob off vs production (2026-11-09)

The user asked whether every effect is strong enough, after warmth proved
invisible and print too strong ([print/warmth report](2026-11-08_cool_chroma_print_strength.md)).
This is step 1: each nonzero `creative_values.fx` knob, and each stage gate, switched
off on its own against current production. Production here is print .5 and warmth ×3.5.

The script, profiles, stills, difference maps and gallery are in
`captures/effect_visibility_20261109/` (`review.html`, `report.json`).
- 54 private headless captures, 0 errors; identities stable before and after.
- Scenes: GZW 101035 (daylight sky), GZW 133058 (foliage/shade), Arc 210448 (dark
  with emitters).
- Noise floor (production repeat): mean |Δ| ≤ .07 codes, p99 ≤ 1.

## Results

Each cell gives mean |Δ| in codes and the share of pixels changed by more than 2
codes.

| Knob off | Daylight | Foliage | Arc dark | Effect when on |
| --- | --- | --- | --- | --- |
| Print / look gate | 4.5, 100% | 3.7, 99% | 3.3, 97% | Darkens about .014–.016 L |
| Corrective gate | 4.8, 100% | 1.5, 57% | 1.3, 25% | Darkens in daylight |
| Inverse luma | 4.0, 86% | 0.2, 4% | 0.4, 8% | Darkens in daylight |
| Endpoints (BLACKS/WHITES) | 0.8, 8% | 2.9, 60% | 4.2, 80% | Lifts the black floor |
| Shadow lift | 1.5, 33% | 6.0, 97% | 3.3, 80% | Brightens shade |
| Tonal gate | 1.7, 21% | 6.1, 97% | 3.3, 86% | Mostly lift |
| Contrast / Retinex / zone | 1.5–1.8, 16–26% | ~0 | ≤0.3 | Daylight only |
| Warmth (×3.5) | 1.4, 52% | 1.3, 60% | 0.8, 27% | Visible, global |
| Surround tint | 0.5, 11% (p99 11) | 0.6, 18% | 0.8, 18% | Local, in shade |
| Shadow temp/tint | ≤0.5, 0% | 0.2, 0% | 0.5, 0% | Below visibility |
| Chroma gate | 0.4, 3% | 0.4, 5% | 0.2, 2% | Near zero |
| Inverse chroma | 0.6, 0.3% | 0.0 | 0.1, 1% | Near zero (abstains) |
| FILM_CURVE | 0.07 | 0.00 | 0.07 | None (noise floor) |

## Findings

- **FILM_CURVE has no effect.** Print stock relieves its own shoulder in
  proportion to the film curve's highlight loss (`shared_relief` in
  `ApplyPrintStock`, from the 2026-10-31
  [highlight cooperation](2026-10-31_highlight_cooperation.md)). Switching the
  film curve off just hands the shoulder to print. The combined highlight roll-off
  is the same, so the knob is inert while print is on. This follows from the
  design; it is not a malfunction.
- **Shadow temp/tint is below visibility.** It uses the same `× 0.06` scale as
  warmth did before it was raised: GZW −.05/−.010 gives at most .003 Oklab.
- **The chroma stage is near zero.** It runs with `SATURATION` 0 and the adaptive
  vibrance only.
- **Inverse chroma is near zero.** This is intended restraint: it preserves
  incoming chroma and abstains above budget (2026-10-31).
- **Daylight-only effects:** contrast, Retinex and zone shaping act in the daylight
  scene and are essentially off in the dim scenes. Inverse luma and the corrective
  gate also act mainly in daylight. This conditional behaviour is by design.
- **Dark-scene effects:** shadow lift and BLACKS dominate the dark scenes.
- **Largest global effect:** print is still the largest effect present in every
  scene, even at .5.

## Step 2 candidates

These are for strength sweeps or a user decision:
- **Shadow temp/tint:** raise it like warmth, or leave it.
- **Chroma stage (`SATURATION`):** sweep it if more colour is wanted.
- **FILM_CURVE:** leave it inert, or make it independent of print. That would be
  a shader change, not a knob change.

Leave as conditional: inverse chroma, and contrast/Retinex/zone.

Limits: three stills, single frames, no motion. Each knob was switched off on its
own, so interactions such as film/print are measured only as they are currently
coupled.

## Step 2: shadow CC and saturation sweeps

Files are in `captures/effect_sweep_20261109/` (`review.html`). The sweep used
current production as the base, three scenes, 21 private headless captures, 0
errors, with identities stable. Production repeats: p99 ≤2 codes and 0% of pixels
>2 codes (daylight mean .52). In the table, "shade Δb" is the mean Oklab b shift
for pixels with L < .45.

| Variant | Daylight mean \|Δ\| | Foliage | Arc dark | Shade Δb |
| --- | --- | --- | --- | --- |
| Shadow CC ×3 | .69 | .36 | 1.04 | −.001 to −.005 |
| Shadow CC ×6 | 1.92 | .88 | 2.51 | −.003 to −.013 |
| SATURATION .1 | .91 | .68 | .53 | ΔC +.002 to +.003 |
| SATURATION .2 | 1.87 | 1.37 | 1.03 | ΔC +.003 to +.005 |
| SATURATION .3 | 2.81 | 2.09 | 1.51 | ΔC +.005 to +.008 |

The user chose `SATURATION` .15 and shadow CC ×4 for both profiles:
- GZW: temp −.20 / tint −.04.
- Arc: temp −.30. Arc had no `SATURATION` line, so one was added under CHROMA.

A post-change production capture compiled with 0 errors in both games. Compared
with the previous production:
- mean |Δ| was about 2.0 codes (p99 9–10);
- ΔC was +.003 to +.005;
- shade Δb was −.005 to −.008;
- no pure-black or pure-white pixels were added.

The exact values were not swept, but they lie between captured points. Watch for
the yellow/orange over-saturation in warm scenes (saturation stacks with warmth
×3.5), and for minty GZW shadows from the tint.

**Later the same day,** the user reduced both: `SATURATION` .075 and shadow CC
×3 (GZW −.15/−.030, Arc −.225). ×3 lies at a captured sweep point; .075 lies
below the captured .1 point. No post-change capture was taken.
