# Troubleshooting

Real problems, in the order they are worth checking.

## The transcript is empty, but the logs say success

`ostt` reports `transcription request completed` even when it transcribed
silence. The giveaway is the recording level. Anything below about
-50 dBFS is the noise floor:

```bash
python3 -c "
import wave,struct,math
w=wave.open('/tmp/ostt-viz-1234.wav'); d=w.readframes(w.getnframes())
s=struct.unpack('<%dh'%(len(d)//2),d)
print('%.1f dBFS'%(20*math.log10(max(math.sqrt(sum(x*x for x in s)/len(s)),1)/32768)))
"
```

Healthy speech sits between -30 and -10 dBFS. If you see -68 dBFS, the
wrong input is selected. Run the device probe in
[SETUP.md](SETUP.md#pinning-devices).

## The recorder hangs on startup and never draws

`ostt.toml` contains a PipeWire node name in `[audio] device`. ostt hands
that string to ALSA, which cannot parse it, so the recorder starts and then
blocks forever. The symptom is a log that stops after
`Configuration loaded:` with no `Recording device:` line following it.

Use `device = "default"` and fix the system default source instead.

## No sound from text to speech

Audio is being generated correctly but routed to a jack nobody is plugged
into. Check which sink is default:

```bash
pactl get-default-sink
```

If it is a USB soundcard, either plug headphones into it or rely on the
`SINK` pin in `scripts/speak.sh`.

## The TTS key does nothing

Almost always a modifier collision. List every binding on that key and
compare the masks:

```bash
hyprctl -j binds | python3 -c "
import json,sys
for x in json.load(sys.stdin):
    if (x.get('key') or '').endswith('V'):
        print(x.get('modmask'), x.get('key'), x.get('description'))
"
```

`Ctrl+Super+V` and `Super+Ctrl+V` are the same chord and both resolve to
mask 68. omarchy's clipboard manager already owns it. Use `Super+Shift+V`.

## Text is transcribed but never pasted

`wtype` exits 0 and types nothing, because the compositor exposes no
virtual-keyboard protocol. Confirm:

```bash
strings /usr/bin/wtype | grep -i "virtual keyboard"
# Compositor does not support the virtual keyboard protocol
```

Auto-paste therefore has to be dispatched from inside the Hyprland config,
which is why `bindings.lua` contains the watcher function. Verify the
watcher is alive:

```bash
printf ok > /tmp/ostt-viz-paste-flag
sleep 2
[ -f /tmp/ostt-viz-paste-flag ] && echo "watcher dead" || echo "watcher alive"
```

If it reports dead, the timer chain stopped. Every code path in
`viz_watch_paste_flag` must reschedule, including the one that pastes.

## The spectrum renders as mojibake

The popup's pty is decoding UTF-8 as Latin-1. The launcher sets
`LANG`/`LC_ALL` and the recorder forces UTF-8 on stdout, and the drawing
uses ASCII only. If you reintroduce block characters such as `█`, expect
this again on any font that lacks them.

## The popup window is huge and hangs off the bottom of the screen

Ghostty ignored the size flags. Override the window in the launcher, or
set `window-width` / `window-height` in the Ghostty config keyed to
`class=ostt-popup`.

## Playback will not stop, or will not start

The stop-press logic trusts a pid file only when the pid is alive **and**
its command line is the audio player, so a stale or recycled pid can never
swallow the next request. To reset it:

```bash
rm -f ~/.config/opencode-assist/speak.pid
```

## Resetting everything

```bash
pkill -f "bin/ostt-viz$"
rm -f ~/.config/ostt-viz.pid /tmp/ostt-viz-paste-flag* /tmp/ostt-viz-*.wav
hyprctl reload
```
