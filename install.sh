#!/bin/bash
# Install Open Road. Prints the keybinding lines to add; does not edit
# your Hyprland config for you.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
ASSIST="$HOME/.local/opencode-assist"
CFG="$HOME/.config"

say()  { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

echo "Checking dependencies..."
missing=()
for c in pw-record pw-play pactl ffmpeg ghostty hyprctl ostt python3; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if [ ${#missing[@]} -gt 0 ]; then
  warn "missing: ${missing[*]}"
  warn "install these before using the tools"
fi

if [ ! -x "$ASSIST/bin/python" ]; then
  warn "no virtualenv at $ASSIST"
  say "create one with:"
  say "  python3 -m venv $ASSIST && $ASSIST/bin/pip install piper-tts numpy"
else
  "$ASSIST/bin/python" -c "import numpy" 2>/dev/null || warn "numpy missing in $ASSIST"
fi

VOICE_DIR="$HOME/.local/share/piper/voices"
if [ ! -f "$VOICE_DIR/en_US-amy-medium.onnx" ]; then
  warn "piper voice not found in $VOICE_DIR"
  say "see docs/SETUP.md for the download URL"
fi

echo
echo "Installing scripts..."
mkdir -p "$BIN" "$ASSIST" "$CFG/opencode/plugin" "$CFG/ostt"
install -m 755 "$SRC/bin/ostt-viz"        "$BIN/ostt-viz"
install -m 755 "$SRC/bin/ostt-viz-launch" "$BIN/ostt-viz-launch"
install -m 755 "$SRC/scripts/speak.sh"    "$ASSIST/speak.sh"
install -m 644 "$SRC/scripts/dictate.py"  "$ASSIST/dictate.py"
install -m 644 "$SRC/scripts/build_player.py" "$ASSIST/build_player.py"
say "$BIN/ostt-viz"
say "$BIN/ostt-viz-launch"
say "$ASSIST/speak.sh"

echo
echo "Optional config files (NOT overwritten if they already exist):"
for pair in "$CFG/ostt/ostt.toml:ostt.toml" \
            "$CFG/opencode/plugin/dyslexia.ts:plugin/dyslexia.ts" \
            "$CFG/opencode/AGENTS.md:AGENTS.md"; do
  dst="${pair%%:*}"; src="${pair##*:}"
  if [ -e "$dst" ]; then
    say "skip $dst (exists)"
  else
    mkdir -p "$(dirname "$dst")"
    install -m 644 "$SRC/$src" "$dst"
    say "installed $dst"
  fi
done

cat <<'MSG'

Done. Add these to your Hyprland bindings.lua, then run: hyprctl reload

  o.bind("ALT + SPACE", "Dictate (spectrum)", "'$HOME/.local/bin/ostt-viz-launch'")
  o.bind("SUPER + SHIFT + V", "TTS read aloud", "'$HOME/.local/opencode-assist/speak.sh'")

Do not bind TTS to Ctrl+Super+V - omarchy's clipboard manager already owns
that chord. See docs/KEYBINDS.md.

The auto-paste watcher must also live in bindings.lua. Copy the
viz_watch_paste_flag function from config/hypr-bindings.lua.
MSG
