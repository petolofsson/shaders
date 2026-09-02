#!/usr/bin/env python3
"""
tools/noise_floor.py - high-frequency energy measurement for EXR captures.

Single-frame mode is useful on flat or synthetic images. Pair mode measures
after-before first, so it is better for isolating dither, grain, and other
small output-noise changes between two matched renders.

Requires: numpy, openexr
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np

try:
    import OpenEXR
    import Imath
except ImportError:
    sys.exit("Missing: pip install openexr")


def load_exr(path: Path) -> np.ndarray:
    """Load R/G/B channels as float32 (H, W, 3)."""
    f = OpenEXR.InputFile(str(path))
    header = f.header()
    dw = header["dataWindow"]
    width = dw.max.x - dw.min.x + 1
    height = dw.max.y - dw.min.y + 1
    pt = Imath.PixelType(Imath.PixelType.FLOAT)
    channels = {}
    for ch in ("R", "G", "B"):
        if ch not in header["channels"]:
            sys.exit(f"{path}: missing channel '{ch}'")
        channels[ch] = np.frombuffer(f.channel(ch, pt), dtype=np.float32).reshape(height, width)
    return np.stack([channels["R"], channels["G"], channels["B"]], axis=2)


def luma(rgb: np.ndarray) -> np.ndarray:
    return 0.2126 * rgb[:, :, 0] + 0.7152 * rgb[:, :, 1] + 0.0722 * rgb[:, :, 2]


def blur5(arr: np.ndarray) -> np.ndarray:
    """5-tap binomial blur, separable, reflect padded."""
    kernel = np.array([1, 4, 6, 4, 1], dtype=np.float32) / 16.0
    pad_x = np.pad(arr, ((0, 0), (2, 2), (0, 0)), mode="reflect")
    tmp = (
        kernel[0] * pad_x[:, 0:-4, :]
        + kernel[1] * pad_x[:, 1:-3, :]
        + kernel[2] * pad_x[:, 2:-2, :]
        + kernel[3] * pad_x[:, 3:-1, :]
        + kernel[4] * pad_x[:, 4:, :]
    )
    pad_y = np.pad(tmp, ((2, 2), (0, 0), (0, 0)), mode="reflect")
    return (
        kernel[0] * pad_y[0:-4, :, :]
        + kernel[1] * pad_y[1:-3, :, :]
        + kernel[2] * pad_y[2:-2, :, :]
        + kernel[3] * pad_y[3:-1, :, :]
        + kernel[4] * pad_y[4:, :, :]
    )


def stats(values: np.ndarray) -> dict:
    v = np.asarray(values, dtype=np.float64).ravel()
    av = np.abs(v)
    return {
        "mean": float(v.mean()),
        "rms": float(np.sqrt(np.mean(v * v))),
        "abs_p50": float(np.percentile(av, 50)),
        "abs_p95": float(np.percentile(av, 95)),
        "abs_p99": float(np.percentile(av, 99)),
        "max_abs": float(av.max()),
    }


def measure(frame: np.ndarray, baseline_luma: np.ndarray) -> dict:
    frame = np.nan_to_num(frame.astype(np.float32), nan=0.0, posinf=0.0, neginf=0.0)
    high = frame - blur5(frame)
    lum_high = luma(high)
    lum_base = np.clip(baseline_luma, 0.0, 1.0)

    zones = {
        "shadows": lum_base < 0.18,
        "mids": (lum_base >= 0.18) & (lum_base < 0.70),
        "highlights": lum_base >= 0.70,
    }
    zone_stats = {}
    for name, mask in zones.items():
        zone_stats[name] = stats(lum_high[mask]) if np.any(mask) else None

    return {
        "rgb_highpass": {
            "r": stats(high[:, :, 0]),
            "g": stats(high[:, :, 1]),
            "b": stats(high[:, :, 2]),
        },
        "luma_highpass": stats(lum_high),
        "luma_highpass_by_zone": zone_stats,
    }


def print_report(report: dict) -> None:
    mode = report["mode"]
    print(f"noise_floor mode: {mode}")
    if mode == "pair":
        print(f"before: {report['before']}")
        print(f"after:  {report['after']}")
        print("measured frame: after-before")
    else:
        print(f"frame: {report['frame']}")

    lum = report["metrics"]["luma_highpass"]
    print(
        "luma highpass: "
        f"rms={lum['rms']:.8f} "
        f"abs_p95={lum['abs_p95']:.8f} "
        f"abs_p99={lum['abs_p99']:.8f} "
        f"max_abs={lum['max_abs']:.8f}"
    )

    for zone, zstats in report["metrics"]["luma_highpass_by_zone"].items():
        if zstats is None:
            print(f"{zone:10s}: no pixels")
            continue
        print(
            f"{zone:10s}: "
            f"rms={zstats['rms']:.8f} "
            f"abs_p95={zstats['abs_p95']:.8f} "
            f"abs_p99={zstats['abs_p99']:.8f}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Measure high-frequency noise-floor energy in one EXR or between two matched EXRs."
    )
    parser.add_argument("exr", nargs="+", type=Path, help="one frame, or before.exr after.exr")
    parser.add_argument("--json-out", type=Path, help="optional report path")
    args = parser.parse_args()

    if len(args.exr) not in (1, 2):
        parser.error("pass one EXR, or exactly two EXRs: before.exr after.exr")

    if len(args.exr) == 1:
        frame = load_exr(args.exr[0])
        base_luma = luma(frame)
        report = {
            "mode": "single",
            "frame": str(args.exr[0]),
            "metrics": measure(frame, base_luma),
        }
    else:
        before = load_exr(args.exr[0])
        after = load_exr(args.exr[1])
        if before.shape != after.shape:
            sys.exit(f"shape mismatch: {args.exr[0]} {before.shape} vs {args.exr[1]} {after.shape}")
        delta = after - before
        report = {
            "mode": "pair",
            "before": str(args.exr[0]),
            "after": str(args.exr[1]),
            "metrics": measure(delta, luma(before)),
        }

    print_report(report)
    if args.json_out:
        args.json_out.write_text(json.dumps(report, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
