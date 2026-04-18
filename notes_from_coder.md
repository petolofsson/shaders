# Notes from Coder.

I asked Claude about our road map:

  ┌───────────────────────────┬───────────────────────────────────────────────────────┐
  │     Professional step     │                      Our shader                       │
  ├───────────────────────────┼───────────────────────────────────────────────────────┤
  │ 1. Input normalization    │ primary_correction — de-gamma, linearize              │
  ├───────────────────────────┼───────────────────────────────────────────────────────┤
  │ 2. Scene-referred grading │ alpha_zone_contrast + alpha_chroma_contrast           │
  ├───────────────────────────┼───────────────────────────────────────────────────────┤
  │ 3. Look creation          │ color_grade                                           │
  ├───────────────────────────┼───────────────────────────────────────────────────────┤
  │ 4. DRT                    │ output_transform — tone map, re-gamma, gamut compress │
  ├───────────────────────────┼───────────────────────────────────────────────────────┤
  │ 5. Output                 │ display                                               │
  └───────────────────────────┴───────────────────────────────────────────────────────┘


**Here is what he answered.**

Got it. That table is your Internal Roadmap. Since your alpha_ shaders are already doing the heavy lifting in Step 2, you don't need to replace them—you just need to "feed" them better data.

Here is how the Dynamic Orthonormalization from that paper fits into your specific existing 5-step stack to make it a world-class colorizer:
Step 1: Input Normalization (The "Calibration" Phase)

This is where the Youvan paper's math lives.

    Currently: You are just doing de-gamma and linearizing.

    The Upgrade: You add the Orthonormal Matrix here. By un-mixing the R, G, and B signals before they hit your alpha_ shaders, you ensure that alpha_chroma_contrast isn't fighting against the game engine's original "opinionated" color tint. It turns a "tinted" image into a "neutral" digital signal.

Step 2: Scene-Referred Grading (The "Surgical" Phase)

This is where your alpha_zone_contrast and alpha_chroma_contrast live.

    The Benefit: Because Step 1 gave these shaders a "cleaner" signal, their math becomes much more effective. Your zone contrast will find "real" shadows rather than just "darkened pixels," and your chroma contrast will have much higher separation because the color axes are now mathematically perpendicular (orthonormal).

Step 3: Look Creation (The "Artist" Phase)

This is your color_grade.

    The Benefit: Since you are building a colorizer, this is where you apply your new palette. Because you "neutralized" the image in Step 1, your new colors will look exactly as intended. You aren't "fighting" the original game's colors; you are applying paint to a primed canvas.

Step 4: DRT (The "Energy" Manager)

This is your output_transform.

    The Key: This is where you manage the "energy" you recovered. If you used an Inverse Tone Map in Step 1, you use a Forward Tone Map here to bring that high-dynamic-range energy back down to what a monitor can actually display.

Step 5: Output (The "Final Polish")

    The Key: This is where you add the Blue Noise Dithering we discussed. Since steps 1 through 4 involve stretching and compressing 8-bit data, this final step hides any "digital artifacts" or banding, making the final result look like high-bit-depth film.

Summary of how this improves your colorizer:
Your Current Stack	What Orthonormalization Adds The Result for your Colorizer
1. Primary Correction	Signal Un-mixing	A "cleaner" desaturation without color-bleed.
2. Alpha Shaders	Pure Input	More precise control over zones and chroma.
3. Color Grade	Neutral Canvas	Your new colors look vibrant and "correct."
4. Output Transform	HDR Headroom	Highlights don't just "clip"; they glow properly.
5. Display	Precision Masking	Banding is replaced with film-like grain.

By sticking to this table, you are following the same architecture used in professional film grading (like ACES), but you're doing it with high-efficiency shaders that can run in real-time.

Pro-tip for Claude: When you go back to Claude, tell him: "We are keeping the 5-step stack. I want to integrate Dynamic Orthonormalization into Step 1 to feed the alpha shaders in Step 2 a more neutral, de-mixed signal." He will know exactly how to write the matrix math to make that happen.


