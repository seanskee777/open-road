-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Dictation with the green/yellow/red spectrum analyzer pinned to the bottom.
-- Press once to start, press again to finish and transcribe.
-- Transcription is handled by ostt; only the recorder front-end is ours.
o.bind("ALT + SPACE", "Dictate (spectrum)", "'/home/YOUR_USERNAME/.local/bin/ostt-viz-launch'")
o.bind("ALT + SHIFT + SPACE", "OSTT to default agent", "'/home/YOUR_USERNAME/.local/bin/ostt' launch -p agent")

-- Auto-paste for dictation.
-- Keystroke injection only works from inside the Hyprland config: this
-- compositor has no virtual-keyboard protocol, so `wtype` is a silent no-op
-- and an external `hyprctl eval` of send_key_state does not deliver. The
-- recorder's helper restores focus and then drops a flag file; the watcher
-- below pastes it. Terminals take Shift+Insert, everything else Ctrl+V,
-- matching the built-in Universal paste.
local VIZ_PASTE_FLAG = "/tmp/ostt-viz-paste-flag"

local function viz_active_window_is_terminal()
  local window = hl.get_active_window()
  if not window or not window.tags then
    return false
  end
  for _, tag in ipairs(window.tags) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end
  return false
end

local function viz_send_paste()
  local mods, key = "CTRL", "V"
  if viz_active_window_is_terminal() then
    mods, key = "SHIFT", "Insert"
  end
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

local function viz_watch_paste_flag()
  -- os.rename is atomic, so if a reload ever leaves a second watcher running
  -- only one of them can claim the flag and paste.
  local claimed = VIZ_PASTE_FLAG .. ".claimed"
  if os.rename(VIZ_PASTE_FLAG, claimed) then
    os.remove(claimed)
    viz_send_paste()
  end
  -- Always reschedule, including after a paste, or the watcher dies after the
  -- first dictation and every later one is silently ignored.
  hl.timer(viz_watch_paste_flag, { timeout = 400, type = "oneshot" })
end

os.remove(VIZ_PASTE_FLAG)
viz_watch_paste_flag()

-- TTS playback: copy text, press Super+Shift+V to read aloud with female voice.
-- Press it again while speaking to stop mid-sentence.
-- Keep this on Super+Shift+V: Ctrl+Super+V collides with omarchy's clipboard
-- manager (both resolve to modmask 68) and the clipboard manager wins.
-- Disable auto-speech by writing 0 to ~/.config/opencode-assist/speak.enabled.
o.bind("SUPER + SHIFT + V", "TTS read aloud", "'/home/YOUR_USERNAME/.local/opencode-assist/speak.sh'")
