# GZW Shader Stack

A cinematic post-processing stack for **Gray Zone Warfare** on Linux (vkBasalt) and Windows (ReShade).

Designed by Peter Olofsson — photographer, photojournalist, film fan. The aesthetic choices (Kodak Vision3 halation, filmic toe, indigo shadow tint, warm/cool foliage split) come from that background, not shader programmer defaults.

## Shader chain

```
OlofssonianZoneContrast → ColorGrade → Halation → FoliageLight → Promist → Veil → Sharpen → CA → Vignette
```

| Shader | What it does |
|--------|-------------|
| **OlofssonianZoneContrast** | Scene-adaptive contrast via per-frame Halton sampling + percentile-pivoted S-curves |
| **ColorGrade** | Warm/cool foliage split, film matrix, sky saturation, ivory white point |
| **Halation** | Kodak Vision3-style red-amber bleed around light sources |
| **FoliageLight** | Warm bloom + silver rim on lit leaf edges |
| **Promist** | Atmospheric diffuse softening + sun scatter |
| **Veil** | Humid atmospheric haze, mid-distance tree blending |
| **Sharpen** | Adaptive unsharp mask — luma, contrast, and saturation gated |
| **CA** | Luma-weighted radial chromatic aberration |
| **Vignette** | Subtle corner darkening |

## Installation

See [docs/INSTALL.md](docs/INSTALL.md) for full setup instructions on Linux and Windows.

**Critical:** GZW HDR must be **OFF**. The stack is tuned for SDR [0–1].

## Notes

- Toggle on/off: **Home key**
- NVG is clean — all blur/bloom paths have built-in NVG gates
- Performance: ~0.5–1.5ms at 1440p on a mid-range GPU

## OlofssonianZoneContrast

The contrast shader is maintained as a standalone general-purpose shader:  
→ [github.com/petolofsson/olofssonian-zone-contrast](https://github.com/petolofsson/olofssonian-zone-contrast)

It is included here as a git submodule. To update it:

```bash
git submodule update --remote
```

## Version

See [VERSION](VERSION) for full changelog.
