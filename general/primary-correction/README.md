# Primary Correction

Input normalization — first shader in the chain. Applies white balance and exposure before any other processing.

## What it does

Multiplies scene RGB by per-channel white balance scalars and an exposure gain derived from a stops-based offset:

    c = col.rgb × WB × pow(2.0, -0.13 + EXPOSURE/100.0)

The -0.13 stop bake means `EXPOSURE=0` matches the raw game output exactly. Positive values brighten, negative darken.

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WB_R` | 100 | Red white balance (100 = neutral) |
| `WB_G` | 100 | Green white balance |
| `WB_B` | 100 | Blue white balance |
| `EXPOSURE` | -40 | Exposure offset in 1/100-stop units (±100 = ±1 stop) |

## Chain position

Must be first in the chain. All downstream shaders assume linear-light input.

    primary_correction → frame_analysis → …

## Debug indicator

White pixel block at x:2474–2486, y:15–27.
