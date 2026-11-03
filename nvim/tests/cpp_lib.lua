-- Run from nvim/: nvim --headless -u NONE -l tests/cpp_lib.lua
local config = vim.fn.getcwd()
vim.opt.runtimepath:prepend(config)
vim.cmd.packadd("LuaSnip")
vim.o.swapfile = false
vim.o.hidden = true
require("config.cmds")

local ls = require("luasnip")
local lib = require("config.actions.cpp_lib")
local root = vim.fn.tempname()
local original_stdpath, original_notify = vim.fn.stdpath, vim.notify
local original_cwd = vim.fn.getcwd()
local project, notices, source_config
local count, failures = 0, 0

local function eq(actual, expected)
	assert(
		vim.deep_equal(actual, expected),
		"expected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual)
	)
end

local function lines()
	return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function snippet(ft, trigger)
	for _, candidate in ipairs(dofile(source_config .. "/snippets/" .. ft .. ".lua")) do
		if candidate.trigger == trigger then
			return candidate
		end
	end
end

local function test(name, run)
	count = count + 1
	if ls.get_active_snip() then
		ls.unlink_current()
	end
	vim.cmd("enew!")
	project = root .. "/" .. count .. "/feed-handler"
	source_config = root .. "/" .. count .. "/config"
	vim.fn.mkdir(source_config .. "/snippets", "p")
	for _, ft in ipairs({ "yaml", "cmake" }) do
		vim.fn.writefile(
			vim.fn.readfile(config .. "/snippets/" .. ft .. ".lua"),
			source_config .. "/snippets/" .. ft .. ".lua"
		)
	end
	vim.fn.mkdir(project, "p")
	vim.fn.writefile({ "project(", "  feed_handler", "  LANGUAGES CXX)" }, project .. "/CMakeLists.txt")
	vim.fn.chdir(project)
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

local static_lib = {
	"add_library(decoding STATIC src/decoding.cpp)",
	"add_library(feed_handler::decoding ALIAS decoding)",
	"",
	"target_include_directories(decoding PUBLIC include)",
	"target_link_libraries(decoding PRIVATE feed_handler::warnings)",
	"",
	"if(BUILD_TESTING)",
	"  add_subdirectory(tests)",
	"endif()",
}

test("static library gets its layout and an expanded cmlib", function()
	vim.cmd("CppLib libs/decoding")
	local dir = project .. "/libs/decoding"
	eq(vim.api.nvim_buf_get_name(0), dir .. "/CMakeLists.txt")
	eq(lines(), static_lib)
	assert(vim.bo.modified, "expansion is left for the user to save")
	eq(vim.fn.isdirectory(dir .. "/include/feed_handler/decoding"), 1)
	eq(vim.fn.isdirectory(dir .. "/src"), 1)
	eq(vim.fn.readfile(dir .. "/tests/.clang-tidy"), snippet("yaml", "tidychill"):get_static_text())
	eq(vim.uv.fs_stat(dir .. "/tests/CMakeLists.txt").size, 0)
	eq(vim.fn.getreg('"'), "add_subdirectory(libs/decoding)\n")
	eq(vim.fn.getregtype('"'), "V")
	assert(notices[1].message:find("created 3", 1, true))
	assert(notices[1].message:find(project .. "/CMakeLists.txt", 1, true))
end)

test("bang makes a header-only library without src/", function()
	vim.cmd("CppLib! libs/decoding")
	eq(lines(), {
		"add_library(decoding INTERFACE)",
		"add_library(feed_handler::decoding ALIAS decoding)",
		"",
		"target_include_directories(decoding INTERFACE include)",
		"",
		"if(BUILD_TESTING)",
		"  add_subdirectory(tests)",
		"endif()",
	})
	eq(vim.fn.isdirectory(project .. "/libs/decoding/src"), 0)
end)

test("subdirectory line is relative to the nearest parent CMakeLists", function()
	vim.fn.mkdir(project .. "/libs", "p")
	vim.fn.writefile({ "add_subdirectory(itch)" }, project .. "/libs/CMakeLists.txt")
	vim.cmd("CppLib libs/decoding")
	eq(vim.fn.getreg('"'), "add_subdirectory(decoding)\n")
	assert(notices[1].message:find(project .. "/libs/CMakeLists.txt", 1, true))
	eq(lines()[2], "add_library(feed_handler::decoding ALIAS decoding)")
end)

test("namespace falls back to the cwd name before project() exists", function()
	vim.fn.writefile({}, project .. "/CMakeLists.txt")
	vim.cmd("CppLib decoding")
	eq(lines()[2], "add_library(feed_handler::decoding ALIAS decoding)")
	eq(vim.fn.isdirectory(project .. "/decoding/include/feed_handler/decoding"), 1)
end)

test("existing library files are kept and not expanded into", function()
	local dir = project .. "/libs/decoding"
	vim.fn.mkdir(dir, "p")
	vim.fn.writefile({ "# hand-written" }, dir .. "/CMakeLists.txt")
	assert(lib.create(dir))
	eq(lines(), { "# hand-written" })
	assert(not vim.bo.modified)
	assert(notices[1].message:find("created 2", 1, true))
	assert(notices[1].message:find("skipped existing: CMakeLists.txt", 1, true))
end)

test("missing snippet fails before filesystem changes", function()
	vim.fn.writefile({ "return {}" }, source_config .. "/snippets/cmake.lua")
	assert(not lib.create("libs/decoding"))
	eq(vim.uv.fs_stat(project .. "/libs"), nil)
	assert(notices[1].message:find("Missing snippet: cmlib", 1, true))
end)

test("missing directory argument reports usage", function()
	assert(not lib.create(""))
	eq(notices[1].level, vim.log.levels.ERROR)
	assert(notices[1].message:find("usage", 1, true))
end)

test("cmgtx defaults come from the tests directory", function()
	vim.cmd("CppLib libs/decoding")
	if ls.get_active_snip() then
		ls.unlink_current()
	end
	vim.cmd.edit(vim.fn.fnameescape(project .. "/libs/decoding/tests/CMakeLists.txt"))
	ls.snip_expand(snippet("cmake", "cmgtx"))
	eq(lines(), {
		"add_executable(decoding_tests decoding_test.cpp)",
		"target_link_libraries(",
		"  decoding_tests PRIVATE feed_handler::decoding feed_handler::warnings",
		"                         GTest::gtest_main)",
		"gtest_discover_tests(decoding_tests DISCOVERY_MODE PRE_TEST)",
	})
end)

vim.fn.stdpath, vim.notify = original_stdpath, original_notify
vim.fn.chdir(original_cwd)
vim.cmd("%bwipeout!")
vim.fn.delete(root, "rf")
if failures > 0 then
	error(failures .. "/" .. count .. " tests failed")
end
print("All " .. count .. " C++ library tests passed")
