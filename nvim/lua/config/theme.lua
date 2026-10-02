-- Active palette from ~/dotfiles/theme/palettes (switch with `theme set <name>`).
local M = {}

local dotfiles = vim.fs.dirname(vim.fn.resolve(vim.fn.stdpath("config")))
local loader = dofile(dotfiles .. "/theme/load.lua")

function M.palette()
	local ok, palette = pcall(loader.palette)
	if ok then
		return palette
	end
	vim.notify(palette .. "; falling back to " .. loader.default, vim.log.levels.WARN)
	return (loader.palette(loader.default))
end

function M.apply()
	vim.cmd.colorscheme("palette") -- nvim/colors/palette.lua
end

-- Called by `theme set` on every running nvim server.
function M.reload()
	-- :colorscheme clears plugin `default = true` links that are only set once at load; restore them.
	local defaults = {}
	for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
		if hl.default and hl.link then
			defaults[name] = hl.link
		end
	end

	M.apply()

	for name, link in pairs(defaults) do
		if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = name })) then
			vim.cmd.highlight("clear", name)
			vim.api.nvim_set_hl(0, name, { link = link, default = true })
		end
	end
end

return M
