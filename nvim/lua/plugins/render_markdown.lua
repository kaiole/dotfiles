local p = require("config.theme").palette()

require("render-markdown").setup({
	completions = { lsp = { enabled = true } },
	heading = {
		icons = { "󰼏 ", "󰎨 " },
		backgrounds = {},
	},
	code = {
		highlight_border = false,
		width = "block",
		style = "normal",
	},
	overrides = {
		buftype = {
			nofile = {
				code = {
					highlight = "NormalFloat",
					highlight_inline = "NormalFloat",
					highlight_border = "NormalFloat",
					language_border = "",
				},
			},
		},
	},
})

-- render-markdown links these to ColorColumn by default; clearing them in the
-- colorscheme alone isn't enough, so re-clear once the plugin has loaded.
vim.schedule(function()
	vim.api.nvim_set_hl(0, "RenderMarkdownCode", { bg = "NONE" })
	vim.api.nvim_set_hl(0, "RenderMarkdownCodeInline", { fg = p.fg_muted, bg = "NONE" })
	vim.api.nvim_set_hl(0, "RenderMarkdownCodeBorder", { bg = "NONE" })
end)
