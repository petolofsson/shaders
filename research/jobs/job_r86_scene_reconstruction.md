## Job D — R86 Scene Reconstruction Research

**Schedule:** 4× per day (07, 07+6h, 07+12h, 07+18h)
**Output:** `/home/pol/code/shaders/research/R86/run{n:02d}_{YYYY-MM-DD}_angle{a}_{angle_name}.md`
where `{n}` = number of existing files in `research/R86/` + 1 (after checking out alpha),
`{a}` = angle number (0/1/2), `{angle_name}` = inverse / hue_correction / fingerprinting.

Compute run number after checking out alpha:
`git -C /home/pol/code/shaders fetch origin alpha && git -C /home/pol/code/shaders checkout alpha && git -C /home/pol/code/shaders pull origin alpha`
then: `ls /home/pol/code/shaders/research/R86/run*.md 2>/dev/null | wc -l`  → add 1.
**Branch:** commit and push output file to `alpha`.
**Do not modify any source files.**

---

### Context — read these first

1. `/home/pol/code/shaders/CLAUDE.md` — pipeline constraints and philosophy
2. `/home/pol/code/shaders/PLAN.md` — R86 full description (Scene Reconstruction Research Track section)
3. `/home/pol/code/shaders/unused/general/inverse-grade/inverse_grade.fx` — existing blind inverse; the baseline to beat
4. `/home/pol/code/shaders/general/grade/grade.fx` — MegaPass: Stage 0 is where R86 hooks in
5. `/home/pol/code/shaders/general/corrective/corrective.fx` — available analysis data (PercTex, ZoneHistoryTex)

---

### Background

**The pipeline is game-agnostic.** Different games apply different tone mappers before
vkBasalt sees the frame — or none at all. R86 must never assume ACES is present.
The design requirement is:

> Detect which tone mapper (if any) was applied from display-referred statistics already
> available in PercTex / CreativeZoneHistTex. Apply the appropriate per-pixel inverse
> only when confidence is high. Fall back to identity when the tone mapper cannot be
> identified. The result must be perceptually neutral on games that do not use ACES.

Arc Raiders (UE5) is the primary test platform because it is known to apply the Hill 2016
ACES rational function. GZW (Grey Zone Warfare) uses a different pipeline and must
pass through R86 unchanged.

**The UE5 ACES approximation (Hill 2016) is a rational function:**
```
f(x) = (2.51x² + 0.03x) / (2.43x² + 0.59x + 0.14)
```
The analytical inverse is derivable via the quadratic formula. The hue distortions
(red/magenta → orange push, cyan → blue, yellow highlight desaturation) are measurable
deviations from a neutral Oklab hue trajectory.

**Other common tone mappers to be aware of:**
- Reinhard: `x / (x + 1)` — monotone, no hue distortion, lighter shoulder than ACES
- Hable/Uncharted2: piecewise rational, similar shoulder to ACES but different coefficients
- AgX (Blender/modern UE5 option): perceptually uniform, very different histogram signature
- Linear / no TMO: passthrough — p75/p50 ratio close to 1.0

**Three research angles to cover in each run — rotate focus across runs:**

| Run mod 3 | Focus |
|-----------|-------|
| 0 | Inverse tone mapping literature — HDR reconstruction from SDR |
| 1 | ACES hue distortion characterisation and correction methods |
| 2 | Tone mapper identification / fingerprinting from scene statistics |

**All angles must keep the game-agnostic constraint in view.** Angle 2 (fingerprinting)
is the prerequisite that makes angles 0 and 1 safe to deploy across games.

Determine which angle to take: `(current_hour // 6) % 3`.

---

### Task

#### Step 1 — Read context
Read all five files listed above. Note the R86 description in PLAN.md carefully —
especially the analytical inverse derivation, risk factors, and scope constraints.

#### Step 2 — Determine research angle
Compute `(current_hour // 6) % 3` to select the focus for this run.

#### Step 3 — Search (5–8 queries minimum)

**Session (CronCreate):** use `mcp__brave-search__brave_web_search` tool directly for all queries.
**RemoteTrigger (Routine):** use curl with `X-Subscription-Token: BSACEZYg3d8q_TVrE-KKqerTXe-h1nA`.

