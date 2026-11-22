vim.keymap.set({ "n", "i", "v", "o" }, "<C-c>", "<Esc>", { silent = true })
-- One :normal! instead of a "<C-d>zz" rhs: Neovim can redraw between a
-- mapping's keys, flashing the pre-zz scroll for a frame (e.g. <C-d> at the top).
local function centered(keys)
	return function()
		local count = vim.v.count > 0 and vim.v.count or ""
		vim.cmd.normal({ args = { count .. vim.keycode(keys) .. "zz" }, bang = true })
	end
end
for _, keys in ipairs({ "<C-d>", "<C-u>", "<C-o>", "<C-i>", "G" }) do
	vim.keymap.set("n", keys, centered(keys))
end
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
-- "x", not "v": "v" also covers Select mode, where typing J/K into a snippet
-- placeholder would move lines instead of inserting text.
-- Leave Visual mode to update the selection marks, then move without opening the command line.
vim.keymap.set("x", "J", "<Esc><Cmd>'<,'>move '>+1<CR>gv=gv")
vim.keymap.set("x", "K", "<Esc><Cmd>'<,'>move '<-2<CR>gv=gv")
vim.keymap.set({ "n", "x" }, "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])
vim.keymap.set({ "n", "x" }, "<leader>d", '"_d')
vim.keymap.set("n", "<leader>w", function()
	vim.wo.wrap = not vim.wo.wrap
end, { desc = "Toggle line wrap" })

require("config.sessionizer").setup()
