# Shadow detection: online research and practical fit

The user reports no visible difference between the previous color candidate and
the [local-context candidate](2026-11-07_shadow_context_review.md). Treat that
as a negative visual result; its signal responded on several kinds of surfaces
and the daylight still repeats varied. It is not a supported route to adoption.
The user asked for online shadow-identification techniques. No production
shader, profile or config changed in this research.

## Relevant approaches

1. **Paired surface regions.** [Guo, Dai and Hoiem, CVPR 2011](https://dhoiem.web.engr.illinois.edu/publications/cvpr11_shadow.pdf)
   compares regions likely to share material and orientation, combines region
   appearance and pairwise relationships, and uses graph inference. This is
   substantially more than the eight nearby RGB taps in our rejected context
   prototype. [Xiao et al., BMVC 2021](https://www.bmvc2021-virtualconference.com/assets/papers/0374.pdf)
   use region growing, candidate penumbrae and physical color relationships.
   Their paper notes failure when no corresponding lit region is visible or
   unrelated regions accidentally satisfy the matching conditions. Its fixed
   outdoor color-temperature assumptions are not guaranteed for game lighting.
   Neither paper establishes a bounded-pass implementation in this repository.
2. **Shadow-edge and illumination reasoning.** [Lynch et al., ICCV Workshop 2013](https://www.cv-foundation.org/openaccess/content_iccv_workshops_2013/W25/html/Lynch_Colour_Constancy_from_2013_ICCV_paper.html)
   use an illumination edge to reason about the same surface under different
   light colors. The paper specifically discusses different sunlight and shadow
   illuminants. An edge is evidence, not a complete mask: contact shadows,
   soft transitions, dark objects and colored lighting remain challenges. These
   papers often aim to remove shadows; this project's goal keeps shadow luminance
   and lighting character, so removal output is not the desired result.
3. **Learned masks.** [STICT, CVPR 2022](https://openaccess.thecvf.com/content/CVPR2022/html/Lu_Video_Shadow_Detection_via_Spatio-Temporal_Interpolation_Consistency_Training_CVPR_2022_paper.html)
   addresses video shadow masks and temporal consistency rather than treating
   independent frame predictions as stable. [DTTNet, AAAI 2026](https://arxiv.org/abs/2511.06925)
   combines a dark-aware semantic model with temporal features; its authors
   report up to 26.63 fps on an RTX 3090 using mixed precision in their setup.
   This is not our game's frame rate, a comparison on the user's GPU, a native
   game-resolution result, or proof that the user's 80–110 fps target is met.
   The current vkBasalt pipeline has no neural inference integration. Models
   and their training may emphasize cast-shadow masks rather than every dark
   occluded surface relevant to the user's requested look; no generalization
   claim for these game images follows from photographic benchmarks.

## Distinction between mask and material color

A useful shadow probability would help decide **where** to apply a correction;
it does not tell us the hidden material's color. The current pipeline has only
the rendered color and image-derived statistics, not authoritative albedo,
material ID, normal or shadow buffer. Direct engine-provided data, if a game
and integration exposed it, could provide stronger evidence, but availability
and cross-game compatibility have not been established. With only the image,
colored illumination, occlusion and indistinguishable RGB explanations remain.
Do not blindly transfer a lit pixel's hue or assume a physically gray pixel has
recoverable hue.

## Recommended next experiment

Evaluate a published detector *offline as an oracle comparison*, not as a
runtime commitment: inspect its raw confidence/mask on the existing daylight
paving, dark shelf, timber and colored-light inputs, with dark non-shadow objects
and missing lit counterparts as controls. Compare masks against human-visible
scene context, note misses, false regions, domain and resolution, then compare a
masked, bounded color-only visual proxy against source and current. Masks alone
do not establish improved image quality. Do not download/run uninspected legacy
generators, assume model installation or game compatibility, or turn a model's
photograph benchmark into an 80–110 fps claim. Any runtime route needs a separate
data path, reproducible performance evidence when authorized, motion/cut checks,
and an explicit choice of how to handle uncertain material/lighting.

Separately, a small analytic shadow-edge study on the real paving boundary can
test whether material/lighting relationships provide useful evidence without
copying the full region-growing algorithm. The failed single-frame texture and
temporal ambiguity controls remain in
[the surface-relation screen](2026-11-07_shadow_surface_relation_screen.md).
Neither direction is an approved implementation candidate yet.
