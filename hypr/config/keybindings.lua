-- Keybindings.
-- https://wiki.hypr.land/Configuring/Basics/Binds/

local main_mod = "SUPER"
local home = os.getenv("HOME")
local toggle_rofi = home .. "/.config/hypr/scripts/toggle_rofi"
local screenshot = home .. "/.config/hypr/scripts/screenshot"
-- scripts/wall_select (Rust, built by scripts/install); the rofi script
-- remains as a fallback until it's removed.
local wall_select = home .. "/.local/bin/wall_select"
local binary = io.open(wall_select)
if binary then
	binary:close()
else
	wall_select = home .. "/.config/hypr/scripts/wall_select"
end

hl.bind(main_mod .. " + Q", hl.dsp.window.close())
hl.bind(main_mod .. " + M", hl.dsp.exit())
-- Lock through logind so hypridle's lock_cmd stays the only hyprlock launcher.
hl.bind(main_mod .. " + minus", hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(main_mod .. " + SPACE", hl.dsp.exec_cmd(toggle_rofi))
hl.bind(main_mod .. " + W", hl.dsp.exec_cmd(wall_select))
hl.bind(main_mod .. " + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(main_mod .. " + P", hl.dsp.exec_cmd("hyprpicker -a"))
-- Zen: show/hide waybar.
hl.bind(main_mod .. " + Z", hl.dsp.exec_cmd("pkill -USR1 -x waybar"))
-- Development build; replace this path when Hyprcast is installed.
hl.bind(main_mod .. " + D", hl.dsp.exec_cmd(home .. "/personal/hyprcast/build/debug/overlay/hyprcast-overlay toggle"))
hl.bind(main_mod .. " + V", hl.dsp.exec_cmd(home .. "/personal/hyprcast/build/debug/overlay/hyprcast-overlay restart"))

-- Notifications.
hl.bind(main_mod .. " + N", hl.dsp.exec_cmd("dunstctl close"))
hl.bind(main_mod .. " + Y", hl.dsp.exec_cmd("dunstctl action"))

hl.bind(main_mod .. " + O", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/toggle_swap_space"))

-- Screenshots: notification's Edit action (click or Super+Y) opens satty.
hl.bind(main_mod .. " + C", hl.dsp.exec_cmd(screenshot .. " region copy"))
hl.bind(main_mod .. " + SHIFT + C", hl.dsp.exec_cmd(screenshot .. " region save"))
hl.bind(main_mod .. " + S", hl.dsp.exec_cmd(screenshot .. " full copy"))
hl.bind(main_mod .. " + SHIFT + S", hl.dsp.exec_cmd(screenshot .. " full save"))

-- Move focus with the home-row keys.
hl.bind(main_mod .. " + H", hl.dsp.focus({ direction = "l" }))
hl.bind(main_mod .. " + J", hl.dsp.focus({ direction = "d" }))
hl.bind(main_mod .. " + K", hl.dsp.focus({ direction = "u" }))
hl.bind(main_mod .. " + L", hl.dsp.focus({ direction = "r" }))

for workspace = 1, 4 do
	hl.bind(main_mod .. " + " .. workspace, hl.dsp.focus({ workspace = workspace }))
	hl.bind(
		main_mod .. " + SHIFT + " .. workspace,
		hl.dsp.window.move({
			workspace = workspace,
			follow = false,
		})
	)
end

hl.bind(
	main_mod .. " + SHIFT + O",
	hl.dsp.window.move({
		workspace = 5,
		follow = false,
	})
)

hl.bind(main_mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(main_mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind(main_mod .. " + R", hl.dsp.submap("fastedit"))
hl.define_submap("fastedit", function()
	hl.bind("L", hl.dsp.window.resize({ x = 20, y = 0, relative = true }))
	hl.bind("H", hl.dsp.window.resize({ x = -20, y = 0, relative = true }))
	hl.bind("K", hl.dsp.window.resize({ x = 0, y = -20, relative = true }))
	hl.bind("J", hl.dsp.window.resize({ x = 0, y = 20, relative = true }))
	hl.bind("R", hl.dsp.layout("togglesplit"))
	hl.bind("equal", hl.dsp.layout("splitratio 1.0 exact"))

	hl.bind(main_mod .. " + H", hl.dsp.window.swap({ direction = "l" }))
	hl.bind(main_mod .. " + L", hl.dsp.window.swap({ direction = "r" }))
	hl.bind(main_mod .. " + K", hl.dsp.window.swap({ direction = "u" }))
	hl.bind(main_mod .. " + J", hl.dsp.window.swap({ direction = "d" }))

	hl.bind(main_mod .. " + R", hl.dsp.submap("reset"))
	hl.bind("escape", hl.dsp.submap("reset"))
end)

local repeating_locked = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%+"), repeating_locked)
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"), repeating_locked)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s 5%+"), repeating_locked)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl --min-value=1200 s 5%-"), repeating_locked)

local locked = { locked = true }
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), locked)
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), locked)
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), locked)
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), locked)
