local color = require("lackluster").color

require("lackluster").setup({
	tweak_color = {
		-- Replace Lackluster's slate-blue accents with neutral gray and muted red.
		lack = "#7a7a7a",
		blue = "#aa6666",
		red = "#aa6666",
	},
	tweak_highlight = {
		StatusLine = {
			overwrite = true,
			fg = color.gray8,
			bg = color.gray2,
		},
		ColorColumn = {
			overwrite = true,
			bg = color.gray2,
		},
		StatusLineNC = {
			overwrite = true,
			fg = color.gray6,
			bg = color.gray2,
		},
		NormalFloat = {
			overwrite = true,
			bg = "NONE",
		},
		FloatBorder = {
			overwrite = true,
			bg = "NONE",
		},
		markdownCode = {
			overwrite = true,
			bg = "NONE",
		},
		markdownCodeBlock = {
			overwrite = true,
			bg = "NONE",
		},
		RenderMarkdownCode = {
			overwrite = true,
			bg = "NONE",
		},
		RenderMarkdownCodeInline = {
			overwrite = true,
			fg = color.gray6,
			bg = "NONE",
		},
		RenderMarkdownCodeBorder = {
			overwrite = true,
			bg = "NONE",
		},
		["@markup.strong"] = {
			overwrite = true,
			fg = color.gray4,
			bold = true,
		},
		["@markup.italic"] = {
			overwrite = true,
			fg = color.gray4,
			italic = true,
		},
		MatchParen = {
			overwrite = true,
			bg = color.gray3,
		},
		["@keyword"] = {
			overwrite = false,
			bold = true,
			italic = false,
		},
		["@function"] = {
			overwrite = true,
			link = "@keyword",
		},
		TelescopeMatching = {
			overwrite = true,
			bold = false,
			italic = false,
			fg = "#aa6666",
		},
		TelescopeNormal = {
			overwrite = true,
			bg = "NONE",
		},
		TelescopeBorder = {
			overwrite = true,
			bg = "NONE",
		},
		TelescopePreviewNormal = {
			overwrite = true,
			bg = "NONE",
		},
		TelescopePreviewBorder = {
			overwrite = true,
			bg = "NONE",
		},
		TelescopePromptNormal = {
			overwrite = true,
			bg = "NONE",
		},
		TelescopePromptBorder = {
			overwrite = true,
			bg = "NONE",
		},
		TelescopeResultsNormal = {
			overwrite = true,
			bg = "NONE",
		},
		TelescopeResultsBorder = {
			overwrite = true,
			bg = "NONE",
		},
	},
	tweak_ui = {
		disable_undercurl = true,
		enable_end_of_buffer = true,
	},
	tweak_syntax = {
		comment = color.gray4,
	},
	tweak_background = {
		normal = "none",
		menu = "none",
		popup = "none",
	},
})

vim.cmd("colorscheme lackluster-dark")
