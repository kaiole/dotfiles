-- Resolve the active palette. Shared by theme/build.lua and nvim.
local M = {}

M.root = debug.getinfo(1, "S").source:sub(2):match("(.*)/") -- theme/
M.default = "lackluster-red"

local function read(path)
	local f = io.open(path)
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

function M.current()
	local name = read(M.root .. "/current")
	name = name and name:match("^%s*(.-)%s*$")
	return (name and name ~= "") and name or M.default
end

function M.palette(name)
	name = name or M.current()
	local path = M.root .. "/palettes/" .. name .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then
		error("theme: cannot load palette '" .. name .. "': " .. err, 0)
	end
	return chunk(), name
end

return M
