# R203 — Texture Highway: Prior Art Survey
_2026-05-18_

## 1. Render Target Atlasing in Real-Time Pipelines

Prior art exists but targets a different problem. Render-to-texture-atlas (RTTA) — packing multiple scene objects' render outputs into sub-regions of one large texture — is documented (Scherzer et al., "Interactive Rendering to Perspective Texture-Atlases"). It addresses geometry batching, not post-process intermediate consolidation.

For post-process pipelines, the dominant engine architecture is a **render target pool** (Unity HDRP, Unreal Engine): a frame allocates named transient textures from a pool; lifetimes are tracked and GPU memory is aliased when lifetimes do not overlap. This is not atlasing — each texture occupies its own address space (potentially aliased), not a UV sub-region of a single texture.

No GDC talk or engine reference was found advocating packing multiple post-process intermediates as sub-regions of a single texture. Texture atlases are well-known for static sprite/material data, not for RTs.

**Verdict:** Atlasing post-process RTs into one texture with UV sub-regions appears novel. Engineering cost (UV remapping in every shader, broken bilinear at sub-region borders) makes it unattractive vs. the standard pool approach. However, the texture highway does not use UV sub-regions for spatial data — the spatial lane occupies full rows, avoiding the bilinear border problem.

---

## 2. ReShade / vkBasalt Inter-Effect Texture Sharing

**Directly confirmed mechanism** (ReShade forum, crosire):

- Textures with the **same name** in two `.fx` files share the same GPU memory. Intentional and documented.
- Only textures are shared across effects. Functions and samplers are not.
- Name collisions between effects that do not intend to share are **undefined behavior** — no built-in detection. This is a latent risk in the current pipeline.
- **Pooled textures** (`pooled = true`) allow the runtime to share any texture with matching dimensions/format, regardless of name. Since ReShade 4.9, pooled textures within the same `.fx` file are excluded from cross-effect sharing to prevent ping-pong conflicts.
- vkBasalt inherits this behavior via the shared ReshadeFX compiler stack.

**Key implication for this pipeline:** vkBasalt matches cross-effect textures by **name + format + dimensions**. The LumHistTex format mismatch (R16F in analysis_frame vs R32F in analysis_scope) means they resolve to **different GPU resources** — analysis_scope is likely reading zeroed or stale data. **This is a confirmed live bug.**

**Verdict:** The scalar highway already uses the name-sharing mechanism correctly (declared once in highway.fxh, included by all effects). Extending to a 2-D texture highway declared once in common.fxh is architecturally identical — no new mechanism required.

---

## 3. G-Buffer Packing and Consolidation

Well-documented trade-off space:
- **Rich Geldreich, GDC 2004**: Xbox 1 G-buffer attribute packing — normals, gloss, color packed across RGBA channels to fit MRT limits.
- **JCGT 2013** ("A Cache-Friendly Approach to Deferred Shading"): replacing a 24-byte G-buffer with a compact visibility buffer cuts bandwidth ~3×.
- **Tiled deferred shading** (ndotl.wordpress.com, 2014): reducing from 4 to 3 MRTs is frequently cited as a meaningful win.

The literature consistently shows that packing **semantically related** data into one target (normal.xyz + roughness.w) saves bandwidth, but packing unrelated data hurts readability without proportional gain.

**Verdict:** Channel packing within data rows of the texture highway (e.g., p25/p50/p75/P all in one RGBA16F row) follows established G-buffer practice and is well-justified.

---

## 4. Bandwidth Cost of Full-Screen Reads in Post-Process Chains

- **ARM developer blog** ("Post-processing effects on mobile optimization"): each full-res read/write round-trip is the primary post-process cost on tile-based GPUs.
- **Canonical optimization**: half-res or quarter-res intermediates for blurs. The pipeline already does this (LFDownscale1/2, DiffusionDownsample).
- **Frame graph / transient aliasing** (Themaister, "Render Graphs and Vulkan," 2017; Pavel Smejkal, "Aliasing Transient Textures in DirectX 12"): the driver can alias non-overlapping transient texture lifetimes onto the same physical pages. This is the engine-level answer — not available to a vkBasalt layer.

