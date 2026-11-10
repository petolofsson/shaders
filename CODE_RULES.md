# Shader implementation rules

Read [AGENTS.md](AGENTS.md) for repository constraints and the relevant
[pipeline contracts](docs/pipeline.md) before changing a stage.

## HLSL structure

- No dynamic branches on pixel properties or recursion. Use `lerp`, `smoothstep`,
  `step`, `saturate` and arithmetic masks.
- Loops need compile-time bounds and explicit `[loop]` or `[unroll]`.
- Declare textures, samplers and targets statically; no hidden allocation.
- Keep helpers and pixel shaders short; `ColorTransformPS` is the orchestration
  exception. Declare variables at first use and do not repurpose names.
- Consume every helper result; document any diagnostic exception.
- Limit `#define` to constants and complete expressions. No token pasting,
  variadic/recursive macros or algorithmic `#ifdef` forks.
- Do not nest sampler calls or hide them in macros, except documented highway reads.

## Domains and state

Bound UVs and highway encodings where produced. Preserve signed RGB and positive
overrange internally; project gamut and apply the SDR ceiling at output boundaries.
Apply linear-light reconstruction gains in RGB, not directly to Oklab coordinates.

Use actual allocated integer texture dimensions for taps and metadata. Keep
precise authoritative histories out of lower-precision feedback paths. Separate
initialization sentinels from legitimate zero/small state. Prove state/precision
changes with explicit GPU readback; do not compensate for storage defects by
changing rates.

## vkBasalt / SPIR-V pitfalls

- No `static const float[]` or `static const float3`: output can compile incorrectly.
- No variable named `out`; it is reserved.
- Use `tex2D(BackBuffer, uv)`; `tex2Dlod(BackBuffer, ...)` returns zero.
- Separate `.fx` effects cannot share explicit render targets, even mip0.
  Build/read dependent surfaces within one effect technique.
- Inter-effect BackBuffer is UNORM; overrange clips between effects.
- Keep BackBuffer `SRGBTexture` and `SRGBWriteEnable` false with explicit sRGB math.
  The 10-bit UNORM validation swapchain has no corresponding sRGB view; common
  8-bit game output is a distinct quantization context.
- Effects that render only to explicit targets must end with BackBuffer passthrough.
- A pass may sample its own render target (history and highway pass-through) only at
  its own texel. Vulkan leaves render-target feedback undefined; same-texel reads are
  the pattern this pipeline relies on. Cross-texel reads of the target being written
  are forbidden.
