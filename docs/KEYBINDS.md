# Keybindings

## Default

| Keys | Action | Handler |
|---|---|---|
| `Alt+Space` | start dictation; press again to finish, transcribe and paste | `bin/ostt-viz-launch` |
| `Alt+Shift+Space` | dictate into the default agent | `ostt launch -p agent` |
| `Super+Shift+V` | read the clipboard aloud; press again to stop | `scripts/speak.sh` |
| `Enter` | finish dictation from inside the popup | handled in `bin/ostt-viz` |
| `Space` | pause and resume recording | handled in `bin/ostt-viz` |
| `Esc`, `q` | cancel dictation, discard the recording | handled in `bin/ostt-viz` |

## Modifier masks

Hyprland resolves chords to a bitmask, which is how collisions hide:

| Mask | Chord | Owner |
|---|---|---|
| 64 | `Super+V` | omarchy universal paste |
| 65 | `Super+Shift+V` | text to speech |
| 68 | `Super+Ctrl+V` | omarchy clipboard manager |

`Ctrl+Super+V` and `Super+Ctrl+V` are the same chord. Both resolve to 68,
so anything bound there is shadowed by the clipboard manager.

Audit before binding:

```bash
hyprctl -j binds | python3 -c "
import json,sys
for x in json.load(sys.stdin):
    k = x.get('key') or ''
    if k.endswith('V'):
        print(x.get('modmask'), k, x.get('description'))
"
```

## Adding your own

Inside the popup, the recorder reads single bytes from stdin in cbreak
mode. To add a key, extend the handler in `bin/ostt-viz`:

```python
elif ch == b"p":
    state["profile"] = "low"
```

Keys already claimed: `\r`, `\n`, space, `\x1b`, `q`, `Q`, `\x03`.

## The auto-paste watcher

`bindings.lua` contains `viz_watch_paste_flag`, a 400 ms self-rescheduling
timer. If you refactor it, keep the unconditional reschedule:

```lua
if os.rename(VIZ_PASTE_FLAG, claimed) then
  os.remove(claimed)
  viz_send_paste()
end
hl.timer(viz_watch_paste_flag, { timeout = 400, type = "oneshot" })
```

Returning early after a paste, which is the intuitive thing to write, kills
the watcher after the first dictation and every later one is silently
dropped.

Test it without recording anything:

```bash
printf ok > /tmp/ostt-viz-paste-flag
sleep 2
[ -f /tmp/ostt-viz-paste-flag ] && echo "watcher dead" || echo "watcher alive"
```
