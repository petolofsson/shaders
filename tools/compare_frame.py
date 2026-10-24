#!/usr/bin/env python3
"""
tools/compare_frame.py — One-command before/after pipeline analysis.

Renders a reference PNG through the current creative_values.fx pipeline,
captures the result, and reports ΔE_oklab with directional ΔL*, ΔC*, Δh°
breakdown per zone and hue band.

Usage:
    compare_frame <reference.png> [--game gzw] [--delay 3] [--keep]
    compare_frame --all --game gzw [--delay 3]

The reference PNG must be a raw game screenshot (pre-vkBasalt, sRGB).
Auto-detects game from gamespecific/<game>/... path structure.

--all launches mpv once for all frames (single SPIR-V compile) and
navigates via IPC socket — much faster than per-frame restarts.
Saves aggregate to gamespecific/<game>/compare_agg.json for call sheet.
"""

import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from datetime import date, datetime
from pathlib import Path

import numpy as np

try:
    import OpenEXR
    import Imath
except ImportError:
    sys.exit("Missing: pip install openexr")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze_delta import compute_relative, print_relative, _de_fmt, _BLD, _RST, HUE_BANDS  # noqa: E402
from capture import take_screenshot  # noqa: E402

ROOT         = Path(__file__).resolve().parent.parent
SOCK         = Path(f"/tmp/mpv-compare-{os.getpid()}.sock")
SCREEN       = 0        # KDE Wayland: primary (right, DP-2) = index 0
GAME_MONITOR = "right"  # which half of a dual-monitor grim capture to use
SETTLE_SECONDS = 5.0
_capture_lock = None


def _acquire_capture_lock() -> None:
    """Serialize desktop capture and temporary profile edits across diagnostics."""
    global _capture_lock
    if _capture_lock is not None:
        return
    lock = open("/tmp/shader-diagnostics.lock", "a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock.close()
        sys.exit("Another shader diagnostic owns the desktop/profile capture lock.")
    _capture_lock = lock


def _source_hashes(game: str) -> dict:
    files = sorted((ROOT / "general").rglob("*.fx*"))
    files += sorted((ROOT / "gamespecific" / game / "shaders").glob("*.fx*"))
    files += [ROOT / "gamespecific" / game / f"{game}.conf"]
    files += sorted((ROOT / "tools").glob("*.py"))
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in files if p.is_file()}


def _infer_game(png: Path) -> "str | None":
    parts = png.resolve().parts
    try:
        idx = list(parts).index("gamespecific")
        return parts[idx + 1]
    except (ValueError, IndexError):
        return None


def _load_png_linear(path: Path) -> np.ndarray:
    """sRGB PNG → linear float32 (H, W, 3) via ImageMagick."""
    r = subprocess.run(
        ["identify", "-format", "%wx%h", str(path)], capture_output=True
    )
    if r.returncode != 0:
        sys.exit(f"Cannot identify {path.name} — is imagemagick installed?")
    w, h = map(int, r.stdout.decode().strip().split("x"))

    r = subprocess.run(
        ["convert", str(path), "-depth", "8", "RGB:-"],
        capture_output=True,
    )
    if r.returncode != 0 or len(r.stdout) != w * h * 3:
        sys.exit(f"ImageMagick conversion failed for {path.name}")

    arr = (np.frombuffer(r.stdout, dtype=np.uint8)
             .reshape(h, w, 3)
             .astype(np.float32) / 255.0)
    return np.where(arr <= 0.04045, arr / 12.92, ((arr + 0.055) / 1.055) ** 2.4)


def _save_exr(arr: np.ndarray, path: Path) -> None:
    """Save linear float32 (H, W, 3) as EXR."""
    h, w = arr.shape[:2]
    header = OpenEXR.Header(w, h)
    pt = Imath.PixelType(Imath.PixelType.FLOAT)
    header["channels"] = {c: Imath.Channel(pt) for c in "RGB"}
    out = OpenEXR.OutputFile(str(path), header)
    out.writePixels({
        "R": arr[:, :, 0].astype(np.float32).tobytes(),
        "G": arr[:, :, 1].astype(np.float32).tobytes(),
        "B": arr[:, :, 2].astype(np.float32).tobytes(),
    })
    out.close()


def _launch_mpv(pngs: "list[Path]", config: Path, delay: int,
                extra_options: "list[str] | None" = None,
                env_overrides: "dict[str, str] | None" = None,
                require_vkbasalt: bool = True) -> subprocess.Popen:
    """Launch mpv with a playlist. Single SPIR-V compile; navigate with _goto_frame."""
    _acquire_capture_lock()
    SOCK.unlink(missing_ok=True)
    log_dir = Path(tempfile.mkdtemp(prefix="shader-runtime-"))
    env = os.environ.copy()
    env["ENABLE_VKBASALT"]      = "1"
    env["VKBASALT_CONFIG_FILE"] = str(config)
    env["VKBASALT_LOG_FILE"] = str(log_dir / "vkbasalt.log")
    env["VKBASALT_LOG_LEVEL"] = "debug"
    if env_overrides:
        env.update(env_overrides)
    cmd = [
        "mpv", "--no-config", "--vo=gpu", "--gpu-api=vulkan",
        "--target-trc=srgb", "--target-prim=bt.709", "--target-colorspace-hint=no",
        "--image-display-duration=inf", "--loop-playlist=inf", "--loop-file=inf", "--fs",
        f"--screen={SCREEN}", f"--fs-screen={SCREEN}",
        f"--input-ipc-server={SOCK}",
    ] + (extra_options or []) + [str(p) for p in pngs]
    with (log_dir / "mpv.log").open("w") as log:
        proc = subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT)
    print(f"  mpv pid {proc.pid} — logs: {log_dir}")
    try:
        deadline = time.monotonic() + max(delay, 15)
        while not SOCK.exists():
            if proc.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError(f"mpv did not start; inspect {log_dir}/mpv.log")
            time.sleep(0.1)
        time.sleep(max(delay, 0))
        _mpv_cmd(["get_property", "path"])
        vk_log = log_dir / "vkbasalt.log"
        if require_vkbasalt:
            if not vk_log.exists():
                raise RuntimeError(f"vkBasalt did not create a log; inspect {log_dir}/mpv.log")
            if re.search(r"\berror\b|failed", vk_log.read_text(errors="replace"), re.I):
                raise RuntimeError(f"vkBasalt reported an error; inspect {vk_log}")
        return proc
    except BaseException:
        _stop_mpv(proc)
        raise


