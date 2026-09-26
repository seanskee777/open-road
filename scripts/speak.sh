#!/bin/bash
# speak.sh - Read TEXT aloud using piper-tts offline female voice.
# Model: en_US-amy-medium (natural American female voice, local, offline)
# Toggle: write 0 to ~/.config/opencode-assist/speak.enabled to disable auto-speech
# Stop: press Super+Shift+V again while speaking to stop playback mid-stream
# Default: length_scale=0.85, volume=1.0
MODEL="/home/d1v1d3dd3v3l0p3r/.local/share/piper/voices/en_US-amy-medium.onnx"
TOGGLE="/home/d1v1d3dd3v3l0p3r/.config/opencode-assist/speak.enabled"
PIDFILE="/home/d1v1d3dd3v3l0p3r/.config/opencode-assist/speak.pid"
WAVFILE="/tmp/opencode_speak.wav"
VENV="/home/d1v1d3dd3v3l0p3r/.local/opencode-assist/bin/python"
# Preferred output: laptop internal speaker.
SINK="alsa_output.pci-0000_03_00.6.HiFi__Speaker__sink"

if [ "${TTS_OFF:-0}" = "1" ]; then
  echo "TTS disabled (TTS_OFF=1)" >&2
  exit 0
fi
if [ -f "$TOGGLE" ] && [ "$(cat "$TOGGLE")" = "0" ]; then
  echo "TTS disabled (toggle file)" >&2
  exit 0
fi

# Second press while audio is genuinely playing = stop it.
# A pidfile is only trusted if the pid is alive AND its cmdline is our player.
# Stale or recycled pids are discarded instead of silencing the next request.
if [ -f "$PIDFILE" ]; then
  read -r OLD_PID OLD_START < "$PIDFILE" 2>/dev/null
  if [ -n "$OLD_PID" ] && [ -r "/proc/$OLD_PID/cmdline" ]; then
    OLD_CMD=$(tr '\0' ' ' < "/proc/$OLD_PID/cmdline" 2>/dev/null)
    case "$OLD_CMD" in
      *pw-play*|*ffmpeg*opencode_s*)
        if [ -n "$OLD_START" ] && [ $(( $(date +%s) - OLD_START )) -lt 120 ]; then
          kill "$OLD_PID" 2>/dev/null
          rm -f "$PIDFILE"
          echo "TTS playback stopped"
          exit 0
        fi
        ;;
    esac
  fi
  rm -f "$PIDFILE"
fi

TEXT="${1:-$(wl-paste 2>/dev/null)}"
if [ -z "$TEXT" ]; then
  echo "No text to speak (provide text as argument or clipboard must have content)" >&2
  exit 1
fi
LENGTH="${2:-0.85}"
VOLUME="${3:-1.0}"

"$VENV" -c "
import sys, os, wave, subprocess, time
sys.path.insert(0, '/home/d1v1d3dd3v3l0p3r/.local/opencode-assist/lib/python3.14/site-packages')
os.chdir('/home/d1v1d3dd3v3l0p3r/.local/share/piper/voices')
from piper import PiperVoice
from piper.config import SynthesisConfig

voice = PiperVoice.load('$MODEL')
config = SynthesisConfig(length_scale=$LENGTH, volume=$VOLUME)
audio_bytes = b''
for c in voice.synthesize(sys.argv[1], syn_config=config):
    audio_bytes += c.audio_int16_bytes

if not audio_bytes:
    sys.stderr.write('piper produced no audio\n')
    sys.exit(1)

with wave.open('$WAVFILE', 'wb') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(22050)
    w.writeframes(audio_bytes)

# Play on the laptop's internal speaker, not the system default sink.
# The JMTek USB soundcard can become the default and its jack is often empty,
# which silently swallows the audio. Falls back to the default sink if absent.
sink = '$SINK'
if 'default' not in sink:
    try:
        out = subprocess.run(['pactl', 'list', 'sinks'], capture_output=True, text=True, timeout=5)
        if ('Name: ' + sink) not in out.stdout:
            sink = 'default'
    except Exception:
        sink = 'default'
proc = subprocess.Popen(['pw-play', '--target', sink, '$WAVFILE'])
with open('$PIDFILE', 'w') as f:
    f.write('%d %d\n' % (proc.pid, int(time.time())))
try:
    proc.wait()
finally:
    try:
        if os.path.exists('$PIDFILE'):
            with open('$PIDFILE') as f:
                parts = f.read().split()
            if parts and parts[0] == str(proc.pid):
                os.remove('$PIDFILE')
    except Exception:
        pass
" "$TEXT"
STATUS=$?
rm -f "$PIDFILE"
exit $STATUS
