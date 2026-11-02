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
	disable_while_typing = true,
})

-- This separate Synaptics interface can get stuck holding LEFT and block
-- touchpad clicks. Keep the working touchpad interface above enabled.
hl.device({
	name = "syna2393:00-06cb:7a13-mouse",
	enabled = false,
})

hl.device({
	name = "at-translated-set-2-keyboard",
	enabled = false,
})