**Angle 0 — Inverse tone mapping / HDR reconstruction:**
- `"inverse tone mapping" "ACES" analytical closed-form 2022 2023 2024 2025`
- `"SDR to HDR" "tone curve inversion" real-time display 2024 2025`
- `"inverse tone mapping operator" rational function approximation GPU`
- `"HDR reconstruction" "single exposure" neural OR analytical 2024 2025`
- arxiv: `"tone mapping inversion" perceptual quality evaluation`

**Angle 1 — ACES hue distortion characterisation:**
- `"ACES" "hue shift" "chromatic distortion" film emulation analysis`
- `"ACES Filmic" "red desaturation" "hue rotation" perceptual evaluation`
- `"Oklab" OR "ICtCp" ACES hue error correction display referred 2023 2024 2025`
- `"gamut mapping" "hue linearity" ACES compensation`
- arxiv: `"color appearance" "tone mapping" hue shift correction observer study`

**Angle 2 — Tone mapper identification / fingerprinting:**
- `"tone mapping operator identification" scene statistics signature 2022 2023 2024`
- `"blind inverse tone mapping" parameter estimation from luminance distribution`
- `"HDR image reconstruction" "single image" tone curve fitting 2024 2025`
- `"display referred" luminance histogram fingerprint tone operator classification`
- arxiv: `"inverse problem" tone mapping operator unknown recovery`

For all angles, also search:
- `site:arxiv.org "inverse tone mapping"` (recent, no paywall)
- ACM SIGGRAPH / SIGGRAPH Asia proceedings for analytical ACES inversion or hue correction

#### Step 4 — Assess each finding

For each paper or technique found:
1. **Which R86 sub-problem does it address?** (inverse derivation / hue correction / fingerprinting)
2. **Mathematical approach** — analytical, neural, statistical, or hybrid?
3. **GPU feasibility** — can it run per-pixel in a single pass? Estimated ALU cost?
4. **Error bounds** — what is the maximum luminance or hue error vs. a true inverse?
5. **Novelty gap** — does this paper apply to real-time display shaders, or only offline VFX?
6. **Directly usable?** — can the method be adapted to HLSL within CLAUDE.md constraints?

Flag anything that provides a **closed-form per-pixel inverse or hue correction** as
**HIGH PRIORITY** — these are immediately actionable without new passes or textures.

#### Step 5 — Prototype derivation (if angle = 0 or 1)

If the run angle is 0 (inverse) or 1 (hue correction), attempt to sketch the HLSL
implementation based on findings:

**Angle 0 prototype sketch:**
Derive the quadratic inverse of `f(x) = (2.51x²+0.03x) / (2.43x²+0.59x+0.14)`:
- Rearrange to `(2.43y - 2.51)x² + (0.59y - 0.03)x + 0.14y = 0`
- Solve with quadratic formula, taking the positive root
- Validate: compute forward(inverse(x)) for x = 0.01, 0.1, 0.3, 0.5, 0.7, 0.9, 0.99
- Note any domain where the inverse is undefined or numerically unstable

**Angle 1 prototype sketch:**
From the literature, list the primary ACES hue distortions with their approximate magnitude
in degrees (Oklab hue) and at what luminance/chroma they peak. Propose per-hue Oklab LCh
correction offsets, following the same structure as the existing `ROT_*` knobs in grade.fx.

#### Step 6 — Write output

---

### Output format

```markdown
# R86 Scene Reconstruction — Run {n:02d} — {angle name} — {YYYY-MM-DD HH:MM}

## Run angle
{which angle was selected and why}

## HIGH PRIORITY findings
{Closed-form methods only. Empty if none this run.}

## Findings

### [{Paper / technique title}]
- **R86 sub-problem:** {inverse / hue correction / fingerprinting}
- **Approach:** {analytical / neural / statistical}
- **GPU feasibility:** {per-pixel single-pass? ALU estimate?}
- **Error bounds:** {max luminance or hue error}
- **Novelty gap:** {offline VFX only, or adaptable to real-time?}
- **Directly usable:** {yes / with modifications / no — reason}
- **Search that found it:** {exact query}

### [...]

## Prototype sketch
{Only for angle 0 or 1 — HLSL derivation or hue offset table}

## Implementation gaps remaining
{What is still unknown after this run — guides the next run's angle selection}

## Searches run
{all queries used}
```

---

### After writing the output file

```bash
cd /home/pol/code/shaders
git fetch origin alpha
git checkout alpha
git pull origin alpha
git add research/R86/run*.md
git commit -m "nightly: R86 scene reconstruction run{n:02d} angle{a} {YYYY-MM-DD}"
git push origin alpha
```