def _stop_mpv(proc: subprocess.Popen) -> None:
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)
    SOCK.unlink(missing_ok=True)


def _require_activity_marker(frame: np.ndarray) -> None:
    """Reject a desktop capture that does not show the active grade output."""
    marker = frame[:2, :2]
    if not (np.all(marker[..., 0] > 0.5) and np.all(marker[..., 1:] < 0.05)):
        raise RuntimeError("Grade activity marker missing: check display selection and vkBasalt logs")


def _make_loop_clip(png: Path, clip: Path, fps: int = 30, frames: int = 60) -> None:
    """Encode exact RGB source pixels as a continuously playable lossless clip."""
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-loop", "1",
        "-framerate", str(fps), "-i", str(png),
        "-vf", "setparams=color_primaries=bt709:color_trc=iec61966-2-1:colorspace=gbr",
        "-frames:v", str(frames), "-c:v", "ffv1", "-pix_fmt", "bgr0",
        "-y", str(clip),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Lossless playback clip failed: {result.stderr.strip()}")


def _make_transition_clip(first: Path, second: Path, directory: Path) -> Path:
    """Twenty seconds of first scene, then eight seconds each of second/first."""
    a = directory / "first.mkv"
    b = directory / "second.mkv"
    _make_loop_clip(first, a)
    _make_loop_clip(second, b)
    entries = [a] * 10 + [b] * 4 + [a] * 4
    playlist = directory / "segments.txt"
    playlist.write_text("".join(f"file '{p}'\n" for p in entries))
    clip = directory / "transition.mkv"
    result = subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "concat",
        "-safe", "0", "-i", str(playlist), "-c", "copy", "-y", str(clip),
    ], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Transition clip failed: {result.stderr.strip()}")
    return clip


def _require_playback_advancing() -> None:
    """Catch a paused or stalled mpv source before calling it temporal warmup."""
    paused = _mpv_cmd(["get_property", "pause"])
    start = _mpv_cmd(["get_property", "time-pos"])
    time.sleep(0.25)
    end = _mpv_cmd(["get_property", "time-pos"])
    if paused or start is None or end is None or abs(end - start) < 0.05:
        raise RuntimeError(
            f"Playback did not advance during temporal warmup "
            f"(pause={paused}, time-pos={start}->{end})"
        )


def _wait_for_video_time(target: float) -> float:
    """Wait for continuous playback to reach a target within one clip cycle."""
    deadline = time.monotonic() + 50
    while time.monotonic() < deadline:
        position = _mpv_cmd(["get_property", "time-pos"])
        if position is not None and position >= target:
            return float(position)
        time.sleep(0.05)
    raise RuntimeError(f"Video did not reach {target:.1f}s")


