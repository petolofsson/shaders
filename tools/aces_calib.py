#!/usr/bin/env python3
"""
R86 ACES confidence calibration tool.

Reads the pixel-encoded PercTex values written by grade.fx into row y=2:
  pixel (0,2): R=p25, G=p50, B=p75   (sRGB-encoded linear floats)
  pixel (1,2): R=aces_conf, G=0, B=0

Maintains a running mean across samples. Stop when the mean stabilises
(std < 0.005 over the last 20 samples). Typical run: 2-3 minutes of gameplay.

Usage:
  python3 tools/aces_calib.py [game_label]

  game_label  arc_raiders | gzw | <anything>  — label in the output (default: unknown)

Output:
  Live: prints each sample + running mean to stdout.
  Final: writes tools/calib_<game_label>.txt with stable mean values.

Requires: grim (Wayland) or scrot (X11), python3 stdlib only.
"""

import subprocess, sys, re, time, struct, zlib, os
from pathlib import Path
from statistics import mean, stdev

GAME = sys.argv[1] if len(sys.argv) > 1 else "unknown"
OUT  = Path(__file__).parent / f"calib_{GAME}.txt"
INTERVAL  = 3    # seconds between samples
STABLE_N  = 20   # samples needed to declare stability
STABLE_SD = 0.005

def screenshot(path):
    """Capture full screen to path. Tries multiple backends in order."""
    candidates = [
        ["grim", str(path)],
        ["grimblast", "save", "screen", str(path)],
        ["wayshot", "-f", str(path)],
        ["scrot", str(path)],
        ["spectacle", "--background", "--fullscreen", "--output", str(path)],
        ["import", "-window", "root", str(path)],  # ImageMagick / X11
    ]
    for cmd in candidates:
        try:
            r = subprocess.run(cmd, capture_output=True)
            if r.returncode == 0:
                return
        except FileNotFoundError:
            continue
    raise RuntimeError("No screenshot tool found. Install grim (Wayland) or scrot (X11).")

PERC_X_P25 = 194  # highway positions written by analysis_frame DebugOverlay
PERC_X_P50 = 195
PERC_X_P75 = 196

def apply_filter(filt, row_bytes, bpp=3):
    """Apply PNG filter to reconstruct raw pixel bytes. Handles type 0 and 1."""
    if filt == 0:
        return bytes(row_bytes)
    if filt == 1:  # Sub: each byte = byte + left byte
        out = bytearray(len(row_bytes))
        for i, b in enumerate(row_bytes):
            left = out[i - bpp] if i >= bpp else 0
            out[i] = (b + left) & 0xFF
        return bytes(out)
    return None  # unsupported filter type

def read_pixels(path):
    """
    Read p25/p50/p75 from data highway row y=0, x=194,195,196 (R channels).
    Encoded by analysis_frame DebugOverlay. Returns (p25, p50, p75) as 8-bit
    ints, or None on failure.
    """
    data = Path(path).read_bytes()
    pos = 8  # skip PNG signature
    idat = b""
    width = height = 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos+4])[0]
        ctype  = data[pos+4:pos+8]
        cdata  = data[pos+8:pos+8+length]
        if ctype == b"IHDR":
            width, height = struct.unpack(">II", cdata[:8])
        elif ctype == b"IDAT":
            idat += cdata
        pos += 12 + length
    if height < 1 or width < PERC_X_P75 + 1:
        return None
    raw = zlib.decompress(idat)
    bpp = 3
    stride = 1 + width * bpp
    row0_raw = raw[0 * stride : 1 * stride]
    filt   = row0_raw[0]
    pixels = apply_filter(filt, row0_raw[1:], bpp)
    if pixels is None:
        return None
    r0 = pixels[PERC_X_P25 * bpp]  # R channel of pixel x=194 → p25
    g0 = pixels[PERC_X_P50 * bpp]  # R channel of pixel x=195 → p50
    b0 = pixels[PERC_X_P75 * bpp]  # R channel of pixel x=196 → p75
    return r0, g0, b0

def srgb_to_linear(v8):
    v = v8 / 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

def _smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)

def aces_confidence(p25, p50, p75):
    iqr        = max(p75 - p25, 0.001)
    highs_norm = max(1.0 - p75, 0.0) / iqr
    shadow_rat = p25 / max(p50, 0.001)
    bright_gate = _smoothstep(0.04, 0.12, p50)
    raw = _smoothstep(3.0, 1.2, highs_norm) * 0.70 + _smoothstep(0.72, 0.52, shadow_rat) * 0.30
    return bright_gate * max(0.0, min(1.0, raw))

def fmt(samples):
    if not samples:
        return "  —  "
    m = mean(samples)
    s = stdev(samples) if len(samples) > 1 else 0.0
    return f"{m:.3f} ±{s:.3f}"

print(f"R86 calibration  game={GAME}  interval={INTERVAL}s  stable when σ<{STABLE_SD} over {STABLE_N} samples")
print(f"{'n':>4}  {'p25':>10}  {'p50':>10}  {'p75':>10}  {'conf':>10}  stable?")

history = {"p25": [], "p50": [], "p75": [], "conf": []}

n = 0
try:
    while True:
        screenshot("/tmp/r86_calib.png")
        px = read_pixels("/tmp/r86_calib.png")
        if px is None:
            print(f"  (skipped — PNG filter not supported, try again)")
            time.sleep(INTERVAL)
            continue

        r0, g0, b0 = px
        p25  = srgb_to_linear(r0)
        p50  = srgb_to_linear(g0)
        p75  = srgb_to_linear(b0)
        conf = aces_confidence(p25, p50, p75)

        history["p25"].append(p25)
        history["p50"].append(p50)
        history["p75"].append(p75)
        history["conf"].append(conf)
        n += 1

        stable = (n >= STABLE_N and
                  all(stdev(history[k][-STABLE_N:]) < STABLE_SD
                      for k in history))

        print(f"{n:>4}  {fmt(history['p25'][-STABLE_N:]):>10}  "
              f"{fmt(history['p50'][-STABLE_N:]):>10}  "
              f"{fmt(history['p75'][-STABLE_N:]):>10}  "
              f"{fmt(history['conf'][-STABLE_N:]):>10}  "
              f"{'STABLE' if stable else ''}", flush=True)

        if stable:
            result = {k: mean(history[k][-STABLE_N:]) for k in history}
            print(f"\nStable values for '{GAME}':")
            for k, v in result.items():
                print(f"  {k} = {v:.4f}")
            OUT.write_text(
                f"game={GAME}\n" +
                "\n".join(f"{k}={v:.4f}" for k, v in result.items()) + "\n"
            )
            print(f"Written to {OUT}")
            break

        time.sleep(INTERVAL)

except KeyboardInterrupt:
    print(f"\nInterrupted at n={n}. Last running means:")
    for k in history:
        if history[k]:
            print(f"  {k} = {mean(history[k]):.4f}")
