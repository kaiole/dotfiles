-- lackluster-red: lackluster.nvim's grays with a muted red accent and no blue.
-- Keys are roles, not colors; see theme/AGENTS.md. Every palette defines every key.
return {
	-- neutrals, ordered from the background toward the foreground
	bg = "#000000", -- base background
	bg_alt = "#080808", -- darkest panels; text on colored chips
	surface = "#191919", -- bars, status lines, selected rows
	border = "#2a2a2a", -- borders, separators
	fg_faint = "#444444", -- comments, hints, placeholders
	fg_dim = "#555555", -- labels, inactive items
	fg_muted = "#7a7a7a", -- secondary text
	fg = "#aaaaaa", -- main text
	fg_strong = "#cccccc", -- emphasized text, active borders
	fg_bright = "#dddddd", -- stronger emphasis
	fg_max = "#deeeed", -- titles, active item, cursor

	-- accents and states
	accent = "#aa6666", -- primary highlight: matches, pointers, mode chips
	accent_muted = "#7a7a7a", -- subdued highlight: search items, links, specials
	accent_alt = "#abab77", -- tertiary highlight
	error = "#aa6666", -- errors, deletions, danger
	success = "#789978", -- success, additions
	warning = "#ffaa88", -- warnings, modified

	-- extra surfaces
	panel = "#101010", -- main content background (pi), Telescope base
	popup = "#1a1a1a", -- popup / custom message background
	statusbar = "#242424", -- status / info background
	error_bg = "#241616", -- background tint behind errors
	whitespace = "#202020", -- visible whitespace characters

	-- syntax (nvim colorscheme, pi code blocks)
	syntax_comment = "#444444",
	syntax_keyword = "#555555", -- if/for/local/...
	syntax_return = "#505050", -- return, yield
	syntax_exception = "#505050", -- try/catch/throw
	syntax_function = "#666666", -- function definitions
	syntax_call = "#555555", -- function calls
	syntax_param = "#7a7a7a", -- parameters
	syntax_variable = "#7a7a7a",
	syntax_member = "#7a7a7a", -- fields, properties
	syntax_constant = "#555555", -- constants, numbers, booleans
	syntax_constant_builtin = "#555555", -- nil, true, ...
	syntax_string = "#aa6666",
	syntax_escape = "#aa6666", -- escapes, regexes, special strings
	syntax_type = "#555555",
	syntax_type_def = "#555555", -- type definitions
	syntax_type_builtin = "#555555", -- int, string, ...
	syntax_builtin = "#444444", -- builtin functions/modules
	syntax_special = "#7a7a7a", -- macros, special chars, preprocessor
	syntax_tag = "#555555", -- markup tags
	syntax_punctuation = "#7a7a7a", -- operators, brackets, delimiters

	-- terminal 16 colors (0-7 normal, 8-15 bright)
	ansi0 = "#080808",
	ansi1 = "#aa6666",
	ansi2 = "#789978",
	ansi3 = "#ffaa88",
	ansi4 = "#7a7a7a",
	ansi5 = "#d7007d",
	ansi6 = "#aaaaaa",
	ansi7 = "#deeeed",
	ansi8 = "#444444",
	ansi9 = "#aa6666",
	ansi10 = "#789978",
	ansi11 = "#ffaa88",
	ansi12 = "#7a7a7a",
	ansi13 = "#d7007d",
	ansi14 = "#aaaaaa",
	ansi15 = "#deeeed",
}
