# Setup

## Dependencies

```bash
# transcription
#   ostt provides the local whisper.cpp backend
pipx install ostt            # or your distribution's package

# speech + spectrum rendering
python3 -m venv ~/.local/opencode-assist
~/.local/opencode-assist/bin/pip install piper-tts numpy

# system tools
sudo pacman -S pipewire pipewire-pulse ghostty ffmpeg
```

`speak.sh` expects the virtualenv at `~/.local/opencode-assist` and the
piper voice at `~/.local/share/piper/voices`. Adjust the constants at the
top of `scripts/speak.sh` if your layout differs.

## Voices

The default is `en_US-amy-medium`, a natural American female voice.

```bash
mkdir -p ~/.local/share/piper/voices
curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx
curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json
```

Male alternatives ship in the same tree: `en_US-lessac-medium`,
`en_US-lessac-low`. Change `MODEL` in `scripts/speak.sh` to switch.

## Audio devices

This is the single most common source of "it records but the transcript is
empty". Always check which device is actually being used.

```bash
pactl list short sources     # inputs
pactl list short sinks       # outputs
pactl get-default-source
pactl get-default-sink
```

Plugging in a USB soundcard or headset can silently become the system
default for **both** directions. If nothing comes out, or the recording is
flat silence, that is almost always why.

Verify a source actually carries signal before trusting it:

```bash
pw-record --format=s16 --rate=16000 --channels=1 \
  --target alsa_input.pci-0000_03_00.6.HiFi__Mic1__source /tmp/probe.wav
```

Then measure it — anything under about -50 dBFS is effectively silence:

```bash
python3 -c "
import wave,struct,math
w=wave.open('/tmp/probe.wav'); d=w.readframes(w.getnframes())
s=struct.unpack('<%dh'%(len(d)//2),d)
print('%.1f dBFS'%(20*math.log10(max(math.sqrt(sum(x*x for x in s)/len(s)),1)/32768)))
"
```

### Pinning devices

Two independent mechanisms, both recommended:

- `speak.sh` sets `SINK` to the laptop speaker and falls back to the system
  default if that sink disappears.
- `ostt.toml` sets `device = "default"`, and the system default source is
  pointed at the real microphone with
  `pactl set-default-source <source>`.

Note that ostt passes its `device` value straight to ALSA, so a PipeWire
node name such as `alsa_input.pci-...__Mic1__source` will hang the recorder
forever. Use `"default"`, an index, or an ALSA device name.

## Models

Transcription quality versus speed, from `config/ostt.toml`:

```toml
[transcription]
provider = "whisper"
model = "base"     # tiny, base, small, medium
```

`base` transcribes a ten second clip in roughly one to two seconds on CPU.

## Fonts

The analyzer draws with plain ASCII (`#` for bars, `@` for peak hold) on
purpose. Block-drawing characters render as mojibake in terminals whose
pty charset is not UTF-8, which is common for windows spawned from a
keybind. ASCII renders correctly everywhere, including dot-matrix faces.

## First run

```bash
# 1. copy something to the clipboard
echo "hello world" | wl-copy

# 2. start dictation, talk, press Alt+Space again
# 3. read the clipboard aloud
```

If the transcript does not appear, work through
[docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md).
