# R60 — Temporal Context Shadow Lift

**Date:** 2026-05-02
**Status:** Proposal — see findings file.

---

## Motivation

Mobile phone adaptive display brightness (Jha et al., CASES 2015) uses two parallel
adaptation layers:

1. **Slow ambient layer** — sustained ambient light tracked over seconds to minutes.
   Represents "what environment is the viewer in?"
2. **Fast content layer** — per-frame luminance and edge analysis within that baseline.
   Represents "what's on screen right now?"

The key finding: the eye's sensitivity to brightness changes varies with sustained
context, not just instantaneous content. Purely fast adaptation fights the viewer's
own dark-adaptation; purely slow adaptation is sluggish on genuine scene changes.

Our R57–R59 chain is a mature fast content layer. It has no slow ambient layer.
The Kalman on `zone_log_key` (K_inf=0.095, ~10 frames) converges to the current
scene in ~1.5 s and has no memory of sustained scene darkness.

---

## Problem

A 5-minute night mission and a 3-second tunnel shadow are treated identically once
the fast Kalman converges. They shouldn't be:

- **Brief dark dip**: viewer eyes haven't adapted → lift detail they can't yet resolve
- **Sustained dark environment**: viewer has dark-adapted, darkness is intentional
  atmosphere → backing off lift preserves mood and avoids fighting the game's intent

---

## Open questions

1. Is `ChromaHistoryTex` col 7 row 0 genuinely free? Verify nothing reads or writes it.
2. What `K_slow` gives the right time constant? Human photopic adaptation is 10–30 s;
   at 60 fps that's K_slow ≈ 0.003–0.010.
3. Log-space vs linear ratio for `context_lift` — which formulation is symmetric and
   stays well-behaved at extremes?
4. What `CONTEXT_WEIGHT` is the right blend? Full normalisation (weight=1) would
   destroy sustained-dark atmosphere; zero is the current behaviour.
5. Register pressure: `ColorTransformPS` is already at ~129 scalars (spill threshold
   128). Does one extra tap + 3 scalar ops push it over?