**For this pipeline:** eliminating one full BackBuffer read (merging DownsamplePS and ComputeLowFreqPS into one pass) is the single concrete bandwidth saving. At 1440p: 2560×1440 × RGBA16F = ~29 MB per avoided read, 60fps = ~1.7 GB/s recovered. Real but not transformative.

The texture highway write pass-through (320×180 at 1440p = ~57,600 pixels per effect write) is negligible — compare to a full-res pass at 2560×1440 = 3.7M pixels.

---

## 5. Resolution-Independent Texture Layout

Standard pattern in engine code: allocate at max resolution, scale viewport. Fixed-dimension auxiliary textures (histograms, LUTs, zone maps) are trivially resolution-independent.

The scalar highway (256×1, fixed) is an instance. The texture highway spatial lane (BUFFER_WIDTH/8 × BUFFER_HEIGHT/8, dynamic) follows the correct pattern for resolution-dependent data. Data rows (fixed pixel count at the left of each row, rest padding) scale correctly at all resolutions.

**Confirmed safe** at 1440p and 4K: BUFFER_WIDTH and BUFFER_HEIGHT are compile-time preprocessor constants in ReshadeFX. Texture dimensions defined in terms of these constants are resolved at shader compilation time per-resolution.

---

## Novelty Assessment

| Concept | Prior Art | Verdict |
|---|---|---|
| Same-name texture sharing in ReShade/vkBasalt | Documented (crosire, ReShade forum) | Established — safe to use |
| Scalar highway (current HighwayTex 256×1) | No identical pattern found | Existing pipeline invention |
| 2-D texture highway (multi-row image + data rows as data bus) | RTTA for geometry exists; not for post-process | **Appears novel** in post-process context |
| Channel packing in data rows | G-buffer packing (GDC 2004, JCGT 2013) | Established practice |
| Transient RT aliasing | Well-documented (frame graphs) | Not applicable to vkBasalt layer |

**Bottom line:** The texture highway is a natural extension of the scalar highway pattern, with no blocking prior art. The name-sharing mechanism is confirmed to work. The specific architecture (fixed data rows + resolution-scaled spatial lane, all declared in a shared header, pass-through write mechanism) appears to be novel in the post-process pipeline domain.

---

## Sources

- ReShade forum: [Share functions/textures/samplers between shaders](https://reshade.me/forum/shader-discussion/4159)
- ReShade forum: [Behavior of pooled textures](https://reshade.me/forum/shader-troubleshooting/7008)
- Themaister: [Render Graphs and Vulkan — a deep dive](https://themaister.net/blog/2017/08/15/render-graphs-and-vulkan-a-deep-dive/)
- Pavel Smejkal: [Aliasing Transient Textures in DirectX 12](https://pavelsmejkal.net/Posts/TransientResourceManagement)
- JCGT: [A Cache-Friendly Approach to Deferred Shading](https://jcgt.org/published/0002/02/04/paper.pdf)
- ARM: [Post-processing effects on mobile optimization](https://community.arm.com/arm-community-blogs/b/graphics-gaming-and-vr-blog/posts/post-processing-effects-on-mobile-optimization-and-alternatives)
- Rich Geldreich: [Xbox 1 G-Buffer Attribute Packing, GDC 2004](https://sites.google.com/site/richgel99/the-early-history-of-deferred-shading-and-lighting/xbox-1-g-buffer-attribute-packing-pixel-shader)
- Scherzer et al.: [Interactive Rendering to Perspective Texture-Atlases](https://www.researchgate.net/publication/225091329)
- ndotl: [Tiled deferred shading tricks](https://ndotl.wordpress.com/2014/05/18/tiled-deferred-shading-tricks/)
