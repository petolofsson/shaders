# Code Rules (HLSL / SPIR-V)

Adapted from Holzmann's Power of Ten for this shader pipeline.

1. **Simple control flow.** No dynamic branching on pixel properties. GPU architectures execute
   both sides of a branch across a warp; branching on per-pixel values causes divergence and
   can produce visible seams. Prefer arithmetic formulations — `lerp`, `smoothstep`,
   `saturate`, `step` — over `if`/`else`. The only permitted branches are on uniform
   compile-time constants or pass-level uniforms that are identical for every pixel in the
   draw call. Recursion is forbidden by GPU architecture and must not be attempted.

2. **Fixed loop bounds.** Every loop must have a compile-time constant iteration count.
   Annotate with `[unroll]` or `[loop]` explicitly; never leave loop unrolling implicit.
   Variable-bound loops whose termination depends on pixel data are not permitted. If the
   bound is not a literal constant or a `#define`d integer, the rule is violated.

3. **No runtime resource allocation.** HLSL has no heap. All textures, samplers, and render
   targets must be declared statically in the effect file header before any pass. Intermediate
   data lives only in declared render target textures or in local registers. `RWTexture` and
   UAVs are not used in this pipeline; if introduced, they must be pre-allocated, not
   dynamically sized.

4. **Short functions.** No pixel shader or helper function longer than 60 lines. The
   MegaPass (ColorTransformPS) is the single permitted exception, structured as a strict
   linear sequence of named stages with one helper call per stage. Any stage that grows
   past 60 lines must be extracted into a named helper. Helper functions must fit on one
   screen without scrolling.

5. **Explicit bounds on every output.** HLSL has no `assert()`. The equivalent discipline
   is: every value that must stay in a range — a hue angle in [0,1], a chroma in [0, ceil],
   a luminance in [0,1] — must be explicitly bounded with `saturate()` or `clamp()` at the
   point it is computed or returned, not deferred to the caller. Each function that produces
   a bounded output must apply the bound itself. Constants used as thresholds or ceilings
   must be validated at authoring time against the data they are derived from (see research
   notes). A bound that can never be reached given the input domain violates this rule — it
   must either be tightened to be meaningful or removed.

6. **Smallest scope.** Declare every variable at the point of first use, not at the top of
   the function. Do not reuse a variable for a different purpose after its first use is
   complete. Intermediate values used only within a single stage must not leak into
   surrounding scope. Uniforms and textures shared across passes must be documented in the
   header comment of the effect file.

7. **Validate inputs and use all outputs.** Every helper function that accepts a hue,
   luminance, or chroma value must clamp or `saturate()` the input at entry, even if the
   caller is trusted. Texture sample coordinates must be in [0,1] before the sample call.
   Every call to a non-void helper must use the return value — assigning to `_` or
   discarding silently is not allowed. The data highway `ReadHWY()` macro returns a decoded
   scalar; the caller must store and use the result, not call it purely for a side effect.

8. **Preprocessor for constants and includes only.** `#define` is permitted for named
   numeric constants (e.g., `HB_CEIL_*`, `HB_BAND_*`) and for single-expression utility
   macros that expand to a complete expression. Token pasting (`##`), variadic macros, and
   recursive macro expansion are not permitted. All macros must expand to a syntactically
   complete unit — a full expression or a full statement, never a fragment. `#ifdef`
   conditional compilation is permitted only for debug overlays and platform toggles, not
   for algorithmic logic. Encoding and decoding of highway slots must be done in named
   inline functions or documented macros in `highway.fxh`, never inline at the call site.

9. **One level of indirection.** No nested texture lookups — a sampler call must not appear
   inside an argument to another sampler call. Sampler accesses must not be hidden inside
   macro bodies (the `ReadHWY()` macro is the single permitted exception, explicitly
   documented). `out` parameters are permitted only where a function must return more than
   one value and a struct return would be disproportionate; in all other cases prefer a
   return value. Function pointers do not exist in HLSL; technique and pass structure must
   be declared explicitly in the effect file, never constructed indirectly.

10. **Zero warnings, known-gotcha checklist.** All effect files must compile without
    warnings under the strictest available HLSL compiler settings. Before committing any
    shader edit, verify against the silent-failure checklist in `CLAUDE.md`: no
    `static const float[]` or `static const float3` (compiles silently, wrong output); no
    variable named `out` (reserved keyword); no `tex2Dlod` on BackBuffer (always returns
    zero); no `MipLevels > 1` on cross-technique render targets (mip1+ silently zeroed).
    Any effect that introduces a new render target or a new cross-technique dependency must
    add an entry to the checklist.