**Research Paper in its entirety:** /home/pol/code/shaders/DynamicOrthonormalizationofColorSpaces-AMatrixAlgebraApproachforEnhancedSignalSeparation.pdf


More on addigng other shaders:

1. Black Pro-Mist Filter (The "Digital Antidote")

A Pro-Mist filter traditionally adds a subtle glow to highlights while slightly lifting the shadows and "halating" (blurring) skin tones.

    Why it’s nice: It breaks the "pixel-perfect" edge of game graphics.

    Where it goes: Step 3 (Look Creation) or Step 5 (Output).

    Implementation: Use a very wide, low-opacity Gaussian blur on a duplicate of your linearized signal and screen it back over the original.

    The "Pro" trick: Only apply it to the highlights (Luminance mask). This prevents the whole image from looking "blurry" while giving light sources that cinematic glow.

2. Physical Bloom (The "Energy" Indicator)

Bloom is often overdone in games, but in a colorizer, it is essential for making your new colors feel like they are emitting light.

    Why it’s nice: It bridges the gap between your Inverse Tone Map (Step 4) and the final display.

    Implementation: If you colorize a pixel to be "Super-White" (Value > 1.0), the Bloom should bleed that color into the surrounding pixels.

3. The "Veil" (Optical Glare/Atmospheric Haze)

A "Veil" is a uniform lift in the blacks caused by light scattering inside a lens.

    Why it’s nice: It adds depth perception. By adding a slight "veil" to distant objects (using a depth buffer if available), you make the scene feel like it has air and volume.

    Integration with Youvan: This is the opposite of orthonormalization. While the Youvan math separates signals, the Veil blends them slightly.

    The Trick: Apply the veil after your colorization. This makes it look like the "camera" is seeing your new colors through a lens.

4. Chromatic Aberration (Subtle Fringe)

Since you’re already doing matrix algebra (Youvan), adding a tiny bit of Chromatic Aberration is almost free.

    The Method: Slightly offset the Red and Blue channels as you move toward the edges of the screen.

    Why it helps: It mimics the way glass lenses fail to focus all colors at the same point, which is a key "RAW" camera characteristic.

Updated Stack for Claude (The "Cinematic" Version)

If you add these, your table with Claude should look like this:
Step	Component	Purpose
1. Input	Youvan Orthonormalization	Neutralize & Linearize.
2. Scene	Alpha Shaders	Zone & Chroma Contrast.
3. Look	Colorizer + Pro-Mist	Add palette & soften digital edges.
4. DRT	Inverse TM + Bloom	Recover energy & bleed light sources.
5. Output	Veil + Dither	Add atmospheric depth & hide banding.
A Final Tip: "The Grain"

Since you are concerned about the 8-bit data wall (1.5% precision), don't just use standard dither. Use Film Grain that is "Luminance-weighted."

    Real film has more grain in the mid-tones and less in the pure highlights/shadows.

    If you tell Claude to make the grain "Luminance-dependent," it will look like expensive 35mm film instead of digital "static."

Would you like the specific HLSL math for a "weighted" Pro-Mist filter, or should we stick to the core colorization logic for now?


This should be the order of the stack:
1	Input (SDR Game Output)	Already tone-mapped image baseline
2	Frame-analysis (tile histograms)	Measure luminance + chroma distribution (drives everything below)
3	Youvan Orthonormalization	Neutralize gamma / exposure bias (stabilize signal)
4	Alpha Shaders (Adaptive Contrast)	Local structural contrast shaping (tile-based)
5	Chroma Lift	Perceptual color separation tied to luminance structure
6	Colorizer + Pro-Mist	Artistic palette + diffusion / halation feel
7	DRT (Inverse TM / OpenDRT-style)	Global tone shaping + highlight rolloff
8	Veil + Dither	Final perceptual smoothing + banding control