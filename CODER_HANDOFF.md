# Shader Stack — Coder Handoff

Last updated: April 18 2026.

---

## Repository layout

```
/home/pol/code/shaders/
├── general/
│   ├── olofssonian-zone-contrast/    # Stable luma contrast — git repo
│   ├── olofssonian-chroma-lift/      # Stable chroma lift — no git
│   ├── color-grade/                  # Stable + alpha film grade — no git
│   ├── primary-correction/           # Alpha: input normalization
│   ├── frame-analysis/               # Alpha: histogram builder
│   ├── youvan-orthonorm/             # Alpha: color cast removal (Youvan 2024)
│   ├── alpha-zone-contrast/          # Alpha: CDF luma contrast
│   ├── alpha-chroma-contrast/        # Alpha: per-band CDF chroma contrast
│   ├── pro-mist/                     # Alpha: Pro-Mist highlight diffusion
│   ├── output-transform/             # Alpha: tonal range + gamut compression
│   └── film-grain/                   # Alpha: luminance-weighted grain
└── gamespecific/
    ├── gzw/                          # Gray Zone Warfare (stable chain)
    ├── arc_raiders/                  # Arc Raiders (alpha chain active)
    ├── cs2/                          # Counter-Strike 2 (stable chain)
    └── ready_or_not/                 # Ready or Not (stable chain)
```

---

## Active pipelines

**Stable** (gzw, cs2, ready_or_not):
```
zone_contrast → chroma_lift → color_grade
```

**Alpha** (arc_raiders):
```
primary_correction → frame_analysis → youvan → alpha_zone → alpha_chroma
    → color_grade → pro_mist → output_transform → film_grain
```

Full 8-step professional pipeline from notes_from_coder.md — all steps wired.

---

## Shader summaries

### olofssonian_zone_contrast.fx
- **Path**: `general/olofssonian-zone-contrast/olofssonian_zone_contrast.fx`
- **Git**: yes — own repo, tagged `stable-working`
- **What it does**: Adaptive luma contrast. Two-pass. Pass 1: 128 Halton(2,3) samples (sliding window via FRAME_COUNT % 128), bitonic sort, extracts median into HistoryTex. Pass 2: `PivotedSCurve(col.rgb, median, CURVE_STRENGTH)`.
- **Key tuning**: `CURVE_STRENGTH 0.30`, `LERP_SPEED 0.08`
- **Debug box**: green at x:2519–2531, y:15–27

### olofssonian_chroma_lift.fx
- **Path**: `general/olofssonian-chroma-lift/olofssonian_chroma_lift.fx`
- **Git**: no
- **What it does**: Adaptive saturation contrast. Two-pass. Pass 1: 64 Halton samples/frame, per-band weighted mean+stddev (E[x²]-E[x]²). Pass 2: per-band `PivotedSCurve(hsv.y, mean, CURVE_STRENGTH)`. 6 hue bands, smooth overlap. Green 4° cool-shift.
- **Key tuning**: `CURVE_STRENGTH 0.40`, `LERP_SPEED 0.08`, `BAND_WIDTH 0.15`
- **Debug box**: red at x:2504–2516, y:15–27

### olofssonian_color_grade.fx
- **Path**: `general/color-grade/olofssonian_color_grade.fx`
- **Git**: no
- **What it does**: Creative film/camera grade. Toe tint (indigo bell), black lift (navy), shadow tint, highlight warm lift, luma-neutral midtone cast, film print matrix. `GRADE_STRENGTH` lerps bypass → full (>1.0 = overdrive).
- **Presets**: `PRESET 1` = Kodak Vision3 500T (active), 2=ARRI ALEXA, 3=Sony Venice, 4=Fuji Eterna 500, 5=Kodak 5219
- **Key tuning**: `GRADE_STRENGTH 1.0`, `TOE_RANGE 0.30`, `SHADOW_RANGE 0.18`, `HIGHLIGHT_START 0.65`
- **Debug box**: blue at x:2534–2546, y:15–27

