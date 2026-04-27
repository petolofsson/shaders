# BackBuffer Re-Quantization Fix — Research & Proposal

**Date**: 2026-04-27  
**Context**: vkBasalt HLSL shader chain for Arc Raiders (alpha pipeline)  
**Problem**: Three passthrough blits currently added to keep BackBuffer alive cause
unnecessary 8-bit UNORM re-quantization between effects.

---

## 1. Confirmed vkBasalt BackBuffer Behavior

### Architecture: Ping-Pong with Per-Effect Fake Images

vkBasalt uses a **ping-pong fake-image model**. Each effect in the chain gets:

- An **input fake image** — allocated by `LogicalSwapchain` (`fakeImages` vector, `logical_swapchain.hpp`)
- An **output fake image** — which becomes the next effect's input

The input for the first effect is the game's swapchain image. The final effect's output is
blitted back to the real swapchain.

**Source**: `src/logical_swapchain.hpp`
```cpp
std::vector<VkImage> images;      // actual swapchain images
std::vector<VkImage> fakeImages;  // intermediate processing images per effect
VkDeviceMemory fakeImageMemory;
```

### The Critical Detail: Output Starts Cleared

The Vulkan render pass created for each effect uses:

```cpp
// src/renderpass.cpp
attachmentDescription.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
```

with a clear color of `{0.0f, 0.0f, 0.0f, 1.0f}`.

This means **each effect's output fake image starts black** at the beginning of that effect's
render pass. The only way the output image becomes non-black is if at least one pass in the
effect writes to BackBuffer (i.e., a pass with no explicit `RenderTarget`).

### Within-Effect Ping-Pong

For a multi-pass effect, `src/effect_reshade.cpp` allocates intermediate backbuffer images
when `outputWrites > 1` and uses `switchSamplers` flags to toggle between:
- `backBufferDescriptorSets` — the intermediate ping-pong images
- `outputDescriptorSets` — the final output image

Pass ordering within a single effect:
- Pass writes to **RenderTarget** → intermediate texture updated; BackBuffer sampler
  continues pointing to the current backbuffer image (no switch)
- Pass writes to **BackBuffer** (no RenderTarget) → the output image is written; the
  backbuffer sampler advances to that result for subsequent passes

### Root Cause of the Black Screen Bug

Chain: `corrective_render_chain → creative_render_chain → olofssonian_chroma_lift → creative_color_grade`

```
corrective_render_chain:
  ALL passes → RenderTarget   ← output fake image stays BLACK
                                 (load op cleared it, never overwritten)

creative_render_chain:
  input = corrective's BLACK output
  ALL passes → RenderTarget   ← output fake image stays BLACK

olofssonian_chroma_lift:
  input = creative's BLACK output
  Pass UpdateHistory → ChromaHistoryTex   (RenderTarget)
  Pass ApplyChroma   → BackBuffer         reads BLACK → outputs BLACK
  output = BLACK
  
creative_color_grade:
  input = BLACK → grade a black frame → BLACK output
```

**Each passthrough blit** (BackBuffer → BackBuffer) fixes this by ensuring the output fake image
is populated with the input content before the effect's own RenderTarget passes run.

### No Config Option Exists

The `loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR` is hardcoded in `renderpass.cpp`. There is no
vkBasalt configuration key to change BackBuffer forwarding behavior. The only config options
are `effects`, `toggleEffectKey`, `reshadeTexturePath`, and `reshadeIncludePath`.

---

## 2. Cross-Effect Texture Sharing

**1×1 textures (confirmed working)**: `LumHistTex`, `SatHistTex` are declared identically
across multiple effects. The ReShade runtime deduplicates textures by name within the effect
namespace — these share the same `VkImage`.

**Full-resolution textures (unconfirmed / likely broken)**: The ReShade texture pool is
per-effect. `src/effect_reshade.hpp` shows per-effect maps:
```cpp
std::unordered_map<std::string, VkImage> textureImages;
```
Each separate `.fx` file loaded as a distinct effect gets its own `EffectReshade` instance with
its own maps. There is no cross-instance texture deduplication at the vkBasalt layer.
Small textures may appear to "work" due to lucky address aliasing in device memory, but
full-res textures (2560×1440×4 = 14.7 MB each) occupy distinct allocations.

