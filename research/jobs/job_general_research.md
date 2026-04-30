# Nightly Job C — Lateral Domain Research

**Schedule:** 04:00 daily (effective domain rotates weekly)
**Output:** `/home/pol/code/shaders/research/R{next}_{YYYY-MM-DD}_Lateral_{Domain}.md`
where `{next}` = one more than the highest R-number found in `ls research/R*.md`.
**Branch:** commit and push output to `alpha`.
**Do not modify any source files.**

---

## Principle

This job searches for improvements to the pipeline by looking in fields that have
nothing to do with shaders or games. The goal is cross-domain transplants — finding
solutions that are well-established in a foreign field but entirely absent from
real-time rendering.

**Two rules that must be followed:**

1. **Search the math, not the application.** Never search for "shader", "game", "HDR",
   "tone mapping", or "rendering". Search for the underlying mathematical problem —
   "recursive Bayesian estimation", "sparse signal recovery", "illumination separation",
   "optimal state smoothing". This surfaces work from fields that would never appear
   in a direct graphics search.

2. **Search in a foreign domain.** Each week rotates to a different field. The domain
   determines which databases and terminology to use — not the topic to search for.
   The topic is always one of the pipeline's core mathematical problems.

---

## Domain rotation

Determine the domain from the ISO week number of the current date (`week % 7`):

| week % 7 | Domain | Search databases |
|----------|--------|-----------------|
| 0 | Radio astronomy / interferometry | arxiv astro-ph, ADS |
| 1 | Seismic processing / geophysics | arxiv physics.geo-ph, SEG |
| 2 | Medical imaging (CT, MRI, retinal) | arxiv eess.IV, PubMed |
| 3 | Remote sensing / satellite imagery | arxiv eess.SP, IEEE TGRS |
| 4 | Telecommunications / signal comms | arxiv eess.SP, IEEE Trans Comms |
| 5 | Climate science / data assimilation | arxiv physics.ao-ph, AMS |
| 6 | Sonar / underwater acoustics | arxiv eess.AS, JASA |

---

## Pipeline mathematical problems

These are the core mathematical challenges in the pipeline. Each search run should
pick 2–3 and look for how the current domain has solved them:

| Problem | Current approach | Where in pipeline |
|---------|-----------------|------------------|
| State estimation / temporal filtering | Adaptive EMA (heuristic) | corrective.fx SmoothZoneLevels, UpdateHistory |
| Illumination/reflectance separation | Coarse 4×4 zone normalization | grade.fx R18 |
| Sparse scene sampling | 8×8 Halton grid | corrective.fx UpdateHistory, analysis_scope_pre |
| Multi-scale basis decomposition | 3-mip Laplacian residual | grade.fx Clarity |
| Local contrast / edge-preserving filter | Zone IQR S-curve | grade.fx Stage 2 |
| Optimal signal recovery | None — open problem | Future pass |

---

## Task

### Step 1 — Read context
Read:
1. `/home/pol/code/shaders/CLAUDE.md` — pipeline constraints
2. `/home/pol/code/shaders/research/HANDOFF.md` — current pipeline state
3. `/home/pol/code/shaders/general/grade/grade.fx` — MegaPass implementation
4. `/home/pol/code/shaders/general/corrective/corrective.fx` — analysis passes

### Step 2 — Determine domain
Compute the current ISO week number. Use `week % 7` to select the domain from the
table above.

### Step 3 — Search (4–6 queries minimum)

For each of 2–3 pipeline problems, run 2 searches:
- One using **domain-specific terminology** combined with the mathematical abstraction
- One using **pure mathematical terminology** with no domain anchor

Example (week=0, domain=radio astronomy, problem=state estimation):
- `"Kalman filter" "radio interferometry" real-time calibration 2023 2024 2025`
- `"recursive Bayesian estimation" "non-stationary signal" adaptive convergence`

Explicitly avoid: "shader", "game", "rendering", "tone mapping", "HDR", "OpenGL",
"Vulkan", "GPU". These terms narrow results to the obvious space.

### Step 4 — Assess findings

For each paper or technique found, assess:
1. **Which pipeline problem does it address?** (from the table above)
2. **What is the mathematical delta?** What does it do differently from the current approach?
3. **GPU cost?** Extra passes? Extra texture reads? Pure math change?
4. **ROI estimate:** Visual impact (Low/Medium/High) vs. implementation cost (Low/Medium/High)
5. **Novelty in gaming context:** Has this technique appeared in any real-time rendering work?

Flag anything with High visual impact + Low/Medium implementation cost as
**HIGH PRIORITY** — these should be noted prominently at the top of the output.

### Step 5 — Write output

---

## Output format

```markdown
# Lateral Research — {Domain} — {YYYY-MM-DD}

## Domain this week
{domain name and why it was selected}

## Pipeline problems targeted
{2–3 problems from the table, with brief rationale for choosing them}

## HIGH PRIORITY findings
{Only items with High visual impact + Low/Medium cost. Empty section if none.}

## Findings

### [{Paper/technique title}]
- **Pipeline target:** {which component}
- **Mathematical delta:** {what it does differently}
- **GPU cost:** {passes / taps / pure math}
- **ROI:** {Visual impact} / {Implementation cost}
- **Novelty:** {has this appeared in real-time rendering?}
- **Search that found it:** {the exact query used}

### [...]

## ROI table
| Finding | Visual impact | GPU cost | Recommended action |
|---------|--------------|----------|-------------------|
| ... | | | |

## Searches run
{list all queries used}
```

---

## After writing the output file

```bash
cd /home/pol/code/shaders
git checkout alpha
git add research/R*_*_Lateral_*.md
git commit -m "nightly: lateral research {Domain} {YYYY-MM-DD}"
git push origin alpha
```
