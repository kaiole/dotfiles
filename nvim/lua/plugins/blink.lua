require("blink.cmp").setup({
	snippets = {
		preset = "luasnip",
	},
	sources = {
		default = { "snippets", "lsp", "path", "buffer", "frontmatter_tags" },
		providers = {
			frontmatter_tags = {
				name = "Tags",
				module = "config.frontmatter_tags",
				score_offset = 12,
			},
			snippets = {
				score_offset = 5,
			},
		},
	},
	keymap = {
		preset = "default",
		["<Tab>"] = false,
		["<C-s>"] = { "show_signature", "hide_signature", "fallback" },
		["<C-k>"] = false,
	},
	signature = {
		enabled = true,
		trigger = {
			enabled = false,
		},
	},
	completion = {
		documentation = { auto_show = true, auto_show_delay_ms = 500 },
		menu = {
			auto_show = true,
			draw = {
				treesitter = { "lsp" },
				columns = { { "label", "label_description", gap = 1 }, { "kind" } },
			},
		},
	},
})
