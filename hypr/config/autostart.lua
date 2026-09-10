-- Session startup commands.
-- https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
	hl.exec_cmd("helium-browser")
	hl.exec_cmd("ghostty")
	hl.exec_cmd("hypridle")
	hl.exec_cmd("waybar")
	hl.exec_cmd("killall -q awww; sleep .5; awww-daemon")
end)
