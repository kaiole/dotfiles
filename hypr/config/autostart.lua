-- Session startup commands.
-- https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
	-- Dark mode for GTK4/libadwaita apps (satty) and the portal; every palette
	-- is dark. Derive this from the palette if a light one is ever added.
	hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
	-- Use the local release build until Hyprcast is installed.
	hl.exec_cmd("hyprctl plugin load " .. os.getenv("HOME") .. "/personal/hyprcast/build/release/plugin/libhyprcast.so")
	hl.exec_cmd("helium-browser")
	hl.exec_cmd("ghostty")
	hl.exec_cmd("hypridle")
	hl.exec_cmd("waybar")
	hl.exec_cmd("awww-daemon")
end)
