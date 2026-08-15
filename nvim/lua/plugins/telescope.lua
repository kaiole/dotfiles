local square_borders = { "─", "│", "─", "│", "┌", "┐", "┘", "└" }

require("telescope").setup({
	defaults = {
		preview = { treesitter = true },
		mappings = {
			n = {
				["<C-c>"] = require("telescope.actions").close,
			},
		},
		file_ignore_patterns = {
			".obsidian",
			".tmp/",
			".DS_Store",
			"build/",
			"node_modules/",
			"target/",
			".git/",
			".cache/",
			".next/",
      "%.pdf$",
      ".venv/",
      "__pycache__/",
      ".egg.info/",
      "%.png$",
      "%.jpg$",
      "%.gif$",
		},
	},
	pickers = {
		find_files = {
			theme = "dropdown",
			borderchars = square_borders,
			no_ignore = true,
			hidden = true,
		},
		live_grep = {
			theme = "dropdown",
			borderchars = square_borders,
		},
		help_tags = {
			theme = "dropdown",
			borderchars = square_borders,
		},
		git_files = {
			theme = "dropdown",
			borderchars = square_borders,
		},
		diagnostics = {
			theme = "dropdown",
			borderchars = square_borders,
		},
	},
	extensions = {
		fzf = {
			fuzzy = true,
			override_generic_sorter = true,
			override_file_sorter = true,
			case_mode = "smart_case",
		},
	},
})

vim.keymap.set("n", "<leader>ff", ":Telescope find_files<CR>")
vim.keymap.set("n", "<leader>gr", ":Telescope live_grep<CR>")
vim.keymap.set("n", "<leader>gf", ":Telescope git_files<CR>")
vim.keymap.set("n", "<leader>ht", ":Telescope help_tags<CR>")
vim.keymap.set("n", "<leader>vd", ":Telescope diagnostics<CR>")
