-- Hyprland configuration entry point.
-- Each required file is evaluated in its own protected scope.

require("config/monitors")
require("config/aesthetic")
require("config/autostart")
require("config/variables")
require("config/input-rules")
-- require("config/hyprcast") -- local Hyprcast development config removed
require("config/keybindings")
require("config/window-rules")

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
