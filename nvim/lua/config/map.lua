vim.keymap.set({ "n", "i", "v", "x", "s", "o" }, "<C-c>", "<Esc>", { silent = true })
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "<C-o>", "<C-o>zz")
vim.keymap.set("n", "<C-i>", "<C-i>zz")
vim.keymap.set("n", "G", "Gzz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")
vim.keymap.set({ "n", "v", "x" }, "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])
vim.keymap.set({ "n", "v" }, "<leader>d", '"_d')

local function wrap_in_callout()
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)

	local first_line = vim.fn.line("'<")
	local last_line = vim.fn.line("'>")
	local selected = vim.api.nvim_buf_get_lines(0, first_line - 1, last_line, false)
	local suffix = { "]", ">" }

	for _, line in ipairs(selected) do
		table.insert(suffix, line == "" and ">" or "> " .. line)
	end
	table.insert(suffix, "")
	table.insert(suffix, "")

	vim.api.nvim_buf_set_lines(0, first_line - 1, last_line, false, { "" })
	vim.api.nvim_win_set_cursor(0, { first_line, 0 })

	local ls = require("luasnip")
	ls.snip_expand(ls.snippet("", {
		ls.text_node("> [!"),
		ls.insert_node(1),
		ls.text_node(suffix),
		ls.insert_node(0),
	}))
end

vim.api.nvim_create_autocmd("FileType", {
	pattern = "markdown",
	callback = function(event)
		vim.keymap.set("x", "<leader>c", wrap_in_callout, {
			buffer = event.buf,
			desc = "Wrap selection in a callout",
		})
	end,
})

vim.keymap.set("n", "<C-f>", function()
	vim.fn.jobstart({ vim.fn.expand("~/.local/bin/tmux-sessionizer") }, { detach = true })
end, { silent = true })
