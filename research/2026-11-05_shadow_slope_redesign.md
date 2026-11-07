# Shadow-curve slope redesign — 2026-11-05

**Decision: not adopted.** The redesign raises selected shelf and dark-metal visible quartile gaps but reduces selected cool-window, blue-wall and blue-field gaps. Within-material neighboring-shade gaps are nearly unchanged. The current evidence therefore does not establish a consistent improvement in shadow gradients. Production shader, profiles/configs and ratings remain unchanged.

The user authorized redesign before any adoption. In an isolated grade copy, the prior source-windowed response is replaced with a single corrected-luma mapping: `anchor=clamp(zone_key,0.02,0.04)`, `x=saturate(new_luma/anchor)`, and a positive `anchor*1.5*x²*(1-x)²` term gated by the existing contrast, zone and adaptation controls. It fixes black and the upper anchor and smoothly rejoins identity at both. A dense CPU scalar fixed-context grid gives derivative 0.71132–1.28868 and maximum lift 0.09375 anchor units. Because the mapping has unchanged endpoints, some compression is mathematically unavoidable; the design bounds that compression for this isolated scalar mapping. The adaptive anchor, existing tonal stages and Oklab reconstruction invalidate any claim of a global full-pipeline monotonicity proof. No additional textures or passes are added.

| Source-selected region | Current L gap | Candidate L gap | Observation |
|---|---:|---:|---|
| GZW shelf | 2.661 | 2.997 | median L rises 15.735→16.880 |
| Arc dark metal | 8.981 | 9.444 | median L rises 17.589→18.710 |
| GZW blue wall | 9.480 | 9.159 | reduction |
| Arc cool window | 31.973 | 30.550 | reduction |
| Arc cool upper | 20.385 | 20.223 | small reduction |
| GZW-profile vivid blue field | 27.390 | 26.853 | reduction |
| GZW-profile vivid sky | 10.567 | 10.564 | near unchanged |

L gaps compare fixed source-quartile groups and do not prove perceived quality. On source-selected neighboring pairs at 1/4/16-pixel offsets, GZW shelf mean signed log-Y gaps are 0.100760/0.115991/0.126915 current versus 0.100685/0.116555/0.127428 candidate; Arc metal is 0.113594/0.136975/0.156600 versus 0.112193/0.136614/0.157455. These fixed-source numbers suggest that the broad quartile improvement is substantially associated with lifting/redistribution rather than demonstrably improved fine gradient response. A larger gap by itself is not the objective; the candidate also changes intentional shadow brightness.

Four current-profile isolated candidate/repeat pairs cover GZW dark, Arc interior, Arc emitters and Arc vivid content under GZW settings. All four are pixel-identical with the marker masked; eight private headless processes reported zero dropped/delayed frames. Production hashes before/after match and isolated config/grade file hashes verify. Full-image maximum per-channel differences are 5/6/4/6 codes respectively; all-channel black count adds no pixels in these scenes, but that is not a near-black continuity contract. White-core and red-lamp selected L gaps are unchanged at displayed precision. 20-second static settling does not establish dense motion stability or complete convergence. Native crops and source/profile/config/capture identities are ignored local artifacts in `captures/shadow_slope_20261105/`.

No independent GPU numeric/zero-bypass contract, gradient/boundary charts, measured motion/cut, performance or actual-config adoption validation was performed. This is an early negative decision on the candidate, not a universal judgment of slope-bounded shadow curves. No automatic strength sweep follows. User has not reviewed a blind visual comparison.
