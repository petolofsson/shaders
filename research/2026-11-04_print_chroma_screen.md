# Weak-color print chroma screen — 2026-11-04

**Decision: do not adopt the isolated candidate.** Modest selected wall/window gains come with mixed daylight material changes. This is an early appearance screen, not a validated replacement or a comprehensive search.

Current-profile, full-minus-effect captures attribute the selected weak-color response mainly to print and grade chroma: removing grade chroma reduces the source-b-quartile Oklab ab gap from 1.28619 to 1.18836 on GZW blue wall and 2.61515 to 2.39058 on Arc cool window; removing print raises it to 1.45282 and 3.09366. Inverse chroma bypass gives 1.28619 and 2.61456. These are separation measures, not quality scores; print bypass also changes density. Full repeats match in these selected measurements. Captures are in the November 4 `full_analysis` directories.

The current ratio path scales absolute Oklab chroma down with print density. An isolated candidate tried restoring input absolute chroma in weak, lower-tone pixels, normalizing linear RGB to print luminance before the existing saturate. The current smooth weak-chroma and brightness gates limit it. This is not a guaranteed luminance contract after saturation, and was not adopted.

| Fixed selection | Current | Candidate |
|---|---:|---:|
| GZW blue wall | 1.28619 | 1.31549 |
| Arc cool window | 2.61515 | 2.64031 |
| Arc warm floor | 5.14254 | 5.12186 |
| GZW shadow paving | 1.96868 | 2.03427 |
| GZW lit paving | 2.72027 | 2.64736 |
| GZW foliage | 1.90091 | 1.88023 |
| GZW cloud | 6.46782 | 6.33854 |

These are fixed source-b-quartile ab separations, not an assessment of visual quality. Selected vivid blue field rose 5.78372 to 5.81448; red-lamp separation was unchanged at displayed precision. The target candidate pairs repeat pixel-exactly, and all seven candidate/control GPU processes reported zero dropped/delayed frames. Other control captures have no candidate repeats. Fresh attribution full/repeat captures were used for the two targets; controls compare against the previous adopted-CC captures. The baseline source/profile/config/include and normalized grade identities require verification before treating the control comparisons as definitive. Gamescope logs report PipeWire and shutdown errors. Twenty-second settling is not proof of convergence.

The candidate did not receive numerical GPU contracts, zero controls, charts, temporal checks or actual-config adoption validation. It preserves production shader and profiles. Its modest gains and mixed controls do not justify adoption or an automatic parameter sweep. Local scripts, captures and isolated shader copies are in `captures/print_chroma_20261104/`.
