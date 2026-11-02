require("oil").setup({
	default_file_explorer = true,
	keymaps = {
		["<C-c>"] = false,
	},
	view_options = {
		show_hidden = true,
	},
	skip_confirm_for_simple_edits = true,
})

vim.keymap.set("n", "<leader>nw", "<CMD>Oil<CR>", { desc = "Open parent directory" })
