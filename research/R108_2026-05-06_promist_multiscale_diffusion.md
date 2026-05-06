# Research Findings — Pro-Mist Multi-Scale Neutral Diffusion — 2026-05-06

## Status: Implemented

Two-scale diffusion live. R92 IGN already present in ProMistPS post-merge (no change needed).

## Design constraint

Pro-Mist's separated concern is **global micro-contrast softening only.**
Halation (fringe around bright sources) is handled by R105/R106 in ColorTransformPS.
Veil (additive DC lift) is removed from the chain — engine handles atmospheric volumes.
Any spectral/warm character belongs to halation, not here.

---

## Current state

`ProMistPS` reads a single mip level (mip1, 1/16-res effective) and lerps it
against the full-res BackBuffer with a scene-adaptive strength:

```hlsl
float3 blurred = tex2Dlod(MistDiffuseSamp, float4(uv, 0, 1)).rgb;  // one scale only
float3 result  = lerp(base.rgb, blurred, saturate(adapt_str));
```

`MistDiffuseTex` has `MipLevels=2`, so mip0 (1/8-res, tighter) is available but unused.
The result is a single-scale diffusion: at any MIST_STRENGTH value, the kernel shape is
fixed — only the blend weight changes. This means low and high MIST_STRENGTH produce
the same spatial frequency signature, just at different intensities.

**The limitation:** Real Pro-Mist filters produce a different kernel shape at different
strengths. A light hand produces fine-grain micro-contrast softening that affects only
tight spatial frequencies. A heavy hand extends the diffusion into coarser structures.
Single-scale lerp cannot reproduce this because the kernel's spatial reach is fixed by
mip1 regardless of strength.

---

## Proposed implementation: two-scale neutral blend

Use both mip levels. At low MIST_STRENGTH, blend toward mip0 (tight diffusion — fine
micro-contrast only). At high MIST_STRENGTH, shift blend toward mip1 (wide diffusion —
coarser structures included). No spectral tinting on either level.

```hlsl
float3 mist_tight = tex2Dlod(MistDiffuseSamp, float4(uv, 0, 0)).rgb;  // mip0: 1/8-res
float3 mist_wide  = tex2Dlod(MistDiffuseSamp, float4(uv, 0, 1)).rgb;  // mip1: 1/16-res

// Scale-selector: 0.0 = tight only, 1.0 = wide only
// Ramps from 0 at MIST_STRENGTH=0 to 1.0 at MIST_STRENGTH=4
float scale_w   = saturate(MIST_STRENGTH * 0.25);
float3 mist_blur = lerp(mist_tight, mist_wide, scale_w);

float3 result = lerp(base.rgb, mist_blur, saturate(adapt_str));
```

At testbed `MIST_STRENGTH = 2.75`: `scale_w ≈ 0.69` → blend is 31% tight / 69% wide.
This is roughly equivalent to the single mip1 read at current strength while giving
different spatial behaviour at lower strengths. At `MIST_STRENGTH = 1.0`: `scale_w =
0.25` → tighter kernel, less coarse-structure softening.

Both mip reads are spectrally flat — no per-channel weighting, no warm tint. The
diffusion is photometrically neutral by construction.

---

## R92 — IGN dither (fold in here)

HANDOFF 2026-05-05 flags R92: ProMistPS still uses `sin(dot)*43758` white-noise
dither. Replace with Jimenez IGN (already in ColorTransformPS):

```hlsl
// Replace:
float dither = frac(52.9829189 * frac(dot(pos.xy, float2(0.06711056, 0.00583715)))) - 0.5;

// With IGN:
float ign_frame = float(FRAME_INDEX & 63u);
float dither    = frac(0.5 + ign_frame * 0.61803398875
                     + 0.5 * frac(dot(pos.xy, float2(0.06711056, 0.00583715))));
dither -= 0.5;
```

FRAME_INDEX must be declared as a uniform (already present in grade.fx for IGN in
ColorTransformPS — confirm it's accessible in ProMistPS scope or re-declare).
This folds R92 into R108 since the code change is one line.

---

## GPU cost

| Item | Cost |
|------|------|
| Extra `tex2Dlod` mip0 | +1 tex tap |
| `scale_w` + lerp (scale blend) | +4 ALU |
| IGN dither (R92) | ±0 ALU vs. current sin-dither |
| Total delta | +1 tap, +4 ALU in ProMistPS |

---

## Expected behaviour change vs. current

| MIST_STRENGTH | Current kernel | R108 kernel |
|---------------|---------------|-------------|
| 1.0 | mip1 (1/16-res) at low weight | mip0 (1/8-res)-dominant at low weight |
| 2.75 | mip1 (1/16-res) at mid weight | ~70% mip1 + 30% mip0 at mid weight |
| 4.0 | mip1 (1/16-res) at high weight | mip1 (1/16-res) at high weight |

At the testbed value the change is subtle. The difference is more visible at low
MIST_STRENGTH where the filter becomes tighter (only fine micro-contrast affected)
versus the current always-wide mip1.

---

## Risks

- mip0 of MistDiffuseTex is the raw MistDownsamplePS output (1/8-res, no extra blurring
  beyond the downsample). Its effective blur sigma is approximately the pixel grid step
  at 1/8 resolution — for a 1920-wide image that is ~12 pixels radius. Confirm this is
  fine-grain enough to constitute "tight micro-contrast softening" and not just another
  coarse blur.
- `scale_w` linear ramp on MIST_STRENGTH could be replaced with `saturate(MIST_STRENGTH
  / 3.0)` if current slope proves too aggressive.

---

## Targets

- Output finished: +2% (spatially adaptive kernel shape vs. single-scale lerp)
- Output novel: +2% (strength-driven scale selection in game post-process Pro-Mist
  simulation — not documented in reviewed implementations)

---

## References

- Spektrafilm diffusion.py — `_DIFFUSION_FILTER_SHAPES` core/halo/bloom separation
  (neutral core + tinted halo): confirms multi-scale diffusion is the correct physical
  model. R108 takes only the neutral core concept; halo/bloom are out of scope here.
- HANDOFF 2026-05-05 — R92 (IGN dither for ProMistPS) flagged as pending.
- PLAN.md R99 (2026-05-04): Pro-Mist redesigned as global lerp diffusion. This is the
  correct base; R108 refines the spatial scale behaviour within that design.
