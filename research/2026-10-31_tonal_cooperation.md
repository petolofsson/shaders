# Combined tonal correction screen — 2026-10-31

**Reject both cumulative-gain candidates. This finite screen is closed without
production shader changes or an effectiveness score increase.**

The user authorized the recommended tonal-cooperation work. This experiment
asks whether limiting the combined Retinex, zone and shadow-lift correction
preserves useful material distinctions. It tests a new combined correction
mechanism rather than reopening the earlier lift-redistribution parameter screen.

## Inputs and mechanism

GZW `INVERSE_LUMA` was externally changed from 0.30 to **0.60** after the previous
validation. That edit is preserved. All three GZW sources receive fresh current-
profile baseline/repeat captures. Arc profile/shaders match the prior validated
state; its two baseline pairs are reused after source, profile, helper and shader
identity checks. Earlier GZW outputs at 0.30 are not current baselines.

Five source scenes cover GZW daylight paving, the dark shelf, shop wood/floor,
Arc interior metal/floor/window and Arc vehicle/road/cloud. Profiles/configs and
all existing working changes remain intact. The current baseline contains the
adopted print and inverse-chroma preservation work.

Immediately after shadow lift, each isolated candidate replaces the combined
Retinex/zone/lift luminance ratio with a smooth bounded log correction:

```text
x = log2(post_tonal_Y / pre_Retinex_Y)
bounded_x = x / sqrt(1 + (x / limit)^2)
post_tonal_Y = pre_Retinex_Y * exp2(bounded_x)
```

The limits are 0.5 stops (`guard`) and 1.0 stop (`gentle`). Small corrections
are retained more closely than large ones. The input reference is after
corrective grading; inverse luma, exposure and CC are not undone. Subsequent
chroma, ambient, film and print responses remain live. This is a final-output
intervention with downstream interactions, not an additive attribution budget.
No new user control, history, analysis surface, rate or pass is introduced.

A fixed-context CPU check over -16 to +16 stops confirms the standalone maps
are monotone, bounded and identity at zero correction. It does not prove
monotonicity or appearance of the spatial/adaptive pipeline. GPU numerical and
motion adoption tests are unnecessary after rejecting the held-image result.

## Observed result

Visible gaps use fixed source-L quartile groups in source-selected regions;
L is Oklab ×100. Larger gaps are not automatically better. The paired native
crops and relative linear-light gaps also inform the decision.

| Material | Current | 0.5-stop guard | 1-stop gentle |
|---|---:|---:|---:|
| GZW shadow paving | 10.3080 | 10.3157 | 10.3089 |
| GZW lit paving | 17.2611 | 17.3069 | 17.2745 |
| GZW shelf | 4.3885 | 4.3240 | 4.3679 |
| GZW wood | 10.4394 | 10.2410 | 10.3771 |
| GZW floor | 12.6361 | 12.6447 | 12.6457 |
| Arc dark metal | 7.7514 | 7.7304 | 7.7447 |
| Arc warm floor | 32.4025 | 32.4624 | 32.4182 |
| Arc cool window | 30.5880 | 30.7553 | 30.6374 |

The stronger guard gives only about 0.27% more lit-paving separation, while
losing about 1.47% shelf and 1.90% wood separation. Cool-window improvement is
about 0.55%. The gentler version reduces both gains and costs; wood still loses
about 0.60%. These small mixed changes do not establish the significant,
repeatable material benefit sought by the user.

For the shelf, relative separation rises 1.6432→1.6482 stops under the stronger
guard while visible separation falls. Wood loses both visible and relative
separation (1.7748→1.7691 stops). Native review shows subtle changes rather than
substantially clearer materials. Current numeric region/end-point results,
including vehicle/road/cloud, are retained in `metrics.json`.

## Validation, decision and limits

Sixteen fresh private/headless captures complete with zero dropped/delayed
frames. Four verified prior Arc captures supply the two baseline pairs, giving
20 ordinary outputs. All five baseline/repeat pairs are pixel-identical.
Candidates have one observation per scene: no candidate-repeat or temporal
stability claim is made. Fresh processes use five seconds of compile wait and
twenty seconds of continuous settling. This is a fixed protocol, not a universal
history-convergence proof. Activity markers are checked and masked in metrics.
Source, media, isolated configuration and output hashes are audited, together
with protected production shaders/profiles/configs. No golden fixture is added.

The evidence rejects these two combined-gain limits as defaults. It does not
show that tonal cooperation is impossible or that a new effect would help.
A plausible explanation is that net correction magnitude is a poor proxy for
material compression: neighboring shades can move closer together even when
individual net corrections are small. That explanation is an inference, not a
measured decomposition of every stage's local response.

Any further tonal-cooperation experiment should begin with a concrete measured
loss of neighboring shade response, rather than extending this gain-limit
parameter screen. No new mandatory repair or candidate is queued. Production
shaders, profiles, configs, histories/rates, headers and passes are preserved.
GZW inverse luma remains the externally selected 0.60. No new full-chain or
per-effect rating is awarded; the earlier GZW 0.30 rating evidence remains
explicitly scoped. No commit or push is made.

Local artifacts: `captures/tonal_cooperation_20261031/` contains immutable code/
profile copies, `report.json`, `metrics.json`, scalar results, native crop strips
and `audit.json`. Scripts and media remain ignored.
