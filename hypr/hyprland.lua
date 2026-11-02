-- Hyprland configuration entry point.
-- Each required file is evaluated in its own protected scope.

require("config/monitors")
require("config/appearance")
require("config/autostart")
require("config/input")
require("config/keybindings")
require("config/window-rules")

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
