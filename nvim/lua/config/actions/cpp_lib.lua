local cmake = require("config.cmake")
local scaffold = require("config.actions.scaffold")

local M = {}

local files = {
	{ name = "CMakeLists.txt", lines = {} },
	{ name = "tests/CMakeLists.txt", lines = {} },
	{ name = "tests/.clang-tidy", filetype = "yaml", trigger = "tidychill" },
}

local function create(directory_argument, header_only)
	assert(directory_argument and directory_argument ~= "", "usage: CppLib[!] <directory>")
	local directory = scaffold.directory(directory_argument)
	local sources = {}
	-- The library CMakeLists.txt is the same snippet you'd expand by hand.
	local snippet = scaffold.load("cmake", header_only and "cmlibh" or "cmlib", sources)
	local created, skipped = scaffold.write(directory, files, sources)
	local name = vim.fs.basename(directory)
	vim.fn.mkdir(vim.fs.joinpath(directory, "include", cmake.project_name(directory), name), "p")
	if not header_only then
		vim.fn.mkdir(vim.fs.joinpath(directory, "src"), "p")
	end

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

	vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(directory, "CMakeLists.txt")))
	if vim.tbl_contains(created, "CMakeLists.txt") then
		require("luasnip").snip_expand(snippet)
	end
end

-- header_only: an INTERFACE library (cmlibh) instead of STATIC (cmlib).
function M.create(directory_argument, header_only)
	return scaffold.run("CppLib", create, directory_argument, header_only)
end

return M
