#!/usr/bin/env python3
"""Capture deterministic Babylon WebGPU sources and matched vkBasalt output.

Uses private headless displays by default, with exact source identity checks,
fresh graded processes and unchanged repeats. Motion uses cached lossless RGB.
"""

import argparse
import hashlib
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request
from datetime import datetime
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SCENE = Path(__file__).resolve().parent
VENDOR = ROOT / "captures/babylon_scene_vendor/babylon.js"
VENDOR_URL = "https://cdn.babylonjs.com/babylon.js"
VENDOR_SHA256 = "5e162a4179028c7aa6e110879039a173f67337c170d0788a8733a20d00231f83"
TRIAL = ROOT / "gamespecific/gzw/gzw_stronger_trial.conf"
NORMAL = ROOT / "gamespecific/gzw/gzw.conf"
TUNING = ROOT / "gamespecific/gzw/shaders/creative_values.fx"
WIDTH, HEIGHT = 2560, 1440


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ensure_vendor():
    if not VENDOR.exists():
        VENDOR.parent.mkdir(parents=True, exist_ok=True)
        print(f"Fetching Babylon.js into ignored cache: {VENDOR}", flush=True)
        with urllib.request.urlopen(VENDOR_URL, timeout=60) as response:
            content = response.read()
        if hashlib.sha256(content).hexdigest() != VENDOR_SHA256:
            raise RuntimeError("Babylon CDN content changed; inspect it before updating the pinned hash")
        VENDOR.write_bytes(content)
    if digest(VENDOR) != VENDOR_SHA256:
        raise RuntimeError(f"Babylon cache hash mismatch: {VENDOR}")


def serve(out):
    events = []
    controls = {}
    lock = threading.Lock()

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(SCENE), **kwargs)

        def log_message(self, fmt, *args):
            with (out / "server.log").open("a") as stream:
                stream.write((fmt % args) + "\n")

        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path == "/control":
                run_id = urllib.parse.parse_qs(parsed.query).get("run", [""])[0]
                with lock:
                    command = controls.get(run_id, {"frame": 0, "token": 0})
                content = json.dumps(command).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            elif self.path == "/babylon.js":
                content = VENDOR.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/javascript")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            else:
                super().do_GET()

        def do_POST(self):
            if self.path != "/report":
                self.send_error(404)
                return
            data = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            try:
                event = json.loads(data)
                with lock:
                    events.append(event)
                    with (out / "events.jsonl").open("a") as stream:
                        stream.write(json.dumps(event) + "\n")
            except (ValueError, UnicodeDecodeError):
                self.send_error(400)
                return
            self.send_response(204)
            self.end_headers()

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.controls = controls
    server.control_lock = lock
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, events, lock


def focus(pid, script_dir):
    name = "shader_scene_focus"
    script = script_dir / "focus.js"
    script.write_text(
        "for (const window of workspace.stackingOrder) {\n"
        f"  if (window.pid === {pid}) {{\n"
        "    window.minimized = false;\n"
        "    workspace.raiseWindow(window);\n"
        "    workspace.activeWindow = window;\n"
        "    break;\n"
        "  }\n"
        "}\n"
    )
    base = ["qdbus6", "org.kde.KWin", "/Scripting"]
    subprocess.run(base + ["org.kde.kwin.Scripting.unloadScript", name], capture_output=True)
    subprocess.run(base + ["org.kde.kwin.Scripting.loadScript", str(script), name],
                   check=True, capture_output=True)
    try:
        subprocess.run(base + ["org.kde.kwin.Scripting.start"], check=True, capture_output=True)
        time.sleep(1)
    finally:
        subprocess.run(base + ["org.kde.kwin.Scripting.unloadScript", name], capture_output=True)


def wait_event(events, lock, run_id, wanted, process, timeout, predicate=None):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        with lock:
            selected = [e for e in events if e.get("run") == run_id]
        for event in selected:
            if event.get("stage") == "error":
                raise RuntimeError(event.get("message"))
            if event.get("stage") == wanted and (predicate is None or predicate(event)):
                return event
        if process.poll() is not None:
            raise RuntimeError(f"Gamescope exited early with {process.returncode}")
        time.sleep(0.02 if wanted == "pose" else 0.2)
    raise TimeoutError(f"No {wanted} event for {run_id} within {timeout}s")


