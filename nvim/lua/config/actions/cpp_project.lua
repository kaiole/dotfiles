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

local function create(directory_argument)
	local directory = scaffold.directory(directory_argument)
	local sources = {}
	-- The top-level CMakeLists.txt is the same snippet you'd expand by hand.
	local snippet = scaffold.load("cmake", "cm", sources)
	local created, skipped = scaffold.write(directory, files, sources)
	scaffold.open(vim.fs.joinpath(directory, "CMakeLists.txt"))
	vim.notify(scaffold.summary("Cpp", directory, created, skipped))
	if vim.tbl_contains(created, "CMakeLists.txt") then
		require("luasnip").snip_expand(snippet)
	end
end

function M.create(directory_argument)
	return scaffold.run("Cpp", create, directory_argument)
end

return M
