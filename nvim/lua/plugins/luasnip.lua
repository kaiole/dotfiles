require("luasnip").setup({
	keep_roots = true,
	link_roots = true,
	link_children = true,
	exit_roots = false,
	update_events = "InsertLeave",
})

require("luasnip.loaders.from_lua").load({ paths = vim.fn.stdpath("config") .. "/snippets" })

local ls = require("luasnip")

vim.keymap.set({ "i", "s" }, "<C-j>", function()
	ls.jump(1)
end, { silent = true })

vim.keymap.set({ "i", "s" }, "<C-k>", function()
	ls.jump(-1)
end, { silent = true })

vim.keymap.set({ "i", "s" }, "<C-n>", function()
	if ls.choice_active() then
		ls.change_choice(1)
	end
end, { silent = true })

vim.keymap.set({ "i", "s" }, "<C-p>", function()
	if ls.choice_active() then
		ls.change_choice(-1)
	end
end, { silent = true })