### primary_correction.fx
- **Path**: `general/primary-correction/primary_correction.fx`
- **What it does**: White balance (WB_R/G/B) + exposure (stops). De-gamma **bypassed** — all downstream shaders tuned for gamma space.
- **Key tuning**: `WB_R/G/B 1.00`, `EXPOSURE 0.00`
- **Debug box**: yellow at x:2474–2486, y:15–27
- **TODO (future)**: Re-enable `pow(x, 2.2)` once all downstream shaders are retuned for linear space. Add inverse tone mapping.

### frame_analysis.fx
- **Path**: `general/frame-analysis/frame_analysis.fx`
- **What it does**: 6-pass histogram builder. Downsample 32×18 → luma histogram (64-bin R32F → LumHistTex) → per-hue saturation histogram (64×6 R32F → SatHistTex) → temporal smooth both. pow(2.2) linearization before binning.
- **Shared textures**: LumHistTex, SatHistTex — re-declared identically in alpha_zone and alpha_chroma.
- **Debug box**: magenta at x:2489–2501, y:15–27

### youvan_orthonorm.fx
- **Path**: `general/youvan-orthonorm/youvan_orthonorm.fx`
- **What it does**: Dynamic color cast removal (Youvan 2024). Three-pass. Pass 1: 64 Halton samples classified into dark/mid/bright luma zones → mean RGB per zone in ZoneTex (temporal lerp). Pass 2: builds 3×3 correction matrix B = M × A⁻¹ (3 pixels only — near-zero cost). Pass 3: applies `lerp(input, B × input, ORTHO_STRENGTH)`.
- **Key tuning**: `ORTHO_STRENGTH 0.60`, `LERP_SPEED 0.05`
- **Debug box**: cyan at x:2459–2471, y:15–27
- **Effect**: maps zone-mean colors to neutral grays at their own luma — removes blue shadows, warm highlights, cross-channel bleed.

### alpha_zone_contrast.fx
- **Path**: `general/alpha-zone-contrast/alpha_zone_contrast.fx`
- **What it does**: CDF-driven luma contrast. Pass 1 (BuildCDF): prefix sum of LumHistTex → smoothed CDF LUT in LumCDFTex. Pass 2: `new_luma = lerp(luma, CDF(luma), CURVE_STRENGTH)`, RGB scaled by new_luma/luma (hue+sat preserved).
- **Key tuning**: `CURVE_STRENGTH 0.30`, `LERP_SPEED 0.08`
- **Debug box**: green at x:2519–2531, y:15–27

### alpha_chroma_contrast.fx
- **Path**: `general/alpha-chroma-contrast/alpha_chroma_contrast.fx`
- **What it does**: Per-band CDF-driven saturation contrast. Pass 1 (BuildSatCDF): per-band prefix sum of SatHistTex rows → smoothed 64×6 CDF LUT in SatCDFTex. Pass 2: per-band `lerp(sat, CDF_band(sat), CURVE_STRENGTH)`, hue-weighted blend, green 4° cool-shift.
- **Key tuning**: `CURVE_STRENGTH 0.45`, `LERP_SPEED 0.08`, `BAND_WIDTH 0.15`, `SAT_THRESHOLD 0.05`
- **Debug box**: red at x:2504–2516, y:15–27

### pro_mist.fx
- **Path**: `general/pro-mist/pro_mist.fx`
- **What it does**: Black Pro-Mist optical filter. Pass 1: horizontal 13-tap Gaussian (8px step) → BlurTex. Pass 2: vertical 13-tap Gaussian on BlurTex, screen-blended over original gated by highlight luma mask: `result = orig + glow - orig*glow`.
- **Key tuning**: `MIST_STRENGTH 0.18`, `HIGHLIGHT_START 0.55`, `HIGHLIGHT_PEAK 0.85`
- **Debug box**: white at x:2444–2456, y:15–27

