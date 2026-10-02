-- Session startup commands.
-- https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
	-- Use the development build until Hyprcast is installed.
	hl.exec_cmd("hyprctl plugin load " .. os.getenv("HOME") .. "/personal/hyprcast/build/debug/plugin/libhyprcast.so")
	hl.exec_cmd("helium-browser")
	hl.exec_cmd("ghostty")
	hl.exec_cmd("hypridle")
	hl.exec_cmd("waybar")
	hl.exec_cmd("killall -q awww; sleep .5; awww-daemon")
end)
