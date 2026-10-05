local path = vim.fn.expand("~/personal/pi-nvim")

-- Local toolkit outside dotfiles; no startup process or model call.
if vim.fn.isdirectory(path) == 0 then
	return
end

vim.opt.runtimepath:prepend(path)
local app = require("config.pi").setup()
local mappings = {}
local function map(mode, lhs, callback, description)
	vim.keymap.set(mode, lhs, callback, { desc = description })
	mappings[#mappings + 1] = { mode = mode, lhs = lhs, callback = callback }
end

map("n", "<leader>pa", function()
	vim.cmd.PiAsk()
end, "Pi: compose question")
map("n", "<leader>pc", function()
	vim.cmd.PiChat()
end, "Pi: conversation")
map("n", "<leader>pf", function()
	vim.cmd.PiAttachFile()
end, "Pi: attach file")
map("n", "<leader>pd", function()
	vim.cmd.PiAttachDiagnostic()
end, "Pi: attach diagnostic under cursor")
map("n", "<leader>pD", function()
	vim.cmd.PiAttachDiagnostics()
end, "Pi: attach buffer diagnostics")
map("n", "<leader>pq", function()
	vim.cmd.PiAttachQuickfix()
end, "Pi: attach quickfix list")
map("x", "<leader>ps", function()
	-- Capture while Visual mode is still active, before changing mode/focus.
	local ok, err = pcall(function()
		app:attach_selection()
	end)
	if ok then
		vim.cmd.normal({ vim.keycode("<Esc>"), bang = true })
	else
		vim.notify("Pi: " .. tostring(err), vim.log.levels.ERROR)
	end
end, "Pi: attach selection")

local group = vim.api.nvim_create_augroup("PiIntegration", { clear = true })
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = group,
	callback = function()
		app:dispose()
	end,
})
local dispose = app.dispose
function app:dispose()
	if self.disposed then
		return
	end
	for _, mapping in ipairs(mappings) do
		local existing = vim.fn.maparg(mapping.lhs, mapping.mode, false, true)
		if existing.callback == mapping.callback then
			vim.keymap.del(mapping.mode, mapping.lhs)
		end
	end
	vim.api.nvim_del_augroup_by_id(group)
	dispose(self)
end

return app