### output_transform.fx
- **Path**: `general/output-transform/output_transform.fx`
- **What it does**: Tonal range (`result * (WHITE_POINT - BLACK_POINT) + BLACK_POINT`), gamut compression (luma-based soft clip + saturation excess clamp). Re-gamma **bypassed** — same reason as primary_correction de-gamma bypass.
- **Key tuning**: `BLACK_POINT 0.035`, `WHITE_POINT 0.97`, `SAT_MAX 0.85`, `SAT_BLEND 0.15`
- **Debug box**: orange at x:2549–2561, y:15–27
- **TODO (future)**: Re-enable `pow(x, 1/2.2)` when primary_correction de-gamma is active. Replace with proper DRT (OpenDRT/ACES).

### film_grain.fx
- **Path**: `general/film-grain/film_grain.fx`
- **What it does**: Luminance-weighted grain. Hash-based noise, frame-animated via FRAME_COUNT. Weight = `4*luma*(1-luma)` — peaks at mid-tone, zero at black/white. Hides 8-bit banding from grade chain.
- **Key tuning**: `GRAIN_STRENGTH 0.035`, `GRAIN_SIZE 1.0`
- **Debug box**: gray at x:2429–2441, y:15–27

---

## Debug box reference

All at y:15–27, top-right of 2560px-wide frame. Missing box = compile fail or not in chain.

| Shader                    | Color                    | x range   | Chain position |
|---------------------------|--------------------------|-----------|----------------|
| film_grain                | very dark purple (0.057) | 2429–2441 | 8 — last       |
| pro_mist                  | dark blue (0.136)        | 2444–2456 | 6b             |
| youvan_orthonorm          | mint green (0.630)       | 2459–2471 | 3              |
| primary_correction        | white (1.000)            | 2474–2486 | 1 — first      |
| frame_analysis            | golden yellow (0.892)    | 2489–2501 | 2              |
| olofssonian_chroma_lift / alpha_chroma | orange-red (0.413) | 2504–2516 | 5   |
| olofssonian_zone_contrast / alpha_zone | teal (0.552)       | 2519–2531 | 4   |
| olofssonian_color_grade   | cornflower blue (0.251)  | 2534–2546 | 6a             |
| output_transform          | dark maroon (0.096)      | 2549–2561 | 7              |

Colors are perceptually ordered by luma (values in parentheses): step 1 = brightest, step 8 = darkest.
Step 6 (Look) has two shaders sharing the blue hue: color_grade (brighter 6a) and pro_mist (darker 6b).

---

## Known compile constraints (vkBasalt/HLSL)

- No `[unroll]` on loops calling RGBtoHSV or bitonic sort — instruction limit. Use `[loop]` or bare loop.
- `tex2Dlod` required for sampling in render-target passes (not `tex2D`).
- `static const` arrays at file scope only — not inside functions.
- No `discard` in render-target passes — use `return float4(0,0,0,0)`.
- No ternary inside hot loops — use branchless `smoothstep * flag + fallback * (1-flag)`.
- `uniform int FRAME_COUNT < source = "framecount"; >` must be declared explicitly.

---

## Config files

**Arc Raiders** (`gamespecific/arc_raiders/arc_raiders.conf`):
```
#effects = zone_contrast:chroma_lift:color_grade   ← stable
effects = primary_correction:frame_analysis:youvan:alpha_zone:alpha_chroma:color_grade:pro_mist:output_transform:film_grain
```

**All other games** (gzw, cs2, ready_or_not):
```
effects = zone_contrast:chroma_lift:color_grade
```

---

## Pending work (future — all blocked on linear pipeline switch)

1. **Linear pipeline activation**: re-enable `pow(2.2)` in primary_correction + `pow(1/2.2)` in output_transform simultaneously. All thresholds in youvan/alpha_zone/alpha_chroma/color_grade will need re-tuning for linear-space values.
2. **Inverse tone mapping** in primary_correction — recover highlight energy compressed by game's tone mapper.
3. **Proper DRT** in output_transform — replace simple re-gamma with OpenDRT or ACES RRT+ODT.
4. **GZW**: stable chain only. Game-specific shaders (halation, foliage, promist, veil, sharpen, ca, vignette) remain unchanged after color_grade.
