"""Private Gamescope display for post-vkBasalt captures without desktop access."""

import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path


# Gamescope supplies these to its client. Record only display routing, not the
# user's complete environment, before replacing the wrapper with the player.
_CLIENT = """
import json, os, sys
from pathlib import Path
keys = ('DISPLAY', 'WAYLAND_DISPLAY', 'GAMESCOPE_WAYLAND_DISPLAY', 'XDG_RUNTIME_DIR')
Path(sys.argv[1]).write_text(json.dumps({k: os.environ[k] for k in keys if k in os.environ}))
os.execvpe(sys.argv[2], sys.argv[2:], os.environ)
"""


class HeadlessDisplay:
    def __init__(self, command, env, log_dir, width, height):
        for program in ("gamescope", "gamescopectl"):
            if not shutil.which(program):
                raise RuntimeError(f"Headless capture requires {program}; use --capture-backend desktop explicitly if needed")
        self.width, self.height = width, height
        self.log_dir = Path(log_dir)
        self.client_info = self.log_dir / "display.json"
        # Unix display socket paths are limited to 108 bytes. Keep this short
        # even when retained logs live deep inside an analysis directory.
        self._runtime = tempfile.TemporaryDirectory(prefix="shader-display-")
        runtime = Path(self._runtime.name)
        outer_env = env.copy()
        outer_env.update(ENABLE_VKBASALT="0", XDG_RUNTIME_DIR=str(runtime))
        outer_env.pop("DISPLAY", None)
        outer_env.pop("WAYLAND_DISPLAY", None)
        outer_env.pop("GAMESCOPE_WAYLAND_DISPLAY", None)
        # The headless compositor has no Vulkan swapchain. Apply vkBasalt to
        # the client's swapchain, then capture the resulting compositor input.
        args = ["gamescope", "--backend", "headless", "-W", str(width),
                "-H", str(height), "-w", str(width), "-h", str(height),
                "-r", "60", "--disable-color-management",
                "--force-windows-fullscreen", "--", "env",
                f"ENABLE_VKBASALT={env.get('ENABLE_VKBASALT', '1')}",
                sys.executable, "-c", _CLIENT, str(self.client_info), *command]
        self.log = (self.log_dir / "gamescope.log").open("w")
        try:
            self.process = subprocess.Popen(args, env=outer_env, stdout=self.log,
                                            stderr=subprocess.STDOUT,
                                            start_new_session=True)
        except BaseException:
            self.log.close()
            self._runtime.cleanup()
            raise

    def screenshot(self, path):
        from PIL import Image

        if not self.client_info.exists():
            raise RuntimeError(f"Private display did not initialize; inspect {self.log_dir}/gamescope.log")
        env = os.environ.copy()
        for key in ("DISPLAY", "WAYLAND_DISPLAY", "GAMESCOPE_WAYLAND_DISPLAY"):
            env.pop(key, None)
        env.update(json.loads(self.client_info.read_text()))
        if not env.get("GAMESCOPE_WAYLAND_DISPLAY"):
            raise RuntimeError("Gamescope did not publish its private control socket")
        path = Path(path).resolve()
        path.unlink(missing_ok=True)
        result = subprocess.run(["gamescopectl", "screenshot", str(path)],
                                env=env, capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise RuntimeError(f"Headless screenshot failed: {result.stderr.strip()}")
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if path.exists():
                try:
                    with Image.open(path) as image:
                        image.load()
                        if image.size != (self.width, self.height):
                            raise RuntimeError(f"Private display capture has wrong size: {image.size}")
                    return
                except (OSError, SyntaxError):
                    pass  # the compositor may still be flushing the PNG
            if self.process.poll() is not None:
                break
            time.sleep(0.05)
        raise RuntimeError(f"Gamescope did not save {path}; inspect {self.log_dir}/gamescope.log")

    def close(self):
        try:
            # The compositor may have exited while a client still belongs to
            # its process group. Clean up that group even after leader exit.
            try:
                os.killpg(self.process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(self.process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                self.process.wait(timeout=5)
        finally:
            self.log.close()
            if getattr(self, "_runtime", None) is not None:
                self._runtime.cleanup()
