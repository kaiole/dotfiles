-- Appearance and layout.
-- https://wiki.hypr.land/Configuring/Basics/Variables/

local palette = dofile(os.getenv("HOME") .. "/dotfiles/theme/load.lua").palette()
local function rgba(color, alpha)
	return "rgba(" .. color:sub(2) .. (alpha or "ff") .. ")"
end

hl.config({
	general = {
		gaps_in = 2.5,
		gaps_out = 5,
		border_size = 2,
		col = {
			active_border = rgba(palette.fg_max),
			inactive_border = rgba(palette.border, "00"),
		},
		resize_on_border = false,
		allow_tearing = false,
		no_focus_fallback = true,
		layout = "dwindle",
	},

	decoration = {
		rounding = 0,
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		shadow = { enabled = false },
		blur = { enabled = false },
	},

	animations = {
		enabled = false,
	},

	dwindle = {
		preserve_split = true,
		force_split = 2,
	},

	misc = {
		force_default_wallpaper = 0,
		disable_hyprland_logo = true,
		focus_on_activate = true,
		-- Lets a new hyprlock take over if one crashes, instead of a dead lock screen.
		allow_session_lock_restore = true,
	},
})
