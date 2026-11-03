# Gray Zone Warfare VOIP on CachyOS and Proton

Date: 2026-11-03

## Finding

GZW's ODIN voice room fails during socket setup under the tested CachyOS Proton
configuration. This is distinct from the microphone working in Discord and Steam.
The latest log still ends the ODIN room with `OS Error 10045` after a fresh game
launch. Microsoft defines Winsock 10045 (`WSAEOPNOTSUPP`) as “operation not
supported”: <https://learn.microsoft.com/en-us/windows/win32/winsock/windows-sockets-error-codes-2>.

The related GZW 0.5 Proton report attributes this error to ODIN querying
`IPV6_V6ONLY` on an IPv4 UDP socket and documents a narrow Wine `ws2_32.dll`
workaround: <https://github.com/Golden-Icon/GZW-0.5-VOIP-FIX>.

## Log evidence

Log: `pfx/drive_c/users/steamuser/AppData/Local/GZW/Saved/Logs/GZW.log`.

- Across launches, Unreal reported `Audio Device Manager Initialization Failed`
  and ODIN could not retrieve the audio-device notification subsystem.
- With the ALSA Wine driver, the log also repeated
  `WasapiCapture ... IAudioClient3::GetMixFormat -> 0x8889000A`.
- Switching the prefix to PulseAudio removed those repeated `GetMixFormat`
  errors in subsequent logs, but did not restore VOIP.
- After the attempted Winsock workaround and DLL overrides, a fresh launch still
  logged `room connection closed: OS Error 10045` (latest observed at line 92).
- GZW also reported that a previously saved output-device ID was unavailable and
  fell back to the default. The user confirmed the in-game selections were
  Default for input and output; the other listed outputs were HDMI and a PS5
  controller.

## Changes tried

- `protontricks 2479810 sound=alsa`, then `sound=pulse`.
- Applied the community workaround to a private copy of the prefix's 64-bit
  `ws2_32.dll`. The patcher reported `PATCHED`; patched DLL SHA-256 was
  `00c8c12afacfe39b6ed0d60ab7665985f6d9d1af6e0c5fca20dc13b4a8d62b19`.
- Added `ws2_32=native,builtin` overrides in the GZW prefix and for
  `GZWClientSteam-Win64-Shipping.exe`.

These changes did not fix VOIP. The shared Proton installation itself was not
patched. No isolated patched Proton tool was built or tested. The in-game HDMI
and controller output choices were not tested; the persistent ODIN socket error
made them unlikely to address the observed failure.

## Restoration record

Before the audio changes, `user.reg` was backed up to
`/tmp/gzw-2479810-user.reg.before-alsa` with SHA-256
`e6cff4870d7144f40f6ce125ab087d9458fd9dbda02ed1cd91c0d56f6a7d2a3b`.
Restoration completed: `user.reg` now matches that backup byte-for-byte, which
removes the ALSA/Pulse selection and both Winsock DLL overrides. The original
`system32/ws2_32.dll` symlink to the installed `proton-cachyos-slr` DLL is back
in place. The attempted patched DLL and its backup were moved to `/tmp` as
`gzw-2479810-ws2_32.dll.patched` and
`gzw-2479810-ws2_32.dll.patch-backup`; no patched DLL remains in the prefix.

GZW itself rewrote `Saved/Config/WindowsClient/GameUserSettings.ini` during
launches; that file was not directly edited or reset because no pre-change copy
was captured. The game was set to Default for input and output, as confirmed by
the user. No other files in the shader repository were changed for this VOIP
troubleshooting task.
