-- Run from nvim/: nvim --headless -u NONE -l tests/cpp_project.lua
local config = vim.fn.getcwd()
vim.opt.runtimepath:prepend(config)
vim.cmd.packadd("LuaSnip")
vim.o.swapfile = false
vim.o.hidden = true
require("config.cmds")

local ls = require("luasnip")
local project = require("config.actions.cpp_project")
local root = vim.fn.tempname()
local original_stdpath, original_notify = vim.fn.stdpath, vim.notify
local original_cwd = vim.fn.getcwd()
local directory, notices, source_config
local count, failures = 0, 0

local function eq(actual, expected)
	assert(
		vim.deep_equal(actual, expected),
		"expected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual)
	)
end

local function read(name)
	return vim.fn.readfile(directory .. "/" .. name)
end

local function test(name, run)
	count = count + 1
	if ls.get_active_snip() then
		ls.unlink_current()
	end
	vim.cmd("enew!")
	vim.fn.chdir(original_cwd)
	directory = root .. "/" .. count .. "/project"
	source_config = root .. "/" .. count .. "/config"
	vim.fn.mkdir(source_config .. "/snippets", "p")
	for _, ft in ipairs({ "yaml", "json", "cmake", "sh" }) do
		vim.fn.writefile(
			vim.fn.readfile(config .. "/snippets/" .. ft .. ".lua"),
			source_config .. "/snippets/" .. ft .. ".lua"
		)
	end
	notices = {}
	vim.fn.stdpath = function(kind)
		return kind == "config" and source_config or original_stdpath(kind)
	end
	vim.notify = function(message, level)
		notices[#notices + 1] = { message = message, level = level }
	end
	local ok, err = xpcall(run, debug.traceback)
	if ok then
		print("PASS " .. name)
	else
		failures = failures + 1
		io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
	end
end

local function expect_scaffold()
	local names = vim.fn.readdir(directory)
	table.sort(names)
	eq(names, {
		".clang-format",
		".clang-tidy",
		".clangd",
		".gitignore",
		"CMakeLists.txt",
		"CMakePresets.json",
		"check",
		"cmake",
	})
	eq(vim.fn.readdir(directory .. "/cmake"), { "config.cmake.in", "gtest.cmake", "install.cmake", "warnings.cmake" })
	eq(read(".gitignore"), { "/build/", ".cache/", "/CMakeUserPresets.json" })
	assert(vim.uv.fs_access(directory .. "/check", "X"), "check is executable")
	-- cm is expanded into the buffer and left for the user to save.
	eq(vim.uv.fs_stat(directory .. "/CMakeLists.txt").size, 0)
	eq(vim.api.nvim_buf_get_name(0), directory .. "/CMakeLists.txt")
	assert(vim.bo.modified, "expansion is left for the user to save")
	local listed = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	eq(vim.list_slice(listed, 1, 3), {
		"cmake_minimum_required(VERSION 3.25...4.4)",
		"project(",
		"  " .. vim.fs.basename(directory):gsub("[^%w_]", "_"),
	})
	assert(vim.tbl_contains(listed, "    include(cmake/gtest.cmake)"))
	local presets = vim.json.decode(table.concat(read("CMakePresets.json"), "\n"))
	eq(
		vim.tbl_map(function(preset)
			return preset.name
		end, presets.configurePresets),
		{ "base", "clang-debug", "dev", "tsan", "lint", "release", "release-clang" }
	)
	for ft, mappings in pairs({
		yaml = { clangd = ".clangd", fmt = ".clang-format", tidy = ".clang-tidy" },
		json = { cmpresets = "CMakePresets.json" },
		cmake = {
			cmwarn = "cmake/warnings.cmake",
			cmgt = "cmake/gtest.cmake",
			cminstall = "cmake/install.cmake",
			cmconfig = "cmake/config.cmake.in",
		},
		sh = { check = "check" },
	}) do
		for _, snippet in ipairs(dofile(source_config .. "/snippets/" .. ft .. ".lua")) do
			local target = mappings[snippet.trigger]
			if target then
				eq(read(target), snippet:get_static_text())
			end
		end
	end
end

test("explicit directory creates all files from real snippets", function()
	vim.cmd("Cpp " .. vim.fn.fnameescape(directory))
	expect_scaffold()
	eq(vim.fn.getcwd(), original_cwd)
	assert(notices[1].message:find("created 11", 1, true))
end)

test("no argument uses effective window-local cwd", function()
	vim.fn.mkdir(directory, "p")
	vim.cmd("lcd " .. vim.fn.fnameescape(directory))
	vim.cmd("Cpp")
	expect_scaffold()
end)

test("relative path with escaped spaces creates parents", function()
	vim.fn.chdir(root .. "/" .. count)
	directory = root .. "/" .. count .. "/nested/my project"
	vim.cmd("Cpp " .. vim.fn.fnameescape("nested/my project"))
	expect_scaffold()
end)

test("existing files survive repeated runs", function()
	assert(project.create(directory))
	vim.fn.writefile({ "# hand-written" }, directory .. "/.clang-tidy")
	vim.fn.writefile({ "project(custom)" }, directory .. "/CMakeLists.txt")
	vim.fn.writefile({ "# custom warnings" }, directory .. "/cmake/warnings.cmake")
	assert(project.create(directory))
	eq(read(".clang-tidy"), { "# hand-written" })
	eq(read("CMakeLists.txt"), { "project(custom)" })
	eq(read("cmake/warnings.cmake"), { "# custom warnings" })
	assert(notices[#notices].message:find("created 0", 1, true))
	assert(notices[#notices].message:find("skipped existing:", 1, true))
end)

test("latest saved snippets are reread in the same session", function()
	assert(project.create(directory))
	local first = directory
	local yaml = source_config .. "/snippets/yaml.lua"
	local json = source_config .. "/snippets/json.lua"
	vim.fn.writefile(vim.split(table.concat(vim.fn.readfile(yaml), "\n"):gsub("build/dev", "build/new"), "\n"), yaml)
	vim.fn.writefile(
		vim.split(table.concat(vim.fn.readfile(json), "\n"):gsub('"version": 6', '"version": 7'), "\n"),
		json
	)
	directory = directory .. "-next"
	assert(project.create(directory))
	eq(read(".clangd")[2], "  CompilationDatabase: build/new")
	eq(vim.json.decode(table.concat(read("CMakePresets.json"), "\n")).version, 7)
	eq(vim.fn.readfile(first .. "/.clangd")[2], "  CompilationDatabase: build/dev")
end)

test("missing snippet fails before filesystem changes", function()
	vim.fn.writefile({ "return {}" }, source_config .. "/snippets/yaml.lua")
	assert(not project.create(directory))
	eq(vim.uv.fs_stat(directory), nil)
	assert(notices[1].message:find("Missing snippet: clangd", 1, true))
end)

test("broken snippet file fails before filesystem changes", function()
	vim.fn.writefile({ "this is not lua" }, source_config .. "/snippets/json.lua")
	assert(not project.create(directory))
	eq(vim.uv.fs_stat(directory), nil)
	eq(notices[1].level, vim.log.levels.ERROR)
end)

test("interactive config snippet is rejected without writing defaults", function()
	vim.fn.writefile({
		'local ls = require("luasnip")',
		'return { ls.snippet("clangd", { ls.insert_node(1, "choose me") }) }',
	}, source_config .. "/snippets/yaml.lua")
	assert(not project.create(directory))
	eq(vim.uv.fs_stat(directory), nil)
	assert(notices[1].message:find("must be static", 1, true))
end)

test("existing directories and dangling symlinks are not overwritten", function()
	vim.fn.mkdir(directory .. "/.clangd", "p")
	assert(vim.uv.fs_symlink(directory .. "/missing", directory .. "/.clang-format"))
	assert(project.create(directory))
	eq(vim.uv.fs_lstat(directory .. "/.clang-format").type, "link")
	eq(vim.uv.fs_stat(directory .. "/.clangd").type, "directory")
	assert(notices[1].message:find("created 9", 1, true))
end)

test("unsaved destination buffer is preserved", function()
	vim.fn.mkdir(directory, "p")
	vim.cmd.edit(vim.fn.fnameescape(directory .. "/.clangd"))
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved config" })
	local buf = vim.api.nvim_get_current_buf()
	assert(project.create(directory))
	eq(vim.uv.fs_stat(directory .. "/.clangd"), nil)
	eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "unsaved config" })
	assert(vim.bo[buf].modified)
end)

test("existing cmake directory keeps unrelated files", function()
	vim.fn.mkdir(directory .. "/cmake", "p")
	vim.fn.writefile({ "# keep" }, directory .. "/cmake/custom.cmake")
	assert(project.create(directory))
	eq(read("cmake/custom.cmake"), { "# keep" })
	eq(vim.fn.filereadable(directory .. "/cmake/warnings.cmake"), 1)
end)

test("file blocking cmake directory fails before writing configs", function()
	vim.fn.mkdir(directory, "p")
	vim.fn.writefile({ "# not a directory" }, directory .. "/cmake")
	assert(not project.create(directory))
	eq(vim.fn.readdir(directory), { "cmake" })
	eq(read("cmake"), { "# not a directory" })
	eq(notices[1].level, vim.log.levels.ERROR)
end)

test("non-directory target reports an error", function()
	vim.fn.writefile({}, directory)
	assert(not project.create(directory))
	eq(vim.uv.fs_stat(directory).type, "file")
	eq(notices[1].level, vim.log.levels.ERROR)
end)

vim.fn.stdpath, vim.notify = original_stdpath, original_notify
vim.fn.chdir(original_cwd)
vim.cmd("%bwipeout!")
vim.fn.delete(root, "rf")
if failures > 0 then
	error(failures .. "/" .. count .. " tests failed")
end
print("All " .. count .. " C++ scaffold tests passed")
