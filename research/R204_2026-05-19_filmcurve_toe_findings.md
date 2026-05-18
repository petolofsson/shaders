# R204 Findings — Film Curve Toe: Physical Justification Audit

**Verdict: `tc_comp` is physically unjustified in this pipeline and should be removed.**

---

## Finding 1 — Domain mismatch: toe belongs in scene-referred space

A film print H&D curve (including the 2383 toe) is designed for **scene-referred logarithmic data** — the input to the print stock is the optical density of the negative, expressed in log exposure. The toe represents the print paper's nonlinear response at low exposure (thin negative, dark scene areas).

This pipeline operates **display-referred**: values are already mapped through ACES (scene → display). Applying a toe in this space has no physical counterpart. The toe's shape encodes a photochemical process that already happened inside ACES.

## Finding 2 — ACES 2383 emulation fires as an LMT, before the Output Transform

In the ACES reference pipeline, the 2383 print stock emulation is an optional **Look Modification Transform (LMT)** applied in scene-referred log space, *upstream* of the Output Transform that performs the actual tone mapping. Professional tools (DaVinci Resolve, OCIO pipelines) follow this same order.

This pipeline inverts that: the FilmCurve fires *after* the game's ACES Output Transform. Applying the toe again in display-referred space is a second compression on an already-compressed signal — the ACES OT already handled the transition from scene to display.

## Finding 3 — Real-time filmic tones use toe for HDR→SDR compression, not print emulation

Hable ("Uncharted 2") and Gran Turismo tonemappers include toe parameters, but these serve a different purpose: compressing the shadow end of an HDR scene during the single-pass scene-to-display mapping. These are **tonemapping toes**, not **print toes**. Since this pipeline is post-ACES (already tone-mapped), adding a further toe is a redundant second pass.

## Finding 4 — D-min is irrelevant in display-referred linear space

Kodak 2383 D-min (the black point density of the print stock, ~0.04–0.06 density units) is a photochemical property expressed in log density. Game output in linear [0,1] has no equivalent concept. Attempting to model D-min as a fixed lift in display-referred linear space is a category error.

## Finding 5 — The existing `PRINT_STOCK` effect already owns shadow character

`ApplyPrintStock` runs downstream of `FilmCurveApply` and applies:
- Power-toe density curve (shadow treatment)
- Reinhard shoulder
- Masking coupler (warm shadow density)
- Midtone desaturation

Any print-like shadow density the user wants is already controllable via `PRINT_STOCK`. The FilmCurve toe in `ApplyCorrective` duplicates this work unconditionally and without a knob.

---

## Recommendation

**Remove `tc_comp` from `FilmCurveApply`.** The function reduces to:

```hlsl
return x + body_s - sh_comp;
```

- `body_s` (upper-mid lift) — remains justified: models the one-sided S of the midrange body, display-referred.
- `sh_comp` (shoulder) — remains justified: graceful SDR ceiling compression.
- `tc_comp` (toe) — **removed**: no physical justification in display-referred space; shadow treatment belongs to `PRINT_STOCK` and `BLACKS`.

**Expected outcome:** Shadow detail preserved when `CORRECTIVE_STRENGTH` is enabled at zero knobs. Intentional shadow treatment remains fully available via `PRINT_STOCK` and `BLACKS`.

**Risk:** None. `PRINT_STOCK` covers any print-toe character the user wants, with a knob.
