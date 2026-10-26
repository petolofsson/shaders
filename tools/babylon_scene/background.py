"""Deterministic private browser sources and frame-matched shader replay."""

import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import compare_frame as pipeline
from headless_display import HeadlessDisplay
from analyze_delta import _srgb_to_linear, compute_relative

WIDTH, HEIGHT = 2560, 1440
TRIAL = ROOT / "gamespecific/gzw/gzw_stronger_trial.conf"


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pixels(path):
    with Image.open(path) as image:
        return np.asarray(image.convert("RGB"))


def read_identity(rgb):
    """Decode complementary cells, rejecting missing or damaged frame labels."""
    cells = rgb[-4:, :256].reshape(4, 64, 4, 3).mean(axis=(0, 2, 3))
    difference = cells[::2] - cells[1::2]
    if np.min(np.abs(difference)) < 16:
        raise RuntimeError("Frame identity has insufficient complementary contrast")
    payload = sum(int(bit) << i for i, bit in enumerate(difference > 0))
    frame, token, checksum = payload & 4095, (payload >> 12) & 4095, payload >> 24
    if checksum != ((frame ^ token ^ 0xa5) & 255) or frame >= 2640:
        raise RuntimeError("Frame identity checksum failed")
    return frame, token


def scene_digest(rgb):
    # The command token changes on a repeated pose. Exclude its four-row strip.
    return hashlib.sha256(rgb[:-4].tobytes()).hexdigest()


def compare_images(first, second):
    # Exclude the activity marker, identity strip and outer raster edges. Use
    # a stated spatial sample for sequence summaries, not a fidelity score.
    a = pixels(first)[8:-8:4, 8:-8:4].astype(np.float32) / 255
    b = pixels(second)[8:-8:4, 8:-8:4].astype(np.float32) / 255
    return compute_relative(_srgb_to_linear(a), _srgb_to_linear(b))


class SourceBrowser:
    def __init__(self, run_id, server, events, lock, temp, out, wait_event):
        self.run_id, self.server = run_id, server
        self.events, self.lock, self.wait_event = events, lock, wait_event
        self.token = 0
        profile = temp / f"profile-{run_id}"
        profile.mkdir()
        (profile / "user.js").write_text(
            'user_pref("dom.webgpu.enabled", true);\n'
            'user_pref("browser.shell.checkDefaultBrowser", false);\n'
            'user_pref("browser.startup.homepage_override.mstone", "ignore");\n'
            'user_pref("toolkit.telemetry.enabled", false);\n')
        log_dir = out / f"browser-{run_id}"
        log_dir.mkdir()
        env = os.environ.copy()
        env.update(ENABLE_VKBASALT="0", MOZ_ENABLE_WAYLAND="0")
        query = urllib.parse.urlencode({"controlled": 1, "run": run_id})
        command = ["firefox", "-no-remote", "-profile", str(profile), "--kiosk",
                   f"http://127.0.0.1:{server.server_port}/?{query}"]
        self.display = HeadlessDisplay(command, env, log_dir, WIDTH, HEIGHT)
        try:
            ready = wait_event(events, lock, run_id, "ready", self.display.process, 90)
            if (ready.get("width"), ready.get("height")) != (WIDTH, HEIGHT):
                raise RuntimeError(f"Browser rendered an unexpected canvas: {ready}")
            self.ready = ready
        except BaseException:
            self.display.close()
            raise

    def capture(self, frame, output):
        self.token += 1
        if self.token > 4095:
            raise RuntimeError("Controlled browser exhausted its frame-label tokens")
        token = self.token
        with self.server.control_lock:
            self.server.controls[self.run_id] = {"frame": frame, "token": token}
        self.wait_event(self.events, self.lock, self.run_id, "pose", self.display.process,
                        30, lambda event: event.get("frame") == frame and event.get("token") == token)
        for attempt in range(5):
            self.display.screenshot(output)
            rgb = pixels(output)
            try:
                identity = read_identity(rgb)
            except RuntimeError:
                identity = None
            if identity == (frame, token):
                return {"frame": frame, "token": token, "image": str(output),
                        "sha256": digest(output), "scene_sha256": scene_digest(rgb)}
            time.sleep(0.05)
        raise RuntimeError(f"Private browser did not present frame {frame}, token {token}")

    def close(self):
        self.display.close()


