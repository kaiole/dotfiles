-- The CMake project around a path, for snippet defaults and :CppLib. Reads
-- saved files only.
local M = {}

-- C++/CMake identifier for a file or directory name: order-book -> order_book.
-- Directories keep their own names; this is the only conversion.
function M.identifier(name)
	return (name:gsub("[^%w_]", "_"))
end

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
	return M.identifier(vim.fs.basename(vim.fn.getcwd()))
end

-- The library directory/CMakeLists.txt defines, as its <project>::<name>
-- alias, or nil if it defines none.
function M.library(directory)
	local ok, lines = pcall(vim.fn.readfile, vim.fs.joinpath(directory, "CMakeLists.txt"))
	return ok and table.concat(lines, "\n"):match("add_library%s*%(%s*([%w_]+::[%w_]+)%s+ALIAS") or nil
end

-- The CMakeLists.txt that would add_subdirectory(directory), if any.
function M.parent_lists(directory)
	return vim.fs.find("CMakeLists.txt", { path = vim.fs.dirname(directory), upward = true })[1]
end

return M
