# Scene-hue direction ablation — 2026-11-04

**Result: direction bias has a modest measurable effect in the selected vivid scene; a centroid-confidence improvement is not established or adopted.** This is an early ablation, not a confidence candidate or GPU centroid probe.

The current inverse reconstructs chroma with `dir_scale = 1 - 0.15 * alignment` even if the scene chroma centroid is nearly zero. The isolated diagnostic changes only that multiplier to 1.0, removing the complete directional contribution regardless of scene confidence. It leaves the other inverse and grade calculations intact. This tests the influence of the existing bias, not whether any scene's centroid actually lacks confidence. A confidence gate might produce smaller changes, but output nonlinearities and quantization prevent treating the image difference as a strict mathematical upper bound.

Current GZW profile differs from the November 3 adoption baseline: FILM_CURVE=0.70, SHADOW_TEMP=-0.05, SHADOW_TINT=-0.010, MID_TEMP=0.05. These external values were preserved. Fresh full and repeat baselines for GZW vivid and daylight were captured with this current profile and current shader. The Arc emitter comparison uses the November 3 candidate baseline after verifying current production hashes against its adoption verification; only the GZW profile differs. Source hashes and isolated capture config files were checked. All five candidate and GZW baseline pairs are exact after masking the 2x2 marker; the Arc original adoption pair was recorded exact. All ten fresh GPU processes reported zero drops/delays.

| Selection, source-b quartile Oklab ab gap | Current | Direction-neutral diagnostic |
|---|---:|---:|
| GZW vivid blue sky | 3.26911 | 3.33373 |
| GZW vivid blue field | 5.83078 | 5.97221 |
| GZW daylight foliage | 1.88405 | 1.88533 |
| GZW daylight cloud | 6.33854 | 6.33854 |
| Arc red lamp | 3.26621 | 3.27925 |

These selected color-separation statistics are not fidelity scores; changing them does not prove better appearance. Across the whole image, candidate changes reach two codes in vivid and daylight and two in Arc emitter. In vivid, 433,887 pixels change, with 770 differing by more than one code; daylight has 21,032 and 508 respectively, and Arc has 40,150 and 1,318. Counts mask the 2x2 marker. The low number of >1-code changes and native appearance require careful interpretation; no subjective improvement, hue-quality, temporal or numerical confidence contract is claimed.

Artifact limitation: the fresh baseline generator accidentally reused the `inverse_neutral.fx` filename after the diagnostic processes had completed, overwriting the diagnostic copy. Its generator, isolated pipeline/config files and logs are retained. Reconstructed baseline and diagnostic shader snapshots are separately saved as `inverse_baseline_snapshot.fx` and `inverse_diagnostic_snapshot.fx`; the external inverse file was not included in the capture helper's file-hash manifest at capture time. The affected original capture records therefore do not independently prove the executed inverse file identity. This limits the ablation evidence and should be corrected by a fresh properly hashed repeat before any adoption decision. No result was relabeled.

No production changes, ratings or mandatory parameter sweep follow. To establish the lead, use a properly hashed current-code capture with explicit GPU readback of both centroid magnitude and direction on balanced opposing-color fixtures and relevant game scenes, then compare a bounded confidence candidate and repeats. If uncertain centroid states do not occur or the difference has no useful visual effect, stop. Local artifacts are in `captures/hue_confidence_20261104/`.

## Hashed vivid confirmation

Four further fresh captures use distinct frozen baseline/diagnostic inverse snapshots whose hashes are recorded before and after each capture in `verified.json`. Both new pairs are pixel-exact; the new baseline matches the earlier fresh baseline exactly and the new diagnostic matches the earlier diagnostic exactly. All four report zero drops/delays. This independently confirms the vivid comparison despite the retained original artifact gap. It does not validate the other two ablations' external inverse provenance or establish the centroid magnitude, color quality, temporal behavior or a production candidate.
