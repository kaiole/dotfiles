require("blink.cmp").setup({
	snippets = {
		preset = "luasnip",
	},
	sources = {
		default = { "snippets", "lsp", "path", "buffer", "obsidian" },
		providers = {
			snippets = {
				score_offset = 100,
			},
			obsidian = {
				name = "Obsidian",
				module = "blink_obsidian",
				score_offset = 12,
        opts = {
          include_unresolved_wiki_links = true,
        },
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
