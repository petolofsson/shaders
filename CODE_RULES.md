# Code Rules

Compact checklist for HLSL/vkBasalt shader edits.

1. **Simple control flow.** No dynamic branching on pixel properties. Use
   `lerp`, `smoothstep`, `step`, `saturate`, and arithmetic masks. Recursion is forbidden.
2. **Fixed loops.** Loop bounds must be compile-time constants with explicit
   `[loop]` or `[unroll]`.
3. **Static resources.** Declare textures, samplers, and render targets in the
   effect header. No runtime allocation or hidden resource construction.
4. **Short helpers.** Keep helpers and pixel shaders under one screen where
   possible. `ColorTransformPS` is the only large orchestration exception.
5. **Respect signal domains.** Bound UVs and encoded highway values where produced.
   Preserve signed RGB and positive overrange in internal grade math; apply gamut
   projection and the SDR ceiling at processing/output boundaries, as in `AGENTS.md`.
6. **Small scope.** Declare variables at first use and do not reuse a name for a
   different meaning.
7. **Use outputs.** Every non-void helper result must be consumed. No throwaway
   calls except explicitly documented diagnostics.
8. **Preprocessor restraint.** Use `#define` for constants and complete
   expression macros only. No token pasting, variadic macros, recursive macros,
   or algorithmic `#ifdef` forks.
9. **One lookup level.** Do not nest sampler calls inside other sampler arguments.
   Do not hide sampler accesses inside macros, except documented highway reads.
10. **Known gotchas before commit.** Check `AGENTS.md`: no `static const float[]`
    or `static const float3`, no variable named `out`, no `tex2Dlod` on
    BackBuffer, no cross-technique mip assumptions, and preserve BackBuffer with
    passthrough when an effect otherwise only writes explicit render targets.
