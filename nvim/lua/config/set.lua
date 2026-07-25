vim.g.netrw_banner = 0

vim.o.number = true
vim.o.relativenumber = true
vim.opt.guicursor = { "n-v:block", "i-c:block-blinkon500-blinkoff500" }
vim.o.scrolloff = 8
vim.o.colorcolumn = "80"
vim.o.signcolumn = "yes"
vim.o.winborder = "single"
vim.o.termguicolors = true

vim.g.markdown_recommended_style = false
vim.o.tabstop = 2
vim.o.expandtab = true
vim.o.shiftwidth = 2
vim.o.softtabstop = 2
vim.o.wrap = false
vim.o.smartindent = true
vim.o.incsearch = true
vim.o.ignorecase = true
vim.o.smartcase = true

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "c", "cpp" },
	callback = function()
		vim.opt_local.tabstop = 4
		vim.opt_local.shiftwidth = 4
		vim.opt_local.softtabstop = 4
		vim.opt_local.expandtab = true
	end,
})

vim.o.swapfile = false
vim.o.backup = false
vim.o.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.o.undofile = true
vim.o.confirm = true

vim.api.nvim_create_autocmd("TextYankPost", {
	callback = function()
		vim.highlight.on_yank()
	end,
})
