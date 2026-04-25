# How To Use — ColorGrade

## Requirements

### GPU compatibility

| Platform | Minimum |
|----------|---------|
| NVIDIA | GTX 900 series or newer (Maxwell) |
| AMD | RX 400 series or newer (GCN 4 / Polaris) |
| Intel | Arc A-series (discrete) or Iris Xe |

ColorGrade is a single pixel shader pass with no compute, no history buffer, and no multi-pass dependency. Any GPU that can run a modern game can run this shader. The requirements above are effectively the floor for Vulkan support.

---

## Windows — ReShade

### 1. Install ReShade

Download the installer from [reshade.me](https://reshade.me). Run it, select your game executable, and choose the correct rendering API (usually **DirectX 11** or **Vulkan** — check your game's documentation if unsure). When asked about shader packages, click **Skip**.

### 2. Install the shader

Copy `olofssonian_color_grade.fx` into your ReShade shaders directory:

```
<game folder>\reshade-shaders\Shaders\olofssonian_color_grade.fx
```

If the `reshade-shaders\Shaders\` folder does not exist, create it.

### 3. Enable in-game

Launch the game and press **Home** to open the ReShade overlay. Find `ColorGrade` in the technique list and check the box to enable it. Close the overlay.

### 4. Select a film preset

Open `olofssonian_color_grade.fx` in a text editor. In the `// ─── Film preset ───` section, uncomment the preset you want and comment out the others. Save the file — ReShade will reload it automatically if live-reload is enabled, or on next launch otherwise.

---

## Linux — vkBasalt

vkBasalt injects post-processing into Vulkan games without modifying game files.

### 1. Install vkBasalt

**Arch / CachyOS / Manjaro:**
```bash
yay -S vkbasalt
```
Or with pacman if it is in your repos:
```bash
sudo pacman -S vkbasalt
```

**Ubuntu 22.04+ / Debian 12+:**
```bash
sudo apt install vkbasalt
```
On older releases the package may not be available — build from source (see below).

**Fedora:**
```bash
sudo dnf install vkBasalt
```

**openSUSE:**
```bash
sudo zypper install vkBasalt
```

**From source (any distro):**
```bash
git clone https://github.com/DadSchoorse/vkBasalt
cd vkBasalt
meson setup build
ninja -C build
sudo ninja -C build install
```

### 2. Create a config file

Create `~/.config/vkbasalt/color_grade.conf`:

```ini
enableOnLaunch = True
toggleKey = Home

reshadeIncludePath = /path/to/color-grade
color_grade = /path/to/color-grade/olofssonian_color_grade.fx

effects = color_grade
```

Replace `/path/to/color-grade` with the actual path to this folder.

### 3. Launch your game

**Steam:** Add to the game's launch options:
```
ENABLE_VKBASALT=1 VKBASALT_CONFIG_FILE=~/.config/vkbasalt/color_grade.conf %command%
```

**Lutris / Heroic:** Add the same two environment variables in the game's environment settings panel.

**Command line:**
```bash
ENABLE_VKBASALT=1 VKBASALT_CONFIG_FILE=~/.config/vkbasalt/color_grade.conf %command%
```

Press **Home** in-game to toggle the effect on and off.

### 4. Select a film preset

Open `olofssonian_color_grade.fx`. In the `// ─── Film preset ───` section, uncomment the preset you want and comment out the others. Changes take effect on next game launch.

---

## Choosing a preset

| If you want | Use |
|-------------|-----|
| A safe, broadly cinematic starting point | Kodak Vision3 500T *(default)* |
| Cleaner and cooler, less pushed | Kodak Vision3 200T |
| Green-leaning, literary, quiet | Fuji Eterna 500 |
| High contrast, punchy, thriller aesthetic | Kodak 5219 |
| Maximum saturation, slide-film pop | Fuji Velvia 50 |

Start with the default and compare it to the others before tuning individual parameters.

---

## Tuning

All parameters are `#define` values at the top of the shader. Change a value, save, and reload.

The most impactful parameters to start with:

- `SAT_GREEN` / `SAT_SKY` — how much foliage and sky are pushed. 1.0 = no change, 1.30 = aggressive.
- `BLACK_POINT` — shadow floor. Higher values lift blacks further from zero.
- `SAT_BLEND` — gamut compression intensity. Higher values compress over-saturated colors more.

The film preset values (white point, matrix) are intentionally left as `#define` blocks rather than individual parameters — swapping a preset changes multiple values that work together as a unit.

---

## Troubleshooting

**Shaders stop working after a system update (Linux)**

After a Mesa or Vulkan driver update, the GPU shader cache can contain stale compiled pipelines that are incompatible with the new driver. Clear it before relaunching:

```bash
rm -rf ~/.cache/mesa_shader_cache/*
```

Then relaunch the game. The cache will be rebuilt fresh on the next run.
