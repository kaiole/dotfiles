-- The CMake project around a path, for snippet defaults and :CppLib. Reads
-- saved files only.
local M = {}

local function declared_project(file)
	local ok, lines = pcall(vim.fn.readfile, file)
	return ok and table.concat(lines, "\n"):match("%f[%w_]project%s*%(%s*([%w_%-]+)") or nil
end

-- Name in the nearest enclosing project(), the namespace of its targets.
-- Falls back to the cwd's name while the root CMakeLists.txt is unwritten.
function M.project_name(path)
	for _, file in ipairs(vim.fs.find("CMakeLists.txt", { path = path, upward = true, limit = math.huge })) do
		local name = declared_project(file)
		if name then
			return name
		end
	end
	return (vim.fs.basename(vim.fn.getcwd()):gsub("[^%w_]", "_"))
end

-- The CMakeLists.txt that would add_subdirectory(directory), if any.
function M.parent_lists(directory)
	return vim.fs.find("CMakeLists.txt", { path = vim.fs.dirname(directory), upward = true })[1]
end

return M
