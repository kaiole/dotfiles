local scaffold = require("config.actions.scaffold")

local M = {}

local files = {
	{ name = ".clangd", filetype = "yaml", trigger = "clangd" },
	{ name = ".clang-format", filetype = "yaml", trigger = "fmt" },
	{ name = ".clang-tidy", filetype = "yaml", trigger = "tidy" },
	{ name = "CMakePresets.json", filetype = "json", trigger = "cmpresets" },
	{ name = ".gitignore", lines = { "/build/", ".cache/" } },
	{ name = "CMakeLists.txt", lines = {} },
	{ name = "cmake/warnings.cmake", lines = {} },
}

local function create(directory_argument)
	local directory = scaffold.directory(directory_argument)
	local created, skipped = scaffold.write(directory, files)
	local lists = vim.fs.joinpath(directory, "CMakeLists.txt")
	if vim.fn.isdirectory(lists) == 0 then
		vim.cmd.edit(vim.fn.fnameescape(lists))
	end
	vim.notify(scaffold.summary("Cpp", directory, created, skipped))
end

function M.create(directory_argument)
	return scaffold.run("Cpp", create, directory_argument)
end

return M
