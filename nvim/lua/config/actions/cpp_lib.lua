local cmake = require("config.cmake")
local scaffold = require("config.actions.scaffold")

local M = {}

-- A library's files besides its CMakeLists.txt, also written by :CppSolo.
-- The header (a path under include/) and source are the ones the
-- cmlib/cmlibh-style header set and add_library list, so the library
-- configures as soon as it is added.
function M.files(header, name, header_only)
	local list = {
		{ name = "include/" .. header, lines = { "#pragma once" } },
		{ name = "tests/CMakeLists.txt", lines = {} },
		{ name = "tests/.clang-tidy", filetype = "yaml", trigger = "tidychill" },
	}
	if not header_only then
		table.insert(list, 2, { name = "src/" .. name .. ".cpp", lines = { '#include "' .. header .. '"' } })
	end
	return list
end

local function create(directory_argument, header_only)
	assert(directory_argument and directory_argument ~= "", "usage: CppLib[!] <directory>")
	local directory = scaffold.directory(directory_argument)
	local sources = {}
	-- The library CMakeLists.txt is the same snippet you'd expand by hand.
	local snippet = scaffold.load("cmake", header_only and "cmlibh" or "cmlib", sources)
	local name = cmake.identifier(vim.fs.basename(directory))
	local header = cmake.project_name(directory) .. "/" .. name .. "/" .. name .. ".hpp"
	local files = vim.list_extend({ { name = "CMakeLists.txt", lines = {} } }, M.files(header, name, header_only))
	local created, skipped = scaffold.write(directory, files, sources)

	-- Never edit the parent CMakeLists.txt; hand over the line instead.
	local parent = cmake.parent_lists(directory)
	local base = parent and vim.fs.dirname(parent) or vim.fn.getcwd()
	local line = "add_subdirectory(" .. (vim.fs.relpath(base, directory) or directory) .. ")"
	vim.fn.setreg('"', line, "l")
	vim.notify(
		scaffold.summary("CppLib", directory, created, skipped)
			.. "\nAdd to "
			.. (parent or "the parent CMakeLists.txt")
			.. ' (in register "): '
			.. line
	)

	scaffold.open(vim.fs.joinpath(directory, "CMakeLists.txt"))
	if vim.tbl_contains(created, "CMakeLists.txt") then
		require("luasnip").snip_expand(snippet)
	end
end

-- header_only: an INTERFACE library (cmlibh) instead of STATIC (cmlib).
function M.create(directory_argument, header_only)
	return scaffold.run("CppLib", create, directory_argument, header_only)
end

return M
