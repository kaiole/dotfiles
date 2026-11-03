local scaffold = require("config.actions.scaffold")

local M = {}

local files = {
	{ name = ".clangd", filetype = "yaml", trigger = "clangd" },
	{ name = ".clang-format", filetype = "yaml", trigger = "fmt" },
	{ name = ".clang-tidy", filetype = "yaml", trigger = "tidy" },
	{ name = "CMakePresets.json", filetype = "json", trigger = "cmpresets" },
	{ name = ".gitignore", lines = { "/build/", ".cache/", "/CMakeUserPresets.json" } },
	{ name = "CMakeLists.txt", lines = {} },
	{ name = "cmake/warnings.cmake", filetype = "cmake", trigger = "cmwarn" },
	{ name = "cmake/gtest.cmake", filetype = "cmake", trigger = "cmgt" },
	{ name = "cmake/install.cmake", filetype = "cmake", trigger = "cminstall" },
	{ name = "cmake/config.cmake.in", filetype = "cmake", trigger = "cmconfig" },
	-- Executable; the umask decides the final mode, as for the other files.
	{ name = "check", filetype = "sh", trigger = "check", mode = tonumber("777", 8) },
}

-- `trigger` is expanded into the new CMakeLists.txt; extra(directory) lists
-- files written besides the project's.
local function create(command, trigger, extra, directory_argument)
	local directory = scaffold.directory(directory_argument)
	local sources = {}
	-- The top-level CMakeLists.txt is the same snippet you'd expand by hand.
	local snippet = scaffold.load("cmake", trigger, sources)
	local list = vim.list_extend(vim.list_extend({}, files), extra and extra(directory) or {})
	local created, skipped = scaffold.write(directory, list, sources)
	scaffold.open(vim.fs.joinpath(directory, "CMakeLists.txt"))
	vim.notify(scaffold.summary(command, directory, created, skipped))
	if vim.tbl_contains(created, "CMakeLists.txt") then
		require("luasnip").snip_expand(snippet)
	end
end

function M.create(directory_argument)
	return scaffold.run("Cpp", create, "Cpp", "cm", nil, directory_argument)
end

-- :CppSolo: the project is one library at its root, named like cm's default
-- project name, with its header at include/<name>/<name>.hpp.
-- header_only: cmsoloh instead of cmsolo, and no source.
function M.create_solo(directory_argument, header_only)
	local function library(directory)
		local name = require("config.cmake").identifier(vim.fs.basename(directory))
		return require("config.actions.cpp_lib").files(name .. "/" .. name .. ".hpp", name, header_only)
	end
	local trigger = header_only and "cmsoloh" or "cmsolo"
	return scaffold.run("CppSolo", create, "CppSolo", trigger, library, directory_argument)
end

return M