def stop_process(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def launch_capture(label, frame, settle, port, out, events, lock, script_dir):
    run_id = f"{label}-{frame}"
    profile = script_dir / f"profile-{run_id}"
    profile.mkdir()
    (profile / "user.js").write_text(
        'user_pref("dom.webgpu.enabled", true);\n'
        'user_pref("browser.shell.checkDefaultBrowser", false);\n'
        'user_pref("browser.startup.homepage_override.mstone", "ignore");\n'
        'user_pref("toolkit.telemetry.enabled", false);\n'
    )
    query = urllib.parse.urlencode({"frame": frame, "run": run_id})
    url = f"http://127.0.0.1:{port}/?{query}"
    env = os.environ.copy()
    env.update(ENABLE_VKBASALT="1" if label == "trial" else "0",
               VKBASALT_CONFIG_FILE=str(TRIAL),
               VKBASALT_LOG_FILE=str(out / f"vkbasalt-{run_id}.log"),
               VKBASALT_LOG_LEVEL="debug")
    cmd = ["gamescope", "--backend", "sdl", "-W", str(WIDTH), "-H", str(HEIGHT),
           "-w", str(WIDTH), "-h", str(HEIGHT), "-f", "--", "env",
           "ENABLE_VKBASALT=0", "MOZ_ENABLE_WAYLAND=0", "firefox", "-no-remote",
           "-profile", str(profile), "--kiosk", url]
    png = out / f"{run_id}.png"
    log = (out / f"gamescope-{run_id}.log").open("w")
    process = subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT,
                               start_new_session=True)
    try:
        ready = wait_event(events, lock, run_id, "ready", process, 90)
        print(f"{run_id}: ready {ready.get('width')}x{ready.get('height')}; settling {settle}s", flush=True)
        time.sleep(settle)
        focus(process.pid, script_dir)
        subprocess.run(["spectacle", "--background", "--fullscreen", "--output", str(png)],
                       check=True, timeout=40, capture_output=True)
        if not png.exists():
            raise RuntimeError("Spectacle returned without an image")
        with Image.open(png) as image:
            if image.size != (WIDTH, HEIGHT):
                raise RuntimeError(f"Wrong capture size: {image.size}")
            rgb = np.asarray(image.convert("RGB"))
        marker = bool(np.all(rgb[:2, :2] == np.array([255, 0, 0])))
        if marker != (label == "trial"):
            raise RuntimeError(f"Activity marker mismatch in {png}: {rgb[:2, :2].tolist()}")
        return {"image": str(png), "ready": ready, "red_marker": marker}
    finally:
        stop_process(process)
        log.close()
        time.sleep(2)


def check_motion(label, port, out, events, lock, script_dir):
    run_id = f"motion-{label}"
    profile = script_dir / f"profile-{run_id}"
    profile.mkdir()
    (profile / "user.js").write_text(
        'user_pref("dom.webgpu.enabled", true);\n'
        'user_pref("browser.shell.checkDefaultBrowser", false);\n'
        'user_pref("toolkit.telemetry.enabled", false);\n'
    )
    query = urllib.parse.urlencode({"stop": 2220, "run": run_id})
    env = os.environ.copy()
    env.update(ENABLE_VKBASALT="1" if label == "trial" else "0",
               VKBASALT_CONFIG_FILE=str(TRIAL),
               VKBASALT_LOG_FILE=str(out / f"vkbasalt-{run_id}.log"),
               VKBASALT_LOG_LEVEL="debug")
    cmd = ["gamescope", "--backend", "sdl", "-W", str(WIDTH), "-H", str(HEIGHT),
           "-w", str(WIDTH), "-h", str(HEIGHT),
           "-f", "--", "env", "ENABLE_VKBASALT=0", "MOZ_ENABLE_WAYLAND=0",
           "firefox", "-no-remote", "-profile", str(profile), "--kiosk",
           f"http://127.0.0.1:{port}/?{query}"]
    log = (out / f"gamescope-{run_id}.log").open("w")
    process = subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT,
                               start_new_session=True)
    try:
        wait_event(events, lock, run_id, "ready", process, 90)
        focus(process.pid, script_dir)
        stopped = wait_event(events, lock, run_id, "stopped", process, 65)
        with lock:
            selected = [e for e in events if e.get("run") == run_id]
        cuts = [e for e in selected if e.get("stage") == "cut"]
        if [e.get("sceneStage") for e in cuts] != ["night", "return"]:
            raise RuntimeError(f"Expected night/return cuts: {cuts}")
        samples = [e["fps"] for e in selected if e.get("stage") == "heartbeat"
                   and 120 < e.get("frame", 0) < 2160]
        print(f"{run_id}: cuts at {[e['frame'] for e in cuts]}; "
              f"{len(samples)} browser FPS samples", flush=True)
        return {"cuts": cuts, "stopped": stopped, "fps_median": float(np.median(samples))
                if samples else None, "fps_p10": float(np.percentile(samples, 10))
                if samples else None, "fps_samples": len(samples)}
    finally:
        stop_process(process)
        log.close()
        time.sleep(2)


