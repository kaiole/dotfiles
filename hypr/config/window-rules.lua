-- Window and workspace rules.
-- https://wiki.hypr.land/Configuring/Basics/Window-Rules/

local workspace_rules = {
	{ class = "com.mitchellh.ghostty", workspace = "1" },
	{ class = "helium", workspace = "2" },
	{ class = "gimp", workspace = "3" },
	{ class = "com.obsproject.Studio", workspace = "3" },
	{ class = "resolve", workspace = "3" },
	{ class = "codex-desktop", workspace = "3" },
	{ class = "Spotify", workspace = "4" },
	{ class = "discord", workspace = "4" },
	{ class = "md.obsidian.Obsidian", workspace = "name:swap" },
}

for _, rule in ipairs(workspace_rules) do
	hl.window_rule({
		match = { class = rule.class },
		workspace = rule.workspace,
	})
end

hl.window_rule({
	match = { class = "sioyek" },
	opacity = "0.60",
})

hl.window_rule({
	match = { class = "md.obsidian.Obsidian" },
	opacity = "0.60",
})

hl.window_rule({
	match = { class = ".*" },
	suppress_event = "maximize",
})