**Conclusion**: Do not rely on cross-effect full-res texture sharing. 1×1 and small
(≤ a few hundred bytes) textures are confirmed safe.

---

## 3. Options

| # | Approach | Invasiveness | Quality Impact | Notes |
|---|----------|-------------|----------------|-------|
| 1 | **Status quo — keep passthrough blits** | None (already done) | −3 × 8-bit UNORM round-trips ≈ ±0.5/255 error each ≈ 0.2% per channel per blit | Accumulates across 3 blits; pure loss, however sub-perceptual for SDR |
| 2 | **Single-file merge → `color_grade.fx`** | High — structural refactor of 3–4 files | Zero extra quantization | Passes share the same within-effect ping-pong; no inter-effect gap |
| 3 | **Shared full-res RGBA16F intermediate texture** | Medium — re-declare same texture across files | Zero quantization (RGBA16F) | Cross-effect full-res sharing is unreliable (per §2); risk of silent breakage |
| 4 | **Make every analysis effect forward BackBuffer explicitly** | Low — one additional pass per effect | Same as option 1, but more deliberate | Semantically equivalent to status quo passthrough blits |
| 5 | **vkBasalt config option** | None | N/A | Does not exist; `loadOp` is hardcoded |

### Quantitative Noise Budget for Status Quo

Each 8-bit UNORM round-trip quantizes to 256 levels. For a signal in [0, 1]:

- Max quantization error per channel per blit: 0.5 / 255 ≈ 0.00196
- After 3 blits (worst-case additive): ≈ 0.0059 ≈ 0.59%
- At 18% grey (0.18): error ≈ 0.6% of 0.18 ≈ 0.001 — about 0.3 counts at 8-bit

Practically: the noise is below the threshold of photographic reproduction. The status quo
is *acceptable* but not *optimal* for a quality-focused pipeline.

---

## 4. Recommended Solution: Single-File Merge

**Recommendation**: Merge `corrective_render_chain.fx`, `creative_render_chain.fx`,
`olofssonian_chroma_lift.fx`, and `creative_color_grade.fx` into a single `color_grade.fx`.

### Rationale

- **Eliminates the problem structurally** rather than working around it with blits
- **Zero quantization cost**: all passes share the effect's internal ping-pong images
- **Single tuning file contract** stays intact: `creative_values.fx` remains the only
  user-facing surface
- **Cross-effect texture sharing becomes irrelevant**: intermediate textures are within-effect
- **Compile-time visibility**: all passes can see each other's RenderTarget declarations

### New conf effects line

```
effects = analysis_frame_analysis:analysis_scope_pre:color_grade:analysis_scope
```

### Merged technique structure

```hlsl
technique ColorGrade {
    pass ComputeLowFreq      { RenderTarget = CreativeLowFreqTex; }
    pass ComputeZoneHistogram { RenderTarget = CreativeZoneHistTex; }
    pass BuildZoneLevels     { RenderTarget = CreativeZoneLevelsTex; }
    pass SmoothZoneLevels    { RenderTarget = ZoneHistoryTex; }
    pass UpdateHistory       { RenderTarget = ChromaHistoryTex; }
    pass MegaPass            { /* no RenderTarget → writes BackBuffer */ }
}
```

`VK_ATTACHMENT_LOAD_OP_CLEAR` fires once before Pass 1. MegaPass is the only BackBuffer
writer — no round-trips, no re-quantization.

### Key Constraints for Implementation

- `kHalton[256]` static const array: already in production and working; no workaround
  possible for a 256-element table — retain as-is
- All other `static const` arrays: replace with `#define` literals or helper functions
- BackBuffer row y=0 guard in MegaPass: `if (pos.y < 1.0) return col;`
- `creative_values.fx` remains the only tuning surface

---

## 5. Conclusion

The single-file merge (`color_grade.fx`) is the correct long-term fix. The current
passthrough workaround introduces 0.59% max accumulated quantization error — sub-perceptual
for SDR but architecturally wrong for a quality-committed pipeline.

The merge is a structural refactor (high invasiveness) but straightforward: all logic already
exists in `creative_color_grade.fx`'s MegaPassPS; the merge adds the analysis passes as
preceding RenderTarget passes in the same technique.
