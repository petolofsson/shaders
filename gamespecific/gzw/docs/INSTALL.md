# GZW Shader Stack — Installation Guide

A cinematic post-processing stack for Gray Zone Warfare.  
Chain: `olofssonian_zone_contrast → color_grade → halation → foliage_light → promist → veil → sharpen → ca → vignette`

---

## Before you start

- **HDR must be OFF** in GZW graphics settings. The stack is tuned for SDR [0–1]. HDR will break all color work.
- Toggle shaders on/off in-game: **Home key**

---

## Linux (vkBasalt)

### 1. Install vkBasalt

**Arch / CachyOS / Manjaro (AUR):**
```bash
yay -S vkbasalt
```

**Fedora:**
```bash
sudo dnf install vkBasalt
```

**Ubuntu / Debian:**
```bash
sudo apt install vkbasalt
```

**Manual (from source):**  
See https://github.com/DadSchoorse/vkBasalt

### 2. Copy shader files

Copy the entire `shaders/` folder to:
```
~/.config/vkbasalt/shaders/
```

### 3. Copy config

Copy `gzw.conf` to:
```
~/.config/vkbasalt/gzw.conf
```

### 4. Launch the game

**Steam:** In GZW launch options, add:
```
ENABLE_VKBASALT=1 VKBASALT_CONFIG_FILE=~/.config/vkbasalt/gzw.conf %command%
```

**Lutris / Heroic:** Add the same environment variables in the game's environment settings.

### 5. In-game

- Press **Home** to toggle the stack on/off
- HDR must be OFF in GZW settings

---

## Windows (ReShade)

vkBasalt is Linux-only. On Windows, the shaders run via **ReShade**, which uses the same .fx shader format.

### 1. Install ReShade

1. Download ReShade from **https://reshade.me**
2. Run the installer
3. Click **Browse** and navigate to the GZW executable:  
   `...\Gray Zone Warfare\Binaries\Win64\GrayZoneWarfare-Win64-Shipping.exe`
4. Select **Vulkan** as the rendering API
5. When asked about shader packages — click **Skip** (you will install these manually)

### 2. Copy shader files

Copy all `.fx` files from the `shaders/` folder into ReShade's shader directory:
```
...\Gray Zone Warfare\reshade-shaders\Shaders\
```

If the `reshade-shaders\Shaders\` folder does not exist, create it.

### 3. Enable the shaders in-game

1. Launch GZW
2. Press **Home** to open the ReShade overlay
3. Go to the **Home** tab — you will see all installed techniques listed
4. Enable them in this exact order (order matters):

| # | Technique |
|---|-----------|
| 1 | `OlofssonianZoneContrast` |
| 2 | `ColorGrade` |
| 3 | `Halation` |
| 4 | `FoliageLight` |
| 5 | `Promist` |
| 6 | `Veil` |
| 7 | `Sharpen` |
| 8 | `CA` |
| 9 | `Vignette` |

5. Close the overlay — press **Home** again

> **Tip:** You can drag techniques in the ReShade UI to reorder them. The order above is critical — changing it will break the look.

### 4. In-game

- Press **Home** to toggle the ReShade overlay
- Press **End** (default) to toggle all effects on/off
- HDR must be OFF in GZW settings

---

## Troubleshooting

**Black screen / corrupted image:**  
HDR is likely ON. Disable it in GZW graphics settings.

**Shaders not appearing (Windows):**  
Make sure the .fx files are in `reshade-shaders\Shaders\` and that ReShade was installed for the correct executable and API (Vulkan).

**Wrong colors / look doesn't match:**  
Techniques are enabled in the wrong order. Reorder them as listed above.

**NVG looks wrong:**  
The stack has built-in NVG gates. If NVG appears affected, confirm HDR is off and technique order is correct.

**Performance:**  
The stack adds approximately 0.5–1.5ms at 1440p on a mid-range GPU. olofssonian_zone_contrast is the most expensive pass (history buffer + percentile sampling). All other passes are single-sample or half-res.