def _mpv_cmd(cmd_list: list):
    """Send a command to the running mpv via IPC socket."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect(str(SOCK))
        s.sendall((json.dumps({"command": cmd_list, "request_id": 1}) + "\n").encode())
        with s.makefile("r") as replies:
            for line in replies:
                reply = json.loads(line)
                if reply.get("request_id") == 1:
                    if reply.get("error") != "success":
                        raise RuntimeError(f"mpv command {cmd_list!r}: {reply}")
                    return reply.get("data")
        raise RuntimeError(f"mpv closed IPC before acknowledging {cmd_list!r}")


def _goto_frame(idx: int, settle: "float | None" = None) -> None:
    """Navigate mpv playlist to frame idx and wait for it to render."""
    _mpv_cmd(["set_property", "playlist-pos", idx])
    time.sleep(SETTLE_SECONDS if settle is None else settle)


# ── All-effects mode ──────────────────────────────────────────────────────────

_AE_GATE_NAMES = ["CORRECTIVE_STRENGTH", "TONAL_STRENGTH", "CHROMA_STRENGTH", "LOOK_STRENGTH"]

# Per-effect passthrough values. Each entry: (label, {knob: passthrough_value}).
# passthrough_value = the value that makes the effect do nothing (0.0 for almost all;
# WHITES=1.0 is the exception because it is a ceiling, not a floor).
# Skip logic: if all knobs are already at their passthrough values, the effect is
# inactive and the run is skipped (would produce ΔE=0 anyway).
_EFFECTS: "list[tuple[str, dict]]" = [
    # ── INPUT ──────────────────────────────────────────────────────────────────
    ("INVERSE_STRENGTH",  {"INVERSE_STRENGTH": 0.0}),
    ("INVERSE_LUMA",      {"INVERSE_LUMA":     0.0}),
    # ── CORRECTIVE ─────────────────────────────────────────────────────────────
    ("EXPOSURE",          {"EXPOSURE":         0.0}),
    ("BLACKS_WHITES",     {"BLACKS": 0.0, "WHITES": 1.0}),
    ("FILM_CURVE",        {"FILM_CURVE": 0.0}),
    ("3WAY_CC",           {"SHADOW_TEMP": 0.0, "SHADOW_TINT": 0.0,
                           "MID_TEMP":    0.0, "MID_TINT":    0.0,
                           "HIGHLIGHT_TEMP": 0.0, "HIGHLIGHT_TINT": 0.0}),
    ("MID_TEMPERATURE",   {"MID_TEMP": 0.0}),
    # ── TONAL ──────────────────────────────────────────────────────────────────
    ("LUMA_CONTRAST",     {"LUMA_CONTRAST_RED": 0.0, "LUMA_CONTRAST_YELLOW": 0.0,
                           "LUMA_CONTRAST_GREEN": 0.0, "LUMA_CONTRAST_CYAN": 0.0,
                           "LUMA_CONTRAST_BLUE":  0.0, "LUMA_CONTRAST_MAG":  0.0}),
    ("CONTRAST",          {"CONTRAST":         0.0}),
    ("RETINEX",           {"RETINEX_STRENGTH": 0.0}),
    ("ZONE_CONTRAST",     {"ZONE_CONTRAST_STRENGTH": 0.0}),
    ("SHADOWS",           {"SHADOWS":          0.0}),
    ("SHADOW_LIFT",       {"SHADOW_LIFT_STRENGTH": 0.0}),
    # ── CHROMA ─────────────────────────────────────────────────────────────────
    ("HUE_ROTATION",      {"HUE_RED": 0.0, "HUE_YELLOW": 0.0, "HUE_GREEN": 0.0,
                           "HUE_CYAN": 0.0, "HUE_BLUE":  0.0, "HUE_MAG":   0.0}),
    ("VIBRANCE",          {"VIBRANCE":         0.0}),
    ("SATURATION",        {"SATURATION": 0.0, "SAT_RED": 0.0, "SAT_YELLOW": 0.0, "SAT_GREEN": 0.0,
                           "SAT_CYAN": 0.0, "SAT_BLUE":  0.0, "SAT_MAG":   0.0}),
    # ── LOOK ───────────────────────────────────────────────────────────────────
    ("PRINT_STOCK",       {"PRINT_STOCK":      0.0}),
    ("PRINTER_LIGHTS",    {"PRINTER_R": 0.0, "PRINTER_G": 0.0, "PRINTER_B": 0.0}),
    # Grade gates are measured separately from individual controls. Input
    # black/white mapping and FilmCurve sit outside these gates in grade.fx.
    ("CORRECTIVE_GATE",   {"CORRECTIVE_STRENGTH": 0}),
    ("TONAL_GATE",        {"TONAL_STRENGTH": 0}),
    ("CHROMA_GATE",       {"CHROMA_STRENGTH": 0}),
    ("LOOK_GATE",         {"LOOK_STRENGTH": 0}),
]


def _ae_cv_path(game: str) -> Path:
    p = ROOT / "gamespecific" / game / "shaders" / "creative_values.fx"
    if not p.exists():
        sys.exit(f"Not found: {p}")
    return p


def _ae_write_knobs(cv: Path, knobs: dict) -> None:
    """Write knob values into creative_values.fx using regex replacement.

    Handles both integer gate knobs (100/0) and float effect knobs.
    Uses multiline \\S+ to match the existing value token regardless of format
    (handles +0.10, -0.20, 0.005, 100, 1.0, etc.).
    """
    _acquire_capture_lock()
    text = cv.read_text()
    for name, val in knobs.items():
        if isinstance(val, int):
            valstr = str(val)
        elif val == 0.0:
            valstr = "0.0"
        elif val == 1.0:
            valstr = "1.0"
        else:
            valstr = f"{val:g}"
        text, replaced = re.subn(
            rf"^(#define\s+{re.escape(name)}\s+)\S+",
            rf"\g<1>{valstr}",
            text,
            flags=re.MULTILINE,
        )
        if replaced == 0:
            if _optional_default(text, name) == val:
                continue
            sys.exit(f"Knob '{name}' not found in {cv}")
    cv.write_text(text)


def _optional_default(text: str, name: str) -> "float | None":
    # Match grade.fx's single guarded fallback block, not arbitrary missing knobs.
    if name == "SATURATION" and not re.search(r"^#define\s+SATURATION\b", text, re.M):
        return 0.0
    optional = {f"{group}_{band}" for group in ("LUMA_CONTRAST", "HUE", "SAT")
                for band in ("RED", "YELLOW", "GREEN", "CYAN", "BLUE", "MAG")}
    optional.add("VIBRANCE")
    if name in optional and not re.search(r"^#define\s+LUMA_CONTRAST_RED\b", text, re.M):
        return 0.0
    return None


def _ae_knobs_at_passthrough(cv: Path, passthrough: dict) -> bool:
    """True if every knob in passthrough is already at its passthrough value.

    Used to skip effects whose knobs haven't been dialled in — they would
    produce ΔE≈0 anyway, so there is nothing to measure.
    """
    text = cv.read_text()
    for name, pval in passthrough.items():
        m = re.search(rf"^#define\s+{re.escape(name)}\s+(\S+)", text, re.MULTILINE)
        if not m:
            if _optional_default(text, name) == float(pval):
                continue
            return False
        try:
            cur = float(m.group(1))
        except ValueError:
            return False
        if abs(cur - float(pval)) > 1e-6:
            return False
    return True


def _capture_pipeline_output(
    pngs: "list[Path]", ref_images: "list[np.ndarray]", config: Path, delay: int,
    playback_paths: "list[Path] | None" = None, keep_dir: "Path | None" = None,
) -> "list[np.ndarray | None]":
    """Launch mpv and capture pipeline output for each PNG.

    Returns a list of the same length as pngs. Entries are None for frames that
    failed to capture or had a resolution mismatch — keeps indices aligned across
    multiple calls so frame i from one config can be compared to frame i of another.
    """
    outputs: "list[np.ndarray | None]" = [None] * len(pngs)
    proc = None
    try:
        for i, (png, before) in enumerate(zip(pngs, ref_images)):
            # Fresh history per image: each ablation receives the same startup
            # and settling protocol, with no carry-over from a different scene.
            proc = _launch_mpv([playback_paths[i] if playback_paths else png], config, delay)
            print(f"    [{i+1}/{len(pngs)}] {png.name}", end="", flush=True)
            _goto_frame(0)
            if playback_paths:
                _require_playback_advancing()
                _mpv_cmd(["set_property", "pause", True])

            tmp       = Path(tempfile.mkdtemp(prefix="compare_ae_"))
            after_png = tmp / f"{png.stem}_after.png"
            take_screenshot(after_png)
            _stop_mpv(proc)
            proc = None

            if not after_png.exists() or after_png.stat().st_size == 0:
                print("  SKIP (capture failed)")
                shutil.rmtree(tmp, ignore_errors=True)
                continue

            after = _load_png_linear(after_png)
            bh, bw = before.shape[:2]
            if after.shape[1] > bw:
                x = after.shape[1] // 2 if GAME_MONITOR == "right" else 0
                after = after[:, x:x + bw, :]

            if before.shape != after.shape:
                print(f"  SKIP (resolution mismatch: reference {before.shape}, capture {after.shape})")
                shutil.rmtree(tmp, ignore_errors=True)
                continue

            outputs[i] = after
            _require_activity_marker(after)
            if keep_dir:
                keep_dir.mkdir(parents=True, exist_ok=True)
                shutil.copy2(after_png, keep_dir / f"{png.stem}.png")
            shutil.rmtree(tmp, ignore_errors=True)
            print("  ok")
    finally:
        if proc is not None:
            _stop_mpv(proc)

    return outputs


def _ae_aggregate(all_stats: "list[dict]") -> dict:
    n = len(all_stats)

    def avg_zone(label):
        zones = [s["zones"][label] for s in all_stats if s["zones"].get(label)]
        if not zones:
            return None
        return {
            "mean_de": sum(z["mean_de"] for z in zones) / len(zones),
            "dL":      sum(z["dL"]      for z in zones) / len(zones),
            "dC":      sum(z["dC"]      for z in zones) / len(zones),
        }

    def avg_band(bname):
        bands = [s["hue_bands"][bname] for s in all_stats if s["hue_bands"].get(bname)]
        if not bands:
            return None
        return {
            "mean_de": sum(b["mean_de"] for b in bands) / len(bands),
            "dL":      sum(b["dL"]      for b in bands) / len(bands),
            "dC":      sum(b["dC"]      for b in bands) / len(bands),
            "dh":      sum(b["dh"]      for b in bands if b["dh"] is not None)
                       / max(1, sum(b["dh"] is not None for b in bands)),
            "n":       sum(b["n"] for b in bands),
        }

    return {
        "mean_de":   sum(s["mean_de"] for s in all_stats) / n,
        "n_frames": n,
        "endpoints": {
            side: {metric: sum(s["endpoints"][side][metric] for s in all_stats) / n
                   for metric in ("black_pct", "any_channel_white_pct")}
            for side in ("before", "after")
        },
        "zones":     {lbl: avg_zone(lbl) for lbl in ("shadows", "midtones", "highlights")},
        "hue_bands": {e[0]: avg_band(e[0]) for e in HUE_BANDS},
    }


def _run_all_effects(game: str, config: Path, delay: int, max_frames: int = 12,
                     only: "list[str] | None" = None, reference: "Path | None" = None,
                     continuous: bool = True, keep: bool = False) -> None:
    cv            = _ae_cv_path(game)
    original_text = cv.read_text()

    frames_dir = ROOT / "gamespecific" / game / "analysis" / "reference"
    pngs       = [reference] if reference is not None else sorted(frames_dir.glob("*.png"))[:max_frames]
    if any(not p.is_file() for p in pngs):
        sys.exit("Reference image does not exist")
    if not pngs:
        sys.exit(f"No PNGs in {frames_dir}")

    effects = _EFFECTS
    if only:
        valid = {label for label, _ in _EFFECTS}
        unknown = [n for n in only if n not in valid]
        if unknown:
            sys.exit(f"Unknown effect(s): {', '.join(unknown)}\nValid: {', '.join(sorted(valid))}")
        effects = [(label, pt) for label, pt in _EFFECTS if label in only]

    started = datetime.now()
    out_dir = ROOT / "gamespecific" / game / "full_analysis"
    default_config = ROOT / "gamespecific" / game / f"{game}.conf"
    if config.resolve() != default_config.resolve():
        out_dir = out_dir / "alternate"
    capture_dir = out_dir / f"captures_{started.strftime('%Y-%m-%d_%H%M%S')}" if keep else None
    clip_dir = Path(tempfile.mkdtemp(prefix="shader-loop-clips-")) if continuous else None
    playback_paths = None
    try:
        if clip_dir:
            playback_paths = []
            for i, png in enumerate(pngs):
                clip = clip_dir / f"{i:03d}.mkv"
                _make_loop_clip(png, clip)
                playback_paths.append(clip)
    except BaseException:
        if clip_dir:
            shutil.rmtree(clip_dir, ignore_errors=True)
        raise

    print(f"compare_frame --all-effects  game={game}  {len(pngs)} frame(s)")
    print(f"Mode: incremental subtraction — ΔE(full pipeline) vs ΔE(full minus effect)")
    print(f"Effects: {', '.join(label for label, _ in effects)}\n")

    def _restore(sig=None, frame=None):
        cv.write_text(original_text)
        print("\ncreative_values.fx restored.")
        if sig is not None:
            sys.exit(1)
    signal.signal(signal.SIGINT, _restore)
    signal.signal(signal.SIGTERM, _restore)

    ref_images = [_load_png_linear(p) for p in pngs]
    results: "list[tuple[str, dict | None]]" = []
    full_agg: "dict | None" = None

    try:
        # Phase 1 — FULL pipeline (gates must all be 100)
        print("── FULL  (reference)")
        _ae_write_knobs(cv, {k: 100 for k in _AE_GATE_NAMES})
        time.sleep(0.1)
        full_out = _capture_pipeline_output(
            pngs, ref_images, config, delay, playback_paths,
            capture_dir / "full" if capture_dir else None)
        print("── FULL repeat  (capture/history variation)")
        repeat_out = _capture_pipeline_output(
            pngs, ref_images, config, delay, playback_paths,
            capture_dir / "repeat" if capture_dir else None)
        repeat_stats = [compute_relative(full_out[i], repeat_out[i])
                        for i in range(len(pngs))
                        if full_out[i] is not None and repeat_out[i] is not None]
        if not repeat_stats:
            raise RuntimeError("No matched FULL repeats; effect attribution has no variation baseline")
        repeatability = _ae_aggregate(repeat_stats)
        print(f"  Unchanged-pipeline repeat ΔE {repeatability['mean_de']:.3f}\n")
        # restore after FULL capture so cv is back to original state for subtraction runs
        cv.write_text(original_text)
        n_ok = sum(1 for o in full_out if o is not None)
        print(f"  {n_ok}/{len(pngs)} frames ok\n")
        if n_ok == 0:
            raise RuntimeError("FULL capture failed: no matched frames; no analysis was saved")

        full_raw_stats = [
            compute_relative(ref_images[i], full_out[i])
            for i in range(len(pngs))
            if full_out[i] is not None and ref_images[i].shape == full_out[i].shape
        ]
        if full_raw_stats:
            full_agg = _ae_aggregate(full_raw_stats)

        # Phase 2 — WITHOUT each effect; compare to FULL
        for label, passthrough in effects:
            if _ae_knobs_at_passthrough(cv, passthrough):
                print(f"── without {label}  (skipped — already at passthrough)\n")
                results.append((label, None))
                continue

            print(f"── without {label}")
            _ae_write_knobs(cv, {**{k: 100 for k in _AE_GATE_NAMES}, **passthrough})
            time.sleep(0.1)
            wo_out = _capture_pipeline_output(
                pngs, ref_images, config, delay, playback_paths,
                capture_dir / label if capture_dir else None)
            cv.write_text(original_text)   # restore before next iteration

            frame_stats = [
                compute_relative(wo_out[i], full_out[i])
                for i in range(len(pngs))
                if full_out[i] is not None and wo_out[i] is not None
                and full_out[i].shape == wo_out[i].shape
            ]
            if not frame_stats:
                print(f"  No valid frame pairs — skipping.\n")
                results.append((label, None))
                continue

            agg = _ae_aggregate(frame_stats)
            results.append((label, agg))
            print(f"  {label} contribution ΔE {agg['mean_de']:.2f}\n")

    finally:
        cv.write_text(original_text)
        if clip_dir:
            shutil.rmtree(clip_dir, ignore_errors=True)
        print("creative_values.fx restored.\n")

    if not results and full_agg is None:
        return

    DEAD = 0.5

    print("─" * 72)
    print(f"\n{_BLD}EFFECT ATTRIBUTION  (incremental — full pipeline minus that effect){_RST}")
    print(f"  ΔE = how much the output changes when that effect is zeroed")
    print(f"  Unchanged-pipeline repeat ΔE {repeatability['mean_de']:.3f}")
    print(f"  ΔE < {DEAD}: small contribution; compare with repeat variation and scene gates\n")

    hdr = f"  {'Effect':<18}  {'ΔE':>5}  {'shadows ΔL*/ΔC*':>18}  {'mids ΔL*/ΔC*':>14}  {'highs ΔL*/ΔC*':>14}"
    sep_line = "  " + "─" * 74
    print(hdr)
    print(sep_line)

    def _zone_row(label: str, agg: "dict | None", flag_dead: bool = True) -> None:
        if agg is None:
            print(f"  {label:<18}  (skipped — at passthrough)")
            return
        de   = agg["mean_de"]
        sh   = agg["zones"].get("shadows")
        mi   = agg["zones"].get("midtones")
        hi   = agg["zones"].get("highlights")
        sh_s = f"{sh['dL']:+.1f}/{sh['dC']:+.1f}" if sh else "    —    "
        mi_s = f"{mi['dL']:+.1f}/{mi['dC']:+.1f}" if mi else "    —    "
        hi_s = f"{hi['dL']:+.1f}/{hi['dC']:+.1f}" if hi else "    —    "
        flag = "  ← silent?" if flag_dead and de < DEAD else ""
        print(f"  {label:<18}  {_de_fmt(de)}  {sh_s:>18}  {mi_s:>14}  {hi_s:>14}{flag}")

    for label, agg in results:
        _zone_row(label, agg)

    if full_agg is not None:
        print(sep_line)
        _zone_row("FULL (raw→graded)", full_agg, flag_dead=False)

    # Hue band table
    band_names = [e[0] for e in HUE_BANDS]
    print(f"\n  by hue band  (ΔL*/ΔC*, Δh°; orange isolated; chromatic pixels C*>3)")
    print(f"  {'Effect':<18}  " + "  ".join(f"{b:<12}" for b in band_names))
    print("  " + "─" * (20 + 14 * len(band_names)))

    def _band_row(label: str, agg: "dict | None") -> None:
        if agg is None:
            print(f"  {label:<18}  (skipped)")
            return
        cells = [
            (f"{agg['hue_bands'][b]['dC']:+.1f}/{agg['hue_bands'][b]['dh']:+.1f}°"
             if agg["hue_bands"].get(b) else "   —   ")
            for b in band_names
        ]
        print(f"  {label:<18}  " + "  ".join(f"{c:<12}" for c in cells))

    for label, agg in results:
        _band_row(label, agg)
    if full_agg is not None:
        _band_row("FULL", full_agg)
    print()

    # ── Persist to full_analysis/ ─────────────────────────────────────────────
    now      = datetime.now()
    cv_path  = ROOT / "gamespecific" / game / "shaders" / "creative_values.fx"
    out_dir.mkdir(parents=True, exist_ok=True)

    payload = {
        "date":            str(now.date()),
        "time":            now.strftime("%H:%M:%S"),
        "game":            game,
        "runtime_config":  str(config.resolve()),
        "runtime_config_sha256": hashlib.sha256(config.read_bytes()).hexdigest(),
        "n_frames":        len(pngs),
        "n_valid_full_frames": n_ok,
        "unchanged_pipeline_repeat": repeatability,
        "settle_seconds":  SETTLE_SECONDS,
        "history":         ("fresh process per image; continuous RGB lossless playback, fixed warmup, not guaranteed steady state"
                            if continuous else "fresh process per image; paused still image, elapsed wait is not temporal warmup"),
        "continuous_playback": continuous,
        "retained_capture_dir": str(capture_dir.relative_to(ROOT)) if capture_dir else None,
        "display_target":  "sRGB / BT.709, target-colorspace-hint=no",
        "diagnostic_gates": {k: 100 for k in _AE_GATE_NAMES},
        "compile_delay_seconds": delay,
        "source_sha256":   _source_hashes(game),
        "reference_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in pngs},
        "creative_values": cv_path.read_text() if cv_path.exists() else None,
        "effects": {
            label: agg
            for label, agg in results
        },
        "full": full_agg,
    }

    ts       = now.strftime("%Y-%m-%d_%H%M%S")
    run_path = out_dir / f"effects_{ts}.json"
    run_path.write_text(json.dumps(payload, indent=2))

    latest = out_dir / "latest.json"
    latest.write_text(json.dumps(payload, indent=2))

    print(f"  saved → {run_path.relative_to(ROOT)}")
    print(f"  latest → {latest.relative_to(ROOT)}")
    if capture_dir:
        print(f"  captures → {capture_dir.relative_to(ROOT)}")


def _run_scene_cut_probe(first: Path, second: Path, game: str,
                         config: Path, delay: int) -> None:
    """Compare matched outputs early and late after two real-image scene cuts."""
    _acquire_capture_lock()
    first_ref = _load_png_linear(first)
    second_ref = _load_png_linear(second)
    if first_ref.shape != second_ref.shape:
        raise RuntimeError("Scene-cut references must have identical dimensions")

    now = datetime.now()
    out_dir = ROOT / "gamespecific" / game / "full_analysis"
    if config.resolve() != (ROOT / "gamespecific" / game / f"{game}.conf").resolve():
        out_dir /= "alternate"
    out_dir = out_dir / f"transition_{now.strftime('%Y-%m-%d_%H%M%S')}"
    out_dir.mkdir(parents=True, exist_ok=True)

    targets = [
        ("first_steady", 18.0, first_ref),
        ("second_early", 20.5, second_ref),
        ("second_late", 26.0, second_ref),
        ("first_early", 28.5, first_ref),
        ("first_late", 34.5, first_ref),
    ]
    frames = {}
    positions = {}
    playback = {}
    with tempfile.TemporaryDirectory(prefix="shader-transition-") as tmp:
        clip = _make_transition_clip(first, second, Path(tmp))
        for label, target, reference in targets:
            proc = None
            try:
                proc = _launch_mpv([clip], config, delay)
                _mpv_cmd(["seek", 0, "absolute", "exact"])
                _require_playback_advancing()
                start_pos = _wait_for_video_time(target)
                _mpv_cmd(["set_property", "pause", True])
                shot = out_dir / f"{label}.png"
                take_screenshot(shot)
                end_pos = _mpv_cmd(["get_property", "time-pos"])
                positions[label] = {"before": start_pos, "after": end_pos}
                lo, hi = ((20.0, 28.0) if label.startswith("second") else
                          (28.0, 36.0) if label.startswith("first_e") or label == "first_late" else
                          (0.0, 20.0))
                if not lo <= start_pos < hi or end_pos is None or not lo <= end_pos < hi:
                    raise RuntimeError(f"{label} capture crossed a scene boundary: {positions[label]}")
                frame = _load_png_linear(shot)
                if frame.shape != reference.shape:
                    raise RuntimeError(f"{label} capture resolution does not match reference")
                _require_activity_marker(frame)
                frames[label] = frame
                print(f"  {label}: target {target:.1f}s, captured {start_pos:.2f}–{end_pos:.2f}s")
                playback[label] = {}
                for key in ("frame-drop-count", "mistimed-frame-count",
                            "vo-delayed-frame-count", "display-fps"):
                    try:
                        playback[label][key] = _mpv_cmd(["get_property", key])
                    except RuntimeError:
                        playback[label][key] = None
            finally:
                if proc is not None:
                    _stop_mpv(proc)

    pairs = {
        "second_early_to_late": ("second_early", "second_late"),
        "first_early_to_late": ("first_early", "first_late"),
        "first_before_to_after": ("first_steady", "first_late"),
    }
    comparisons = {name: compute_relative(frames[a], frames[b])
                   for name, (a, b) in pairs.items()}
    source_comparisons = {
        label: compute_relative(reference, frames[label])
        for label, _, reference in targets
    }
    report = {
        "date": str(now.date()), "time": now.strftime("%H:%M:%S"),
        "game": game, "runtime_config": str(config.resolve()),
        "runtime_config_sha256": hashlib.sha256(config.read_bytes()).hexdigest(),
        "source_sha256": _source_hashes(game),
        "reference_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in (first, second)},
        "method": "lossless RGB video: first 20s, second 8s, first 8s; 30 fps; fresh playback for each paused snapshot",
        "positions_seconds": positions,
        "playback": playback,
        "temporal_comparisons": comparisons,
        "source_comparisons": source_comparisons,
    }
    (out_dir / "report.json").write_text(json.dumps(report, indent=2))
    for name, stats in comparisons.items():
        print(f"  {name}: ΔE {stats['mean_de']:.3f}")
    print(f"  playback counters: {playback}")
    print(f"  saved → {out_dir.relative_to(ROOT)}")


def _run_perf_probe(png: Path, game: str, config: Path, delay: int,
                    baseline: bool) -> None:
    """Stress mpv presentation and retain MangoHud frametime logs."""
    _acquire_capture_lock()
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    label = "baseline" if baseline else "pipeline"
    out_dir = ROOT / "gamespecific" / game / "full_analysis"
    if config.resolve() != (ROOT / "gamespecific" / game / f"{game}.conf").resolve():
        out_dir /= "alternate"
    out_dir /= f"perf_{stamp}_{label}"
    out_dir.mkdir(parents=True, exist_ok=True)
    mango_config = out_dir / "MangoHud.conf"
    mango_config.write_text(
        f"fps_only\nautostart_log=1\nlog_duration=16\nlog_interval=0\noutput_folder={out_dir}\n"
    )
    proc = None
    with tempfile.TemporaryDirectory(prefix="shader-perf-") as tmp:
        clip = Path(tmp) / "source.mkv"
        _make_loop_clip(png, clip, fps=120, frames=240)
        env = {
            "MANGOHUD": "1",
            "MANGOHUD_CONFIGFILE": str(mango_config),
        }
        if baseline:
            env["ENABLE_VKBASALT"] = "0"
        try:
            proc = _launch_mpv(
                [clip], config, delay,
                extra_options=["--untimed", "--framedrop=no", "--no-audio"],
                env_overrides=env, require_vkbasalt=not baseline)
            _require_playback_advancing()
            time.sleep(12)
            playback = {}
            for key in ("frame-drop-count", "vo-delayed-frame-count", "display-fps"):
                try:
                    playback[key] = _mpv_cmd(["get_property", key])
                except RuntimeError:
                    playback[key] = None
        finally:
            if proc is not None:
                _stop_mpv(proc)

    logs = [str(p.relative_to(out_dir)) for p in out_dir.rglob("*") if p.is_file()]
    if not any(name.endswith(".csv") and not name.endswith("_summary.csv") for name in logs):
        raise RuntimeError(f"MangoHud did not produce a frame-time CSV in {out_dir}")
    report = {
        "game": game, "reference": str(png.resolve()),
        "reference_sha256": hashlib.sha256(png.read_bytes()).hexdigest(),
        "runtime_config": str(config.resolve()), "baseline": baseline,
        "method": "mpv untimed 120 fps FFV1 RGB loop at source size, 12 second observation; MangoHud logging",
        "playback": playback, "mangohud_files": logs,
    }
    (out_dir / "report.json").write_text(json.dumps(report, indent=2))
    print(f"  playback counters: {playback}")
    print(f"  MangoHud files: {logs}")
    print(f"  saved → {out_dir.relative_to(ROOT)}")


def _run_batch(game: str, config: Path, delay: int, keep: bool) -> None:
    frames_dir = ROOT / "gamespecific" / game / "analysis" / "reference"
    pngs = sorted(frames_dir.glob("*.png"))
    if not pngs:
        sys.exit(f"No PNGs in {frames_dir}")

    print(f"compare_frame --all  game={game}  {len(pngs)} frame(s)")
    print()

    analysis_dir = ROOT / "gamespecific" / game / "analysis" / str(date.today())
    frames_out: "Path | None" = None
    if keep:
        frames_out = analysis_dir / "frames"
        frames_out.mkdir(parents=True, exist_ok=True)

    all_stats: list[dict] = []
    all_channels: list[dict] = []
    proc = _launch_mpv(pngs, config, delay)

    try:
        for i, png in enumerate(pngs):
            print(f"── [{i+1}/{len(pngs)}] {png.name}")
            before = _load_png_linear(png)
            bh, bw = before.shape[:2]

            _goto_frame(i)

            tmp       = Path(tempfile.mkdtemp(prefix="compare_frame_"))
            after_png = tmp / f"{png.stem}_after.png"
            take_screenshot(after_png)

            if not after_png.exists() or after_png.stat().st_size == 0:
                print("  SKIP — screen capture failed")
                shutil.rmtree(tmp, ignore_errors=True)
                continue

            after = _load_png_linear(after_png)
            ah, aw = after.shape[:2]
            if aw > bw:
                x = aw // 2 if GAME_MONITOR == "right" else 0
                after = after[:, x:x + bw, :]
                ah, aw = after.shape[:2]

            if before.shape != after.shape:
                print(f"  SKIP — resolution mismatch: ref {bw}×{bh}, capture {aw}×{ah}")
                shutil.rmtree(tmp, ignore_errors=True)
                continue

            if keep and frames_out:
                _save_exr(before, frames_out / f"{png.stem}_before.exr")
                _save_exr(after,  frames_out / f"{png.stem}_after.exr")
            shutil.rmtree(tmp, ignore_errors=True)

            stats = compute_relative(before, after)
            all_stats.append(stats)

            frame_ch = {}
            for ch, ci in (("R", 0), ("G", 1), ("B", 2)):
                frame_ch[ch] = {
                    "raw":  [float(v) for v in np.percentile(before[:, :, ci], [5, 50, 95])],
                    "grad": [float(v) for v in np.percentile(after[:, :, ci],  [5, 50, 95])],
                }
            all_channels.append(frame_ch)

            for label in ("shadows", "midtones", "highlights"):
                z = stats["zones"].get(label)
                if z is None:
                    continue
                dh_s = f"{z['dh']:+.1f}°" if z["dh"] is not None else "—    "
                print(f"  {label:<12}  ΔL* {z['dL']:+5.1f}  ΔC* {z['dC']:+5.1f}  Δh° {dh_s:<7}  ΔE {_de_fmt(z['mean_de'])}")
            print()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()

    if not all_stats:
        sys.exit("No frames analysed.")

    n = len(all_stats)
    print("─" * 62)
    print(f"\n{_BLD}AGGREGATE  {n} frame(s){_RST}\n")

    agg_zones: dict = {}
    for label in ("shadows", "midtones", "highlights"):
        zones = [s["zones"][label] for s in all_stats if s["zones"].get(label)]
        if not zones:
            agg_zones[label] = None
            continue
        dhs = [z["dh"] for z in zones if z["dh"] is not None]
        agg_zones[label] = {
            "mean_de": sum(z["mean_de"] for z in zones) / len(zones),
            "dL":      sum(z["dL"]      for z in zones) / len(zones),
            "dC":      sum(z["dC"]      for z in zones) / len(zones),
            "dh":      sum(dhs) / len(dhs) if dhs else None,
        }
        z = agg_zones[label]
        dh_s = f"{z['dh']:+.1f}°" if z["dh"] is not None else "—    "
        print(f"  {label:<12}  ΔL* {z['dL']:+5.1f}  ΔC* {z['dC']:+5.1f}  Δh° {dh_s:<7}  ΔE {_de_fmt(z['mean_de'])}")

    agg_bands: dict = {}
    print(f"\n  by hue band (C*>5 chromatic pixels)")
    for entry in HUE_BANDS:
        bname = entry[0]
        bands = [s["hue_bands"][bname] for s in all_stats if s["hue_bands"].get(bname)]
        if not bands:
            agg_bands[bname] = None
            continue
        dhs = [b["dh"] for b in bands if b["dh"] is not None]
        agg_bands[bname] = {
            "mean_de": sum(b["mean_de"] for b in bands) / len(bands),
            "dL":      sum(b["dL"]      for b in bands) / len(bands),
            "dC":      sum(b["dC"]      for b in bands) / len(bands),
            "dh":      sum(dhs) / len(dhs) if dhs else None,
        }
        b = agg_bands[bname]
        dh_s = f"{b['dh']:+.1f}°" if b["dh"] is not None else "—    "
        print(f"  {bname:<8}      ΔL* {b['dL']:+5.1f}  ΔC* {b['dC']:+5.1f}  Δh° {dh_s:<7}  ΔE {_de_fmt(b['mean_de'])}")
    print()

    # Save aggregate JSON for call sheet
    agg_channels: dict = {}
    if all_channels:
        for ch in ("R", "G", "B"):
            agg_channels[ch] = {
                "raw":  [sum(f[ch]["raw"][i]  for f in all_channels) / len(all_channels) for i in range(3)],
                "grad": [sum(f[ch]["grad"][i] for f in all_channels) / len(all_channels) for i in range(3)],
            }

    agg_data = {
        "date":     str(date.today()),
        "game":     game,
        "n_frames": n,
        "zones":    agg_zones,
        "hue_bands": agg_bands,
        "channels": agg_channels,
    }
    agg_path = ROOT / "gamespecific" / game / "compare_agg.json"
    agg_path.write_text(json.dumps(agg_data, indent=2))
    print(f"  aggregate → {agg_path.relative_to(ROOT)}")

    analysis_dir.mkdir(parents=True, exist_ok=True)
    arch_path = analysis_dir / "compare_agg.json"
    arch_path.write_text(json.dumps(agg_data, indent=2))
    if keep and frames_out:
        print(f"  EXRs      → {frames_out.relative_to(ROOT)}/")
    print(f"  archive   → {arch_path.relative_to(ROOT)}")


def main() -> None:
    global SETTLE_SECONDS
    ap = argparse.ArgumentParser(
        description="One-command before/after pipeline analysis",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  compare_frame gamespecific/gzw/reference_frames/frame.png\n"
            "  compare_frame --all --game gzw\n"
            "  compare_frame frame.png --keep\n"
        ),
    )
    ap.add_argument("png",     nargs="?", default=None,
                    help="Reference PNG (pre-vkBasalt game screenshot)")
    ap.add_argument("--all",         action="store_true",
                    help="Batch-analyse all reference frames for the game")
    ap.add_argument("--all-effects", action="store_true",
                    help="Measure each pipeline stage individually (not cumulative) — shows silent effects")
    ap.add_argument("--transition", type=Path, default=None,
                    help="Second reference PNG for a continuous scene-cut probe")
    ap.add_argument("--perf-probe", action="store_true",
                    help="Run a high-rate mpv/MangoHud throughput probe")
    ap.add_argument("--perf-baseline", action="store_true",
                    help="Disable vkBasalt during --perf-probe")
    ap.add_argument("--game",  default=None,
                    help="Game name (auto-inferred from path, required with --all / --all-effects)")
    ap.add_argument("--config", type=Path, default=None,
                    help="vkBasalt config to use for this capture")
    ap.add_argument("--delay", type=int, default=3,
                    help="Seconds to wait for SPIR-V compile (default: 3)")
    ap.add_argument("--keep",  action="store_true",
                    help="Retain captures for inspection (or EXRs in batch mode)")
    ap.add_argument("--settle", type=float, default=5.0,
                    help="Seconds of history warmup per image (default: 5; not steady state)")
    ap.add_argument("--max-frames", type=int, default=None,
                    help="Cap number of reference frames (default: 12 for --all-effects, unlimited for --all)")
    ap.add_argument("--only", nargs="+", default=None, metavar="EFFECT",
                    help="Test only these effects (space-separated, e.g. --only INVERSE_LUMA EXPOSURE)")
    args = ap.parse_args()
    if not 0 <= args.settle <= 60 or not 0 <= args.delay <= 60:
        ap.error("--settle and --delay must be between 0 and 60 seconds")
    SETTLE_SECONDS = args.settle
    _acquire_capture_lock()

    if args.perf_probe:
        if not args.png:
            ap.error("--perf-probe requires a reference PNG")
        png = Path(args.png)
        if not png.is_file():
            ap.error(f"Reference PNG not found: {png}")
        game = args.game or _infer_game(png)
        if not game:
            ap.error("Cannot infer game; pass --game")
        config = args.config or ROOT / "gamespecific" / game / f"{game}.conf"
        if not config.exists():
            ap.error(f"Config not found: {config}")
        _run_perf_probe(png, game, config, args.delay, args.perf_baseline)
        return

    if args.transition is not None:
        if not args.png:
            ap.error("--transition requires the first reference PNG")
        first = Path(args.png)
        second = args.transition
        if not first.is_file() or not second.is_file():
            ap.error("Both scene-cut reference PNGs must exist")
        game = args.game or _infer_game(first)
        if not game:
            ap.error("Cannot infer game; pass --game")
        config = args.config or ROOT / "gamespecific" / game / f"{game}.conf"
        if not config.exists():
            ap.error(f"Config not found: {config}")
        _run_scene_cut_probe(first, second, game, config, args.delay)
        return

    if args.all_effects:
        game = args.game
        if not game:
            sys.exit("--all-effects requires --game <name>")
        config = args.config or ROOT / "gamespecific" / game / f"{game}.conf"
        if not config.exists():
            sys.exit(f"Config not found: {config}")
        max_frames = args.max_frames if args.max_frames is not None else 12
        _run_all_effects(game, config, args.delay, max_frames, args.only,
                         Path(args.png) if args.png else None,
                         True, args.keep)
        return

    if args.all:
        game = args.game
        if not game:
            sys.exit("--all requires --game <name>")
        config = args.config or ROOT / "gamespecific" / game / f"{game}.conf"
        if not config.exists():
            sys.exit(f"Config not found: {config}")
        _run_batch(game, config, args.delay, args.keep)
        return

    if not args.png:
        ap.print_help()
        sys.exit(1)

    png = Path(args.png)
    if not png.exists():
        sys.exit(f"Not found: {png}")

    game = args.game or _infer_game(png)
    if not game:
        sys.exit("Cannot infer game from path. Pass --game <name>.")

    config = args.config or ROOT / "gamespecific" / game / f"{game}.conf"
    if not config.exists():
        sys.exit(f"Config not found: {config}")

    stem      = png.stem
    tmp       = Path(tempfile.mkdtemp(prefix="compare_frame_"))
    after_png = tmp / f"{stem}_after.png"

    proc = None
    try:
        print(f"compare_frame  game={game}  source={png.name}")
        print()

        print("Before: loading reference PNG...")
        before = _load_png_linear(png)
        bh, bw = before.shape[:2]
        print(f"  {bw}×{bh}")
        print()

        print("After: launching mpv + vkBasalt...")
        proc = _launch_mpv([png], config, args.delay)
        _goto_frame(0)

        print("Capturing screen...")
        take_screenshot(after_png)
        if not after_png.exists() or after_png.stat().st_size == 0:
            proc.terminate()
            sys.exit("Screen capture failed.")

        print("After: linearizing captured frame...")
        after = _load_png_linear(after_png)
        ah, aw = after.shape[:2]
        if aw > bw:
            x = aw // 2 if GAME_MONITOR == "right" else 0
            after = after[:, x:x + bw, :]
            ah, aw = after.shape[:2]
        print(f"  {aw}×{ah}")

        _stop_mpv(proc)
        proc = None
        print("mpv closed.")
        print()

        if before.shape != after.shape:
            sys.exit(
                f"Resolution mismatch: reference {bw}×{bh}, capture {aw}×{ah}.\n"
                f"Ensure the reference PNG matches the display resolution ({aw}×{ah})."
            )
        _require_activity_marker(after)

        if args.keep:
            _save_exr(before, tmp / f"{stem}_before.exr")
            _save_exr(after,  tmp / f"{stem}_after.exr")

        stats = compute_relative(before, after)
        print_relative(stats, png.name, after_png.name)

    finally:
        if proc is not None:
            _stop_mpv(proc)
        if not args.keep:
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            print(f"Temp files kept in {tmp}/")


if __name__ == "__main__":
    main()
