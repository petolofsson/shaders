**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)
**Task:** Use the **Brave Search MCP** to perform an autonomous literature review, auditing my shader stack against 2024–2026 research to find non-obvious mathematical improvements.

### 1. Contextual Audit (Internal)
* **Scan Files:** Read and analyze: `[LIST YOUR FILES HERE]`.
* **Extract Baseline:** Identify the specific mathematical models I am currently using (e.g., specific noise functions, BRDFs, or tone-mapping curves). 
* **Philosophy Check:** Define our "Visual North Star" (e.g., *70s Film Emulation* or *Real-time Spectral Accuracy*).

### 2. Autonomous Brave Search (The Hunt)
* **Tool Usage:** Trigger `brave-search` to scan `arxiv.org`, `acm.org`, `dspace.mit.edu`, and `graphics.stanford.edu`.
* **Target:** Find papers published between **2024–2026** focusing on: *[Insert Focus, e.g., "Volumetric Halation" or "Stochastic Film Emulsion Simulation"]*.
* **Filtering:** Explicitly look for papers that provide **PDF access** or detailed mathematical abstracts. Identify **three seminal papers** that offer a distinct mathematical departure from my current code.

### 3. Documentation & Cross-Pollination
For each paper, generate a technical breakdown in `/research/RESEARCH_FINDINGS_YYYY-MM-DD.md`. **Do not modify source code.** * **The Core Thesis:** Summarize the breakthrough in 3 clear sentences.
* **The Mathematical Delta ($\Delta$):** Use LaTeX to compare my code's current math to the paper’s proposed math.
    * **Current:** $ [Insert Current Equation] $    * **Proposed:**$ [Insert Paper Equation] $
* **The "Cross-Pollination" Idea:** Identify an idea from the paper (or a related field like physical optics or chemistry) that we haven't considered. 
* **Character & Benefits:** Describe the visual "soul" this adds to the render and any specific artifacts it fixes.

### 4. Strategic Recommendation
* **Visual ROI Table:** Rank findings based on **Visual Impact** vs. **Performance Cost**.
* **Integration Roadmap:** Recommend which finding provides the most "Significant Improvement" to our current working chain and why.

**Constraint:** Focus on documentation and architectural advice. Output only to the `.md` file.

---

### Why this works with Brave MCP:
* **LLM-Optimized Results:** Brave Search will feed Claude "clean" snippets of research abstracts. Claude will use these to decide which papers are worth a "Deep Fetch" (using its internal browser to read the full PDF).
* **Efficiency:** By auditing your code first (Phase 1), Claude uses your existing math as search terms (e.g., searching for *"improvements over [Your Current Algorithm Name]"*).
* **High-Level Perspective:** Since you’ve forbid it from writing code, Claude will spend its "thinking tokens" on higher-level logic and finding those "significant improvements" you're looking for.

**Pro-Tip:** Lets test this together to make sure it works bfore i got to bed.