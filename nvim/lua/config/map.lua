vim.keymap.set({ "n", "i", "v", "x", "s", "o" }, "<C-c>", "<Esc>", { silent = true })
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "<C-o>", "<C-o>zz")
vim.keymap.set("n", "<C-i>", "<C-i>zz")
vim.keymap.set("n", "G", "Gzz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
-- Leave Visual mode to update the selection marks, then move without opening the command line.
vim.keymap.set("v", "J", "<Esc><Cmd>'<,'>move '>+1<CR>gv=gv")
vim.keymap.set("v", "K", "<Esc><Cmd>'<,'>move '<-2<CR>gv=gv")
vim.keymap.set({ "n", "v", "x" }, "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])
vim.keymap.set({ "n", "v" }, "<leader>d", '"_d')
vim.keymap.set("n", "<leader>c", ":!", { desc = "Run shell command" })

local markdown = require("config.actions.markdown")

local function wrap_selection_in_blockquote()
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
	markdown.wrap_in_blockquote(vim.fn.line("'<"), vim.fn.line("'>"))
end

vim.api.nvim_create_autocmd("FileType", {
	pattern = "markdown",
	callback = function(event)
		vim.keymap.set("x", "<C-g>", wrap_selection_in_blockquote, {
			buffer = event.buf,
			desc = "Wrap selection in a blockquote",
		})
	end,
})

vim.keymap.set("n", "<C-f>", function()
	vim.fn.jobstart({ vim.fn.expand("~/.local/bin/tmux-sessionizer") }, { detach = true })
end, { silent = true })
