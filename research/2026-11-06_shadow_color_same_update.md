# Half-color candidate: same-update GPU comparison

**Limited positive evidence for the color mechanism, not adoption.** The existing half-strength bounded-color candidate changes selected shelf/metal color-group separation before screenshot quantization. Its selected brightness response remains tiny and mixed. Four sparse patches have exact encoded repeats and no new measured continuous input-relative brightness reversals. These results do not erase earlier full-region screenshot costs or establish a user-visible combined color/brightness improvement.

## Diagnostic

In a private isolated combined technique, a diagnostic pass immediately before ordinary grade reads post-inverse input and evaluates mechanically cloned production and half-color transforms in the same invocation. Both stop before dither/encoding. Their only body difference is exactly the preserved half-color insertion from the earlier screen, parsed as data without executing its capture script. They read the same UV and current scene/history state. The ordinary pipeline remains the current grade; this is a cloned candidate calculation in that state, not a naturally evolving candidate-history or actual ordinary candidate-write readback.

Input and the two pre-dither outputs are stored in a 16×48 RGBA32F diagnostic surface, then encoded as nine 24-bit scalar values per sampled pixel after the normal passes. Sampling covers a 16×16 grid at exact native pixel centers within four 64×64 patches. Adjacent grid samples are four native pixels apart; this is sparse patch evidence, not full material or frame coverage.

Readback interval is [0,0.25], step approximately 1.49e-8. Samples at its ceiling are excluded, as are input-Y values ≤0.001. The shelf excludes 12 low-Y samples and window excludes 19 samples at the encoding ceiling. Ceiling observations cannot establish the original value, gamut safety or clipping. All encoded values repeat exactly in each patch. Input and baseline values match the earlier independent float-detail readback exactly at encoded resolution in all four patches; this is a useful clone/input sanity check, not direct comparison with the ordinary GPU write.

Eight fresh private headless processes report zero dropped/delayed frames, with 20-second settling. Production/profile/config hashes match the half-color epoch and remain unchanged. Snapshots and screenshots are checked against their hashes; saved arrays must decode exactly from those screenshots. Clone hashes, sources/clips/configs and log paths are in `captures/shadow_color_same_update_20261106/report.json`; numerical results/code are adjacent. No performance or temporal convergence claim follows.

## Selected response

For each horizontal/vertical adjacent grid pair, retain two valid samples with input log-Y gap 0.03–0.5 stops. The sign is defined by actual post-inverse input in the same invocation. Pairs overlap. Input response is a diagnostic reference, not an assertion that it defines the intended final appearance.

| Patch | Valid samples | Pairs | Mean signed float log-Y gap baseline → half color | New continuous reversals |
| --- | ---: | ---: | ---: | ---: |
| Shelf | 244 | 349 | 0.109880 → 0.109968 | 0 |
| Metal | 256 | 273 | 0.109922 → 0.109812 | 0 |
| Blue wall | 256 | 326 | 0.058678 → 0.058672 | 0 |
| Cool window | 237 | 299 | 0.145359 → 0.145353 | 0 |

Neither baseline nor candidate reverses any of these 1,247 measured float pairs. This does not prove all earlier reported reversals are quantization artifacts: those measurements use larger regions, different source selections and ordinary dithered screenshots. Here, simulated undithered 8-bit rounding produces one baseline reversal each on metal/window and none for candidate; simulated 16-bit has none in either. Simulated bit depths are not changes to game output.

The shelf's simulated 8-bit gap changes 0.111891→0.119346 and metal 0.098197→0.115715, substantially larger than their float changes. The wall simulated gap decreases 0.059384→0.055994 despite an almost unchanged float gap. This illustrates why quantized small effects need uncertainty bounds; it does not establish a new 8-bit brightness benefit.

Using input L 12–35 and input-b quartile groups, pre-dither a/b group distance ×100 changes 0.2479→0.3440 on shelf (224 samples) and 0.3530→0.3967 on metal (249). Groups may also differ in brightness; these are color-change quantities, not perceptual quality scores. The wall has no eligible group in that lightness range; the window has only 11 samples and is not substantive color evidence. Maximum full-chain luma changes in the valid samples range from 0.00000280 shelf to 0.00000998 window. The early correction's ideal zero-luma property does not mean the downstream chain preserves luma exactly.

## Remaining scope

This is not an independent CPU/GPU contract for every half-helper boundary, a saturation/headroom sweep, a dense near-black continuity/noise test, or measured motion/cut validation. The [source/input audit](2026-11-06_shadow_neutral_alignment.md) separately corrects the earlier inverse-color attribution and observes unchanged sparse exact-gray screenshots. Together these results support the existing color idea more precisely, but still leave subtle appearance, full-region quantization, warm-material and broader palette behavior to decide. No profile/shader adoption, actual-config activation, fresh rating or publication follows.
