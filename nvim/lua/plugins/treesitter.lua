local treesitter_languages = {
	"lua",
	"vim",
	"vimdoc",
	"query",
	"javascript",
	"typescript",
	"tsx",
	"c",
	"cpp",
	"cmake",
	"json",
	"yaml",
	"css",
	"markdown",
	"markdown_inline",
	"bash",
	"toml",
	"rust",
	"python",
}

require("nvim-treesitter").setup({
	install_dir = vim.fn.stdpath("data") .. "/site",
})

require("nvim-treesitter").install(treesitter_languages)

vim.api.nvim_create_autocmd("FileType", {
	callback = function()
		pcall(vim.treesitter.start)
	end,
})
