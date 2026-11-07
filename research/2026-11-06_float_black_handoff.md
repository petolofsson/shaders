# High-precision black handoff check

The [same-update float-pair diagnostic](2026-11-06_shadow_float_pairs.md) now samples the black field of the existing black/white/gray fixture through both unchanged profiles. In this fixture, post-inverse grade input is zero at the diagnostic's encoded resolution, while the pre-dither grade output is a small, profile-dependent colored value. This supports the proposed zero-input gate for this specific black context; it does not prove source-black behavior in every scene, execute the candidate on the GPU, or establish output identity after dither.

The source fixture and clip are the hash-verified originals from the [late-offset screen](2026-11-05_late_black_offset.md), containing a broad source-black field, white field and code-64 gray field. Each 16×16 grid samples black at native pixel centers within `(256,400)–(320,464)`, well away from the field boundaries. The private headless diagnostic samples post-inverse grade input and the pre-dither production-grade clone in the same GPU invocation, retaining its [0,0.25] encoding range and approximately 1.49e-8 nominal readback step. It is a clone, not the actual normal output write. Four new processes—two independent still runs per profile—report zero dropped/delayed frames; each profile's pair is identical at encoded resolution. Static settling and repeats do not establish convergence or moving-scene behavior. Production/profile/config identities and all capture hashes are in `captures/shadow_float_pairs_20261106/report_black.json`.

| Profile | Post-inverse grade-input RGB range | Pre-dither clone RGB median |
| --- | --- | --- |
| GZW | all sampled channels encode as 0 | [0.00158972, 0.00171539, 0.00191812] |
| Arc | all sampled channels encode as 0 | [0.00159465, 0.00170501, 0.00203495] |

Each sampled field is uniform at encoded precision. The input encoding clamps negative values to zero and is finite resolution; the BackBuffer is UNORM and the decoded zero should not be described as an independent proof of exact internal float bit patterns. The nonzero, slightly colored result reflects the current chain and the fixture's scene/adaptive context. It is not a request to change BLACKS or neutralize that result.

For the research model's `smoothstep(0.0005,0.003,grade_input_Y)` gate, zero input gives zero correction in CPU algebra for both its color and brightness components. This test therefore supports the condition needed to preserve this fixture's black when the unchanged model is eventually implemented, but does not prove the candidate's GPU math, the complete color/gamut path, its interaction with dither, or arbitrary neighboring scene contexts. Both profiles, production shaders/configs, histories and ratings remain unchanged.
