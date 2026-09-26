# Architecture

```
   Alt+Space
       |
       v
  ostt-viz-launch  --->  ghostty popup  --->  ostt-viz  (recorder front-end)
       |                                                  |
       | second press sends SIGUSR1                       | pw-record 16 kHz mono
       |                                                  v
       |                                            growing WAV file
       |                                                  |
       |                                       live FFT -> green/yellow/red bars
       |                                                  |
       |                                       on stop: ffmpeg -> 16 kHz s16
       |                                                  |
       |                                                  v
       |                                          ostt transcribe
       |                                       (local whisper.cpp, base)
       |                                                  |
       |                                       wl-copy  ->  clipboard
       v                                                  |
  focus({last=true})  <----------------------------------- +
       |
       v
  /tmp/ostt-viz-paste-flag  --->  Hyprland watcher  --->  send_key_state Ctrl+V
```

## Components

| File | Role |
|---|---|
| `bin/ostt-viz` | the recorder front-end and analyzer. Owns capture, FFT, rendering, and the handoff to transcription. |
| `bin/ostt-viz-launch` | single-key toggle. Starts the popup, or sends `SIGUSR1` to stop an in-progress recording. |
| `scripts/speak.sh` | text to speech. Piper synthesis to a WAV, then `pw-play` on a pinned sink. |
| `scripts/dictate.py` | thin wrapper around faster-whisper for one-shot transcription. |
| `scripts/build_player.py` | builds the captioned audio player used by the in-session listen-and-read tool. |
| `plugin/dyslexia.ts` | opencode plugin exposing speech tools to the model. |
| `bindings.lua` | keybindings plus the auto-paste watcher. The watcher must live here. |

## Why the front-end was replaced

ostt draws its spectrum using only the terminal's default foreground
colour. It emits no colour escape sequences at all, and the compiled binary
exposes no colour configuration, so the bars are always whatever the
terminal theme's foreground happens to be. On this setup that was white.

Recompiling ostt would fix it but needs network access and a Rust
toolchain. Replacing the front-end does not: the spectrum becomes
ANSI truecolor, which the terminal already supports.

Transcription is left to ostt because it already works, runs the local
whisper.cpp daemon, and handles the model registry.

## The analyzer

- `pw-record` writes 16 kHz mono s16 PCM into a WAV whose header is
  44 bytes, so the render loop can just `read()` forward and slice the
  last 4096 bytes as 2048 samples.
- A 2048-point Hanning-windowed rFFT is mapped onto `cols - 10` log-spaced
  bands from 70 Hz to 12 kHz.
- Each band is normalised against the loudest bin in the frame, then scaled
  by `drive`, derived from the frame's absolute RMS level. Scaling by
  absolute level rather than an auto-gain reference is deliberate: with
  auto-gain even a whisper pins the meter to full scale and the green end
  of the gradient never appears.
- Colour thresholds: below 0.38 green, 0.46 to 0.72 yellow, above 0.82 red,
  with short blends between. Bars are drawn from cell midpoints so any
  audible signal lights the bottom row.
- Rendering is full-screen with absolute cursor addressing
  (`ESC[row;1H`) and the analyzer anchored to the last rows, so it stays
  put while the terminal is resized.

## Why auto-paste is dispatched from Hyprland

Keystroke injection into another Wayland client needs either the
virtual-keyboard protocol, which this compositor does not expose, or
Hyprland's own `send_key_state`. The latter only delivers from inside the
running config, so the recorder cannot trigger it directly.

The recorder therefore does what it can from outside — restore focus, then
drop a flag file — and a watcher inside `bindings.lua` polls for that file
and performs the paste. The watcher claims the flag with `os.rename`, which
is atomic, so a reload that leaves two watchers alive cannot paste twice.