def render_held(source, output, settle):
    clip = output.with_suffix(".mkv")
    pipeline._make_loop_clip(source, clip)
    process = None
    try:
        process = pipeline._launch_mpv([clip], TRIAL, 3)
        pipeline._goto_frame(0, settle)
        pipeline._require_playback_advancing()
        pipeline._mpv_cmd(["set_property", "pause", True])
        pipeline._capture_frame(output)
        pipeline._require_activity_marker(pipeline._load_png_linear(output))
        return {"image": str(output), "red_marker": True,
                "identity": list(read_identity(pixels(output)))}
    finally:
        if process is not None:
            pipeline._stop_mpv(process)


def export_motion(args, server, events, lock, temp, out, wait_event):
    source = out / "motion-source"
    source.mkdir()
    frames_dir = source / "frames"
    frames_dir.mkdir()
    step = 60 // args.source_fps
    route = list(range(0, args.stop_frame + 1, step))
    manifest = {"complete": False, "resolution": [WIDTH, HEIGHT],
                "source_fps": args.source_fps, "replay_fps": 30,
                "pre_roll_s": args.settle, "route_frames": route, "frames": [],
                "scene_sha256": digest(Path(__file__).with_name("scene.js")),
                "html_sha256": digest(Path(__file__).with_name("index.html"))}
    browser = SourceBrowser("motion-source", server, events, lock, temp, out, wait_event)
    try:
        for index, frame in enumerate(route):
            capture = browser.capture(frame, frames_dir / f"{index:05d}.png")
            manifest["frames"].append(capture)
            if index % 30 == 0 or index == len(route) - 1:
                print(f"Source motion: {index + 1}/{len(route)} poses; route frame {frame}", flush=True)
        # A repeated first pose detects accumulation, asynchronous canvas state,
        # or nondeterministic scene changes after traversing the route.
        check = browser.capture(route[0], source / "first-pose-repeat.png")
        if check["scene_sha256"] != manifest["frames"][0]["scene_sha256"]:
            raise RuntimeError("Source first-pose repeat differs after the route")
        manifest["first_pose_repeat"] = check
    finally:
        browser.close()
        (source / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    clip = source / "source.mkv"
    result = subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-framerate", str(args.source_fps),
        "-i", str(frames_dir / "%05d.png"), "-vf",
        f"tpad=start_duration={args.settle}:start_mode=clone,fps=30,"
        "setparams=color_primaries=bt709:color_trc=iec61966-2-1:colorspace=gbr",
        "-c:v", "ffv1", "-threads", "2", "-pix_fmt", "bgr0", "-y", str(clip),
    ], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"Lossless motion encoding failed: {result.stderr}")
    manifest.update(complete=True, clip=str(clip), clip_sha256=digest(clip))
    (source / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest, source


def load_motion(source, args):
    source = source.resolve()
    manifest = json.loads((source / "manifest.json").read_text())
    expected_route = list(range(0, args.stop_frame + 1, 60 // args.source_fps))
    if (manifest.get("pre_roll_s") != args.settle or
            manifest.get("source_fps") != args.source_fps or
            manifest.get("replay_fps") != 30 or
            manifest.get("route_frames") != expected_route or
            manifest.get("resolution") != [WIDTH, HEIGHT]):
        raise RuntimeError("Cached motion protocol differs; regenerate for the requested settle, rate and route")
    if not manifest.get("complete") or digest(manifest["clip"]) != manifest["clip_sha256"]:
        raise RuntimeError("Motion source is incomplete or its clip hash changed")
    for name, key in (("scene.js", "scene_sha256"), ("index.html", "html_sha256")):
        if digest(Path(__file__).with_name(name)) != manifest[key]:
            raise RuntimeError("Scene changed; regenerate the cached motion source")
    return manifest, source


def motion_windows(route_end):
    windows = [("foliage", 360, 480), ("clearing", 1020, 1140),
               ("before_night_cut", 1410, 1439), ("after_night_cut", 1440, 1470),
               ("corridor", 1560, 1680), ("before_return_cut", 2130, 2159),
               ("after_return_cut", 2160, 2190)]
    selected = [(name, lo, min(hi, route_end)) for name, lo, hi in windows if lo < route_end]
    return selected or [("smoke", 0, route_end)]


def replay_motion(label, manifest, out):
    capture_dir = out / f"motion-{label}"
    capture_dir.mkdir()
    route_end = manifest["route_frames"][-1]
    ranges = [(lo, hi) for _, lo, hi in motion_windows(route_end)]
    valid_ids = {(frame["frame"], frame["token"]) for frame in manifest["frames"]}
    process = None
    captures = {}
    try:
        active = label.split("-")[0] in ("trial", "repeat")
        process = pipeline._launch_mpv([Path(manifest["clip"])], TRIAL, 3,
                    extra_options=["--loop-file=no", "--loop-playlist=no", "--keep-open=yes"],
                    env_overrides={"ENABLE_VKBASALT": "1" if active else "0"},
                    require_vkbasalt=active)
        pipeline._mpv_cmd(["seek", 0, "absolute", "exact"])
        pipeline._mpv_cmd(["set_property", "pause", False])
        pipeline._require_playback_advancing()
        for lo, hi in ranges:
            begin = manifest["pre_roll_s"] + lo / 60
            end = manifest["pre_roll_s"] + hi / 60
            pipeline._wait_for_video_time(begin)
            deadline = time.monotonic() + (end - begin) + 15
            while True:
                if time.monotonic() > deadline:
                    raise RuntimeError(f"Replay stalled in sampling window {lo}–{hi}")
                before = pipeline._mpv_cmd(["get_property", "time-pos"])
                if before > end or pipeline._mpv_cmd(["get_property", "eof-reached"]):
                    break
                path = capture_dir / f"capture-{len(captures):04d}.png"
                pipeline._capture_frame(path)
                after = pipeline._mpv_cmd(["get_property", "time-pos"])
                rgb = pixels(path)
                identity = read_identity(rgb)
                if identity not in valid_ids:
                    raise RuntimeError(f"Replay source identity is absent from manifest: {identity}")
                if active:
                    pipeline._require_activity_marker(rgb.astype(np.float32) / 255)
                key = f"{identity[0]}:{identity[1]}"
                if key not in captures:
                    captures[key] = {"image": str(path), "frame": identity[0], "token": identity[1],
                                     "video_time_before": before, "video_time_after": after, "source_run": label}
                else:
                    path.unlink()  # duplicate video presentation, not a new paired sample
            print(f"{label}: sampled route frames {lo}–{hi}; {len(captures)} unique identities", flush=True)
        playback = {key: pipeline._mpv_cmd(["get_property", key])
                    for key in ("frame-drop-count", "vo-delayed-frame-count")}
        return {"captures": captures, "playback": playback, "sample_ranges": ranges}
    finally:
        if process is not None:
            pipeline._stop_mpv(process)


def _matching_render_phase(runs, identity):
    """Require explicit GPU-update ages; pose labels and mpv time are insufficient."""
    phases = []
    for label in ("baseline", "trial", "repeat"):
        phase = runs[label]["captures"][identity].get("render_phase")
        if not isinstance(phase, dict):
            return None
        source_update, cut_update = phase.get("source_update"), phase.get("cut_update")
        if (type(source_update) is not int or source_update < 1 or
                type(cut_update) is not int or cut_update < 0):
            return None
        phases.append((source_update, cut_update))
    if len(set(phases)) != 1:
        return None
    return {"source_update": phases[0][0], "cut_update": phases[0][1]}


def matched_motion(runs, route_end, require_render_phase=False):
    """Intersect source poses, optionally requiring equal measured GPU phases."""
    matched = sorted(set(runs["baseline"]["captures"]) & set(runs["trial"]["captures"]) &
                     set(runs["repeat"]["captures"]), key=lambda key: tuple(map(int, key.split(":"))))
    if require_render_phase:
        matched = [key for key in matched if _matching_render_phase(runs, key) is not None]
    if not matched:
        if require_render_phase:
            raise RuntimeError("No matching measured render-phase identities across baseline/trial/repeat")
        raise RuntimeError("No matching source identities across baseline/trial/repeat; no pixel conclusions are valid")
    coverage = {name: [key for key in matched if lo <= int(key.split(":")[0]) <= hi]
                for name, lo, hi in motion_windows(route_end)}
    missing = [name for name, keys in coverage.items() if not keys]
    if missing:
        raise RuntimeError(f"Missing matched source identities in required windows: {missing}")
    return matched, coverage


def summarize_motion(runs, route_end, require_render_phase=False):
    """Report source comparisons without implying unmeasured temporal alignment."""
    matched, coverage = matched_motion(runs, route_end, require_render_phase=require_render_phase)
    pairs = []
    for key in matched:
        baseline = runs["baseline"]["captures"][key]
        trial = runs["trial"]["captures"][key]
        repeat = runs["repeat"]["captures"][key]
        delta = compare_images(baseline["image"], trial["image"])
        variation = compare_images(trial["image"], repeat["image"])
        pairs.append({"identity": key, "frame": trial["frame"], "source_to_trial": delta,
                      "render_phase": _matching_render_phase(runs, key),
                      "trial_repeat": variation, "images": {
                          "baseline": baseline["image"], "trial": trial["image"], "repeat": repeat["image"]}})
    return {"coverage": coverage, "matched_frames": len(pairs), "pairs": pairs, "analysis_stride": 4,
            "identity_scope": "source_pose_token_and_render_phase" if require_render_phase else "source_pose_and_token",
            "render_phase_required": require_render_phase,
            "render_phase_verified_frames": sum(pair["render_phase"] is not None for pair in pairs),
            "analysis_border_crop": 8, "mean_trial_repeat_de": float(np.mean([
                pair["trial_repeat"]["mean_de"] for pair in pairs])),
            "unmatched_frames_excluded": {label: len(run["captures"]) - len(matched)
                                           for label, run in runs.items()}}


def collect_motion(manifest, out, runs, max_attempts=4):
    for label, run in runs.items():
        if "attempts" not in run:
            run["attempts"] = [{"source_run": label, "playback": run["playback"],
                                "sample_ranges": run["sample_ranges"],
                                "captured_identities": list(run["captures"])}]
    start_attempt = max((len(run["attempts"]) for run in runs.values()), default=0)
    if runs:
        try:
            matched_motion(runs, manifest["route_frames"][-1])
        except RuntimeError:
            pass
        else:
            return summarize_motion(runs, manifest["route_frames"][-1])
    for attempt in range(start_attempt, max_attempts):
        for label in ("baseline", "trial", "repeat"):
            run_name = label if attempt == 0 else f"{label}-attempt-{attempt + 1}"
            run = replay_motion(run_name, manifest, out)
            aggregate = runs.setdefault(label, {"captures": {}, "attempts": []})
            aggregate["attempts"].append({"source_run": run_name,
                "playback": run["playback"], "sample_ranges": run["sample_ranges"],
                "captured_identities": list(run["captures"])})
            for key, capture in run["captures"].items():
                aggregate["captures"].setdefault(key, capture)
        try:
            matched_motion(runs, manifest["route_frames"][-1])
            break
        except RuntimeError as error:
            if attempt == max_attempts - 1:
                raise
            print(f"Coverage retry {attempt + 2}/{max_attempts}: {error}", flush=True)
    return summarize_motion(runs, manifest["route_frames"][-1])


def run_headless(args, result, server, events, lock, temp, out, wait_event):
    pipeline.CAPTURE_BACKEND = "headless"
    pipeline._acquire_capture_lock()
    result.update(capture_backend="headless", method="private browser source -> lossless RGB -> private vkBasalt replay")
    if not args.motion_only:
        for frame in args.frames:
            files = {}
            for label in ("baseline", "source_repeat"):
                browser = SourceBrowser(f"{label}-{frame}", server, events, lock, temp, out, wait_event)
                try:
                    capture = browser.capture(frame, out / f"{label}-{frame}.png")
                    result["captures"][f"{frame}-{label}"] = capture
                    files[label] = capture
                finally:
                    browser.close()
            if files["baseline"]["scene_sha256"] != files["source_repeat"]["scene_sha256"]:
                raise RuntimeError(f"Held source pose {frame} is not repeatable")
            for label in ("trial", "trial_repeat"):
                capture = render_held(Path(files["baseline"]["image"]), out / f"{label}-{frame}.png", args.settle)
                result["captures"][f"{frame}-{label}"] = capture
                files[label] = capture
            result["comparisons"][str(frame)] = {
                "trial_vs_baseline": compare_images(files["baseline"]["image"], files["trial"]["image"]),
                "trial_repeat": compare_images(files["trial"]["image"], files["trial_repeat"]["image"])}
            print(f"Held {frame}: exact source repeat; graded repeat ΔE "
                  f"{result['comparisons'][str(frame)]['trial_repeat']['mean_de']:.6f}", flush=True)
    if args.motion_check or args.motion_only:
        manifest, source = (load_motion(args.reuse_source, args) if args.reuse_source else
                           export_motion(args, server, events, lock, temp, out, wait_event))
        result["motion_source"] = str(source / "manifest.json")
        result["motion_runs"] = {}
        result["motion_comparisons"] = collect_motion(manifest, out, result["motion_runs"])
        print(f"Matched moving source identities: {result['motion_comparisons']['matched_frames']}", flush=True)