def compare(before_path, after_path):
    # Use the existing linear-light Oklab comparison, including marker masking.
    sys.path.insert(0, str(ROOT / "tools"))
    from analyze_delta import _srgb_to_linear, compute_relative
    with Image.open(before_path) as image:
        before = np.asarray(image.convert("RGB"), dtype=np.float32) / 255
    with Image.open(after_path) as image:
        after = np.asarray(image.convert("RGB"), dtype=np.float32) / 255
    return compute_relative(_srgb_to_linear(before), _srgb_to_linear(after))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", nargs="+", type=int, default=[420, 1080, 1620, 1920])
    parser.add_argument("--settle", type=float, default=20)
    parser.add_argument("--motion-check", action="store_true",
                        help="also run the full route with both cuts, baseline and trial")
    parser.add_argument("--capture-backend", choices=("headless", "desktop"), default="headless")
    parser.add_argument("--motion-only", action="store_true", help="skip held poses and export/replay motion")
    parser.add_argument("--source-fps", type=int, choices=(10, 15, 30), default=15,
                        help="deterministic camera samples per second; shader replay runs at 30 fps")
    parser.add_argument("--stop-frame", type=int, default=2220)
    parser.add_argument("--reuse-source", type=Path, help="reuse a previously exported motion source directory")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    ensure_vendor()
    if not all(0 <= frame < 2640 for frame in args.frames):
        parser.error("frames must be in 0..2639")
    if args.settle < 0:
        parser.error("--settle must be nonnegative")
    if not 0 < args.stop_frame < 2640:
        parser.error("--stop-frame must be in 1..2639")
    if args.capture_backend == "desktop" and (args.motion_only or args.reuse_source):
        parser.error("--motion-only/--reuse-source require the headless backend")
    out = args.output or ROOT / "captures/babylon_scene_runs" / datetime.now().strftime("%Y%m%d_%H%M%S")
    out.mkdir(parents=True, exist_ok=False)
    tracked_sources = [NORMAL, TRIAL, TUNING,
                       ROOT / "gamespecific/arc_raiders/shaders/creative_values.fx"]
    tracked_sources += sorted((ROOT / "general").rglob("*.fx*"))
    source_hashes = {str(p.relative_to(ROOT)): digest(p) for p in tracked_sources}
    server, events, lock = serve(out)
    result = {"resolution": [WIDTH, HEIGHT], "settle_s": args.settle,
              "frames": args.frames, "source_hashes": source_hashes, "captures": {},
              "comparisons": {}}
    try:
        with tempfile.TemporaryDirectory(prefix="babylon-scene-") as temp:
            if args.capture_backend == "headless":
                from background import run_headless
                run_headless(args, result, server, events, lock, Path(temp), out, wait_event)
            for frame in ([] if args.capture_backend == "headless" else args.frames):
                files = {}
                for label in ("baseline", "trial", "repeat"):
                    capture = launch_capture(label, frame, args.settle,
                                             server.server_port, out, events, lock, Path(temp))
                    result["captures"][f"{frame}-{label}"] = capture
                    files[label] = capture["image"]
                    print(f"{frame} {label}: {files[label]}", flush=True)
                result["comparisons"][str(frame)] = {
                    "trial_vs_baseline": compare(files["baseline"], files["trial"]),
                    "repeat_vs_baseline": compare(files["baseline"], files["repeat"]),
                }
                print(f"{frame}: ΔE trial {result['comparisons'][str(frame)]['trial_vs_baseline']['mean_de']:.3f}, "
                      f"repeat {result['comparisons'][str(frame)]['repeat_vs_baseline']['mean_de']:.3f}", flush=True)
            if args.motion_check and args.capture_backend == "desktop":
                result["motion"] = {
                    label: check_motion(label, server.server_port, out, events, lock, Path(temp))
                    for label in ("baseline", "trial")
                }
    except BaseException as error:
        result["failure"] = {"type": type(error).__name__, "message": str(error)}
        raise
    finally:
        result["status"] = "failed" if "failure" in result else "complete"
        server.shutdown()
        server.server_close()
        result["hashes_unchanged"] = source_hashes == {
            str(p.relative_to(ROOT)): digest(p) for p in tracked_sources}
        (out / "report.json").write_text(json.dumps(result, indent=2) + "\n")
        print(f"Report: {out / 'report.json'}", flush=True)
    if not result["hashes_unchanged"]:
        raise RuntimeError("A tracked shader, config or tuning file changed during capture")


if __name__ == "__main__":
    main()
