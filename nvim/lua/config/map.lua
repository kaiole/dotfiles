vim.keymap.set({ "n", "i", "v", "o" }, "<C-c>", "<Esc>", { silent = true })
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "<C-o>", "<C-o>zz")
vim.keymap.set("n", "<C-i>", "<C-i>zz")
vim.keymap.set("n", "G", "Gzz")
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
vim.keymap.set("n", "<leader>c", function()
	if not vim.env.TMUX or not vim.env.TMUX_PANE then
		vim.notify("The floating shell requires tmux", vim.log.levels.WARN)
		return
	end

	vim.system({
		"tmux",
		"new-pane",
		"-O",
		"-A",
		"-B",
		"single",
		"-t",
		vim.env.TMUX_PANE,
		"-c",
		vim.fn.getcwd(),
		"-x",
		"85%",
		"-y",
		"80%",
		-- Resolve the themed popup styles at draw time, including after theme reloads.
		"-S",
		"#{popup-border-style}",
		"-R",
		"#{popup-border-style}",
		"-s",
		"#{popup-style}",
		";",
		"move-pane",
		"-P",
		"centre",
	}, { text = true }, function(result)
		if result.code ~= 0 then
			vim.schedule(function()
				vim.notify("tmux floating shell failed: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
			end)
		end
	end)
end, { desc = "Open tmux floating shell" })

require("config.sessionizer").setup()
