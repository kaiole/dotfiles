-- Run from nvim/: nvim --headless -u NONE -l tests/snippet_format.lua
-- The C++ workflow snippets must come out the way gw formats them, so neither
-- :Cpp's files nor a hand-expanded snippet ever needs a reformat. Uses gw's
-- formatters (cmake-format, Prettier, shfmt) through the real conform setup.
local config = vim.fn.getcwd()
vim.opt.runtimepath:prepend(config)
vim.cmd.packadd("LuaSnip")
vim.cmd.packadd("conform.nvim")
vim.o.swapfile = false
vim.o.hidden = true
-- Indent options decide some formatters' output (shfmt follows expandtab).
dofile(config .. "/lua/config/set.lua")
dofile(config .. "/lua/plugins/conform.lua")

local ls = require("luasnip")
local conform = require("conform")
local root = vim.fn.tempname()
local count, failures = 0, 0

for _, command in ipairs({ "cmake-format", "shfmt", vim.fn.expand("~/.npm-global/bin/prettier") }) do
	assert(vim.fn.executable(command) == 1, "missing formatter: " .. command)
end

local function test(name, run)
	count = count + 1
	if ls.get_active_snip() then
		ls.unlink_current()
	end
	vim.cmd("enew!")
	local ok, err = xpcall(run, debug.traceback)
	if ok then
		print("PASS " .. name)
	else
		failures = failures + 1
		io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
	end
end

-- Opens `path` (relative to `project`) as an empty, unsaved buffer.
local function open(project, path, filetype)
	path = project .. "/" .. path
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.cmd.edit({ vim.fn.fnameescape(path), bang = true })
	vim.bo.filetype = filetype
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
end

local function lines()
	return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

-- Fails with a diff when gw would change the buffer.
local function expect_formatted()
	local before = lines()
	conform.format({ bufnr = 0, async = false })
	if not vim.deep_equal(before, lines()) then
		error(
			"gw would change it:\n" .. vim.diff(table.concat(before, "\n") .. "\n", table.concat(lines(), "\n") .. "\n")
		)
	end
end

-- Jumps through every field, as <C-j> would, then lets the snippet's
-- scheduled format run.
local function finish()
	while ls.jumpable(1) do
		ls.jump(1)
	end
	vim.wait(20)
end

local function project(name)
	local directory = root .. "/" .. name
	vim.fn.mkdir(directory, "p")
	vim.fn.writefile({ "project(" .. name .. ")" }, directory .. "/CMakeLists.txt")
	return directory
end

-- Where each snippet is expanded; defaults (names, namespace) come from it.
local places = {
	cmake = {
		cm = "CMakeLists.txt",
		cmlib = "libs/%s/CMakeLists.txt",
		cmlibh = "libs/%s/CMakeLists.txt",
		cmgtx = "libs/%s/tests/CMakeLists.txt",
		cmgbx = "libs/%s/bench/CMakeLists.txt",
		cmconfig = "cmake/config.cmake.in",
		default = "cmake/dependency.cmake",
	},
	json = { default = "CMakePresets.json" },
	yaml = {
		clangd = ".clangd",
		fmt = ".clang-format",
		tidychill = "libs/%s/tests/.clang-tidy",
		default = ".clang-tidy",
	},
	sh = { default = "check" },
}

local function static(snippet)
	local types = require("luasnip.util.types")
	for _, node in ipairs(snippet.nodes) do
		if node.type ~= types.textNode and node.type ~= types.exitNode then
			return false
		end
	end
	return true
end

test("the check catches unformatted CMake", function()
	open(project("sanity"), "CMakeLists.txt", "cmake")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "set(  X   1)" })
	assert(not pcall(expect_formatted))
end)

-- Short names keep every line on one line; long ones force the wraps whose
-- layout depends on the names.
for _, names in ipairs({ { "app", "io" }, { "a_rather_long_project_name", "order_book_decoder" } }) do
	local dir = project(names[1])
	for filetype, paths in pairs(places) do
		for _, snippet in ipairs(dofile(config .. "/snippets/" .. filetype .. ".lua")) do
			local place = (paths[snippet.trigger] or paths.default):format(names[2])
			if static(snippet) then
				-- Written verbatim by :Cpp, so the text itself must be formatted.
				test(("%s/%s is formatted as written"):format(filetype, snippet.trigger), function()
					open(dir, place, filetype)
					vim.api.nvim_buf_set_lines(0, 0, -1, false, snippet:get_static_text())
					expect_formatted()
				end)
			else
				test(("%s/%s is formatted once finished (%s)"):format(filetype, snippet.trigger, names[1]), function()
					open(dir, place, filetype)
					ls.snip_expand(snippet)
					finish()
					expect_formatted()
				end)
			end
		end
	end
end

test("finishing a snippet formats only its own lines", function()
	open(project("app"), "libs/io/tests/CMakeLists.txt", "cmake")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "set(  KEEP   1)", "" })
	vim.api.nvim_win_set_cursor(0, { 2, 0 })
	for _, snippet in ipairs(dofile(config .. "/snippets/cmake.lua")) do
		if snippet.trigger == "cmgtx" then
			ls.snip_expand(snippet)
		end
	end
	finish()
	assert(not ls.get_active_snip(), "finished snippet is unlinked")
	local result = lines()
	assert(result[1] == "set(  KEEP   1)", result[1])
	assert(result[2] == "add_executable(io_tests io_test.cpp)", result[2])
end)

vim.cmd("%bwipeout!")
vim.fn.delete(root, "rf")
if failures > 0 then
	error(failures .. "/" .. count .. " tests failed")
end
print("All " .. count .. " snippet format tests passed")
