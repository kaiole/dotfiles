-- Input configuration.
-- https://wiki.hypr.land/Configuring/Basics/Variables/#input

hl.config({
	input = {
		kb_layout = "us",
		kb_variant = "colemak_dh_ortho",
		kb_options = "ctrl:swapcaps",
		repeat_rate = 50,
		repeat_delay = 300,
		follow_mouse = 2,
		accel_profile = "",
		sensitivity = -0.90,
	},

	cursor = {
		no_warps = true,
	},
})

hl.device({
	name = "syna2393:00-06cb:7a13-touchpad",
	accel_profile = "adaptive",
	sensitivity = 0.0,
	scroll_factor = 0.1,
	tap_to_click = false,
})

hl.device({
	name = "at-translated-set-2-keyboard",
	enabled = false,
})
