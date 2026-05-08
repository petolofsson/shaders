# R128 — Specular Pings
**Date:** 2026-05-08
**Status:** Implemented

## Motivation

From a study of the Lego Movie cinematography (expanded cinematography article): the
production deliberately let isolated specular hotspots clip to overexposure to sell
photographic realism — "specular pings of overexposure selling photographic exposure
realism." The pipeline already has:

- **R105 halation** — spreads energy *outward* from bright sources (DoG blur ring)
- **Pro-Mist** — additive shimmer where blurred > sharp (highlight→shadow bloom)

Neither models the sharp peak itself. A real lens looking at a metallic surface or
glinting water shows tiny, bright, *un-spread* pinpoints — the ping. The surrounding
area may glow (halation) but the ping stays crisp.

## Design

**Detection:** A pixel qualifies as a specular ping when:
1. Its luminance significantly overshoots its 1/16-res neighbourhood average (`hal_blur`,
   already computed for halation) — i.e., it is genuinely isolated, not part of a broad
   bright area.
2. Its absolute luminance is high enough to be a real highlight (gate smoothstep 0.45→0.75).

**Operation:** Additive lift, slight warm tint. Real specular highlights reflect the light
source colour (usually warm/white) rather than the material. The tint factors
`float3(1.04, 1.00, 0.92)` are a gentle push toward warm white.

**SDR construction:** The `saturate()` ceiling is intentional — a ping that clips to 1.0
is correct. An over-exposed specular should read as clipped white, which is exactly what
SDR film looks like at a specular hotspot.

## Implementation

`grade.fx` — `ColorTransformPS`:

1. **Hoist `LowFreqMip1` read** — was read twice (line 334 for halation, line 438 for
   Retinex `.a`). Replaced with a single `float4 lf_mip1_tex` hoisted alongside
   `lf_mip2_tex`. Net: −1 texture read.

2. **Ping block** — inserted after `lin = saturate(chroma_rgb)` (post gclip/gamut),
   before dither:

```hlsl
{
    float ping_local = dot(hal_blur, float3(0.2126, 0.7152, 0.0722));
    float ping_broad = dot(lf_mip2,  float3(0.2126, 0.7152, 0.0722));
    float ping_xs    = max(0.0, ping_local - ping_broad - 0.08);
    float ping_gate  = smoothstep(0.40, 0.70, ping_local);
    lin = saturate(lin + ping_xs * ping_gate * SPECULAR_PING * float3(1.04, 1.00, 0.92));
}
```

**Detection in pre-grade smooth space:** Both `ping_local` (1/16-res, `hal_blur`) and
`ping_broad` (1/32-res, `lf_mip2`) are spatially averaged textures — no per-pixel noise.
Comparing them finds local peaks at the 30px scale that don't persist at the 60px scale,
i.e. features narrower than ~30px. The lift still applies at full pixel resolution to `lin`.

Early revisions compared per-pixel `ping_L` against `ping_local`, which produced speckle
(game rendering noise amplified by the excess) and gradient banding at bloom edges. Moving
detection fully to smooth space eliminates both artefacts and removes the need for the
`ping_no_bloom` suppressor — game bloom spans >>60px so it cancels itself across both
scales; genuine specular highlights (<30px) do not.

**Knob:** `SPECULAR_PING` in `creative_values.fx`. Default 1.0. Range 0 (off) to ~2.0
(aggressive sparkle on metallic surfaces). The per-pixel math is already modest so
1.0 is a real working default, not an artificial scale.

## GPU cost

Zero additional texture reads (hoist eliminates the duplicate). ~6 ALU ops per pixel,
all in the hot path of ColorTransformPS — negligible.

## Interaction with other effects

- **Halation (R105):** Complementary. Halation spreads the glow outward; pings sharpen
  the source point. Both can be active simultaneously.
- **Pro-Mist:** Also complementary — mist blurs bright areas into dark neighbours; pings
  lift the source. No interference.
- **Gamut/gclip:** Pings fire *after* gclip so the gamut clip cannot undo the lift.
  `saturate()` is the only ceiling — correct for SDR.
- **Dither (R89):** Pings fire before dither, so the quantization noise still dithers
  the ping contribution. Correct order.
