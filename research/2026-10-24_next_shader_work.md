# Earlier shader fidelity pass — historical plan

Superseded by the agreed [visual goal](../GOAL.md) and current ordered
[PLAN.md](../PLAN.md). The work order and pending-tooling statements below
record an earlier state. Matched headless motion and history readback now work;
the Retinex halo correction is adopted. Preserve this note as prior rationale,
not as the current task queue.

The user asked to do this in the next session. Here, **effect efficiency**
means a useful, controlled visual contribution for the intended scene, not
GPU speed. The user explicitly deprioritized GPU cost. Do not run more cost
profiling unless they change that priority.

## Starting point

- Read `AGENTS.md`, `HANDOFF.md`, this file, the [combined-chain resource
  finding](2026-10-23_cross_effect_resources.md), the [GZW audit
  continuation](2026-10-24_gzw_audit_continuation.md), and the [Babylon
  course report](2026-10-24_babylon_shader_course.md).
- Use `gamespecific/gzw/gzw_stronger_trial.conf` for GZW shader assessment.
  `gzw.conf` remains on the four-effect chain, whose separate render targets
  do not share the highway/zone resources. Do not switch or edit `gzw.conf`
  without an explicit user request.
- Preserve the working tree, including existing uncommitted analysis files
  and the staged deletion of `startprompt-2026-10-23.md`. Preserve user tuning
  in `gamespecific/gzw/shaders/creative_values.fx` and shader header comments.
  Shader logic may be corrected when a defect is demonstrated by matched
  captures. Shared shader changes also need Arc Raiders regression checks.
- Current automated course: [runner](../tools/babylon_scene/README.md).
  It produces 1440p held-pose baseline/trial/repeat screenshots with a
  20-second settle and confirms the moving route reaches cuts at frames 1440
  and 2160. It does not yet capture matched **moving** output frames.

## Work order

1. **Shadow separation first.** The Electric Dreams cross-game forest probe
   showed near-black growth from 0.003% source to 1.803% full output; turning
   off either contrast gate reduced output to 0.069%. This is a risk signal,
   not sufficient evidence to retune GZW. Use existing genuine GZW dark
   captures plus the Babylon night scene. Add a graded near-black ramp and
   textured low-light target to the synthetic scene if needed. Measure
   exact-black/near-black growth, local contrast, and retained separation.
   Isolate the relevant tonal stages and their interaction with settled
   matched captures. Fix shader logic only if an actual defect is reproduced.
2. **Assess every effect by purpose.** Run a full render, unchanged repeat,
   and one-at-a-time bypass on representative inputs. For small effects use
   `--settle 20` and a fresh process per image. Inspect: inverse grade for
   natural chroma reconstruction; corrective/zone/slow-key for stable scene
   estimates; Retinex and zone contrast for texture without edge halos;
   shadow lift for dark detail without gray blacks; FilmCurve for smooth
   highlight rolloff without clipping; chroma and gamut stages for vivid
   hues without shifts or hard boundaries; print stock for the intended look
   without damage to neutrals. Use source-selected regions and visual crops,
   not whole-frame ΔE alone. A near-zero bypass on an irrelevant scene does
   not prove an effect is useless, and a large ΔE does not prove fidelity.
3. **Automate matched motion evidence.** Extend the Babylon route runner to
   retain short baseline/trial sequences during forest movement, the colored
   corridor, and both hard cuts. Record actual frame identity or timing and
   reject mismatched pairs. Inspect moving-edge halos, flicker, history lag,
   cut recovery, and SDR endpoints. Keep this fully automated; the user
   should not have to steer or record. Raw game footage, if later supplied,
   can supplement this but should not block the synthetic checks.
4. **Change one demonstrated issue at a time.** Capture before/candidate/
   unchanged-repeat evidence, compile and render, check both dark and bright
   scenes plus saturated colors and cuts, and test Arc Raiders when shared
   shader logic changes. Keep user-facing tuning unchanged. Document observed
   improvements and any tradeoff with links to retained captures. Do not
   restore the removed golden-image suite.

## Existing evidence and limits

- The combined trial's genuine GZW sunset has active corrective, tonal,
  chroma and look stages. Its exact-black increase remains a concern; FilmCurve
  and inverse chroma barely engage there. An Arc cloud stress input engages
  FilmCurve, and a vivid Arc input engages inverse chroma under the GZW
  profile. These cross-game stress tests establish engagement, not GZW look
  quality.
- The prior static dark→sunset→dark test settled back to near-identical dark
  output by 18 seconds. That does not establish clean moving cut behavior.
- The Babylon baseline repeats were pixel identical for tested held poses;
  forest and revised night trial changes were ΔE 7.773 and 1.881. These are
  change magnitudes, not fidelity scores. The scripted route reached both cuts
  in baseline and trial, but output frames during movement were not matched.
- Browser FPS and prior mpv/MangoHud numbers do not isolate GPU cost. Cost is
  outside the requested work.

## Useful commands

```text
python3 -B tools/babylon_scene/run.py --motion-check
python3 -B -m unittest discover -s tests -p 'test_diagnostics.py'
```

See `tools/compare_frame.py --help` and `tools/README.md` for capture and
effect-attribution options. Always point GZW effect runs to
`gamespecific/gzw/gzw_stronger_trial.conf`, use `--settle 20` for small
effects, and include an unchanged repeat. Update `HANDOFF.md` with evidence;
it must remain under 60 lines.
