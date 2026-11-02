-- Run from nvim/: nvim --headless -u NONE -l tests/cpp.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.swapfile = false
vim.o.hidden = true

local cpp = require("config.cpp")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local original_input, original_confirm = vim.ui.input, vim.fn.confirm
local original_clients, original_notify = vim.lsp.get_clients, vim.notify
local directory, prompts, notices, answer, confirmation
local failures, count = 0, 0

local function eq(actual, expected)
	assert(
		vim.deep_equal(actual, expected),
		"expected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual)
	)
end

local function current_path()
	return vim.api.nvim_buf_get_name(0)
end

local function start(path)
	local full_path = directory .. "/" .. path
	vim.fn.mkdir(vim.fs.dirname(full_path), "p")
	vim.fn.writefile({}, full_path)
	vim.cmd.edit(vim.fn.fnameescape(full_path))
	return full_path
end

local function test(name, run)
	count = count + 1
	vim.cmd("only!")
	vim.cmd("enew!")
	directory = root .. "/" .. count
	vim.fn.mkdir(directory, "p")
	prompts, notices, answer, confirmation = {}, {}, nil, 1
	vim.lsp.get_clients = function()
		return {}
	end
	vim.ui.input = function(options, callback)
		prompts[#prompts + 1] = options
		callback(answer)
	end
	vim.fn.confirm = function()
		return confirmation
	end
	vim.notify = function(message)
		notices[#notices + 1] = message
	end
	local cwd = vim.fn.getcwd()
	local ok, err = xpcall(run, debug.traceback)
	vim.fn.chdir(cwd)
	if ok then
		print("PASS " .. name)
	else
		failures = failures + 1
		io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
	end
end

test("existing adjacent counterpart needs no prompt", function()
	start("widget.hpp")
	local source = directory .. "/widget.cpp"
	vim.fn.writefile({ "// existing" }, source)
	cpp.switch()
	eq(current_path(), source)
	eq(#prompts, 0)
	eq(vim.fn.readfile(source), { "// existing" })
end)

test("custom source destination creates parents and leaves include to user", function()
	start("include/mylib/widget.hh")
	answer = directory .. "/src with spaces/widget.cc"
	cpp.switch()
	eq(prompts[1].default, nil)
	eq(prompts[1].completion, "file")
	eq(current_path(), answer)
	eq(vim.uv.fs_stat(answer).size, 0)
	eq(vim.uv.fs_stat(directory .. "/include/mylib/widget.cpp"), nil)
end)

test("entering adjacent path creates empty source", function()
	start("widget.hpp")
	answer = directory .. "/widget.cpp"
	cpp.switch()
	eq(current_path(), answer)
	eq(vim.uv.fs_stat(answer).size, 0)
end)

test("split creates header at chosen destination with pragma once", function()
	local source = start("src/widget.cpp")
	answer = directory .. "/include/mylib/widget.h"
	cpp.split()
	eq(current_path(), answer)
	eq(vim.fn.readfile(answer), { "#pragma once" })
	local paths = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		paths[#paths + 1] = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
	end
	table.sort(paths)
	local expected = { source, answer }
	table.sort(expected)
	eq(paths, expected)
end)

test("cancel or empty destination creates nothing", function()
	local header = start("widget.hpp")
	cpp.switch()
	eq(current_path(), header)
	answer = ""
	cpp.switch()
	eq(current_path(), header)
	eq(vim.uv.fs_stat(directory .. "/widget.cpp"), nil)
end)

test("declining parent creation leaves filesystem and window alone", function()
	local header = start("widget.hpp")
	answer = directory .. "/src/nested/widget.cpp"
	confirmation = 2
	cpp.switch()
	eq(current_path(), header)
	eq(vim.uv.fs_stat(directory .. "/src"), nil)
end)

test("chosen existing file opens without overwriting", function()
	start("widget.hpp")
	answer = directory .. "/other.cpp"
	vim.fn.writefile({ "// keep me" }, answer)
	cpp.switch()
	eq(current_path(), answer)
	eq(vim.fn.readfile(answer), { "// keep me" })
end)

test("directory destination is rejected", function()
	local header = start("widget.hpp")
	answer = directory
	cpp.switch()
	eq(current_path(), header)
	assert(notices[1]:find("Not a file:", 1, true))
end)

test("unsupported extension is rejected before making parents", function()
	local header = start("widget.hpp")
	answer = directory .. "/missing/widget.txt"
	cpp.switch()
	eq(current_path(), header)
	eq(vim.uv.fs_stat(directory .. "/missing"), nil)
	eq(#notices, 1)
end)

test("relative destination is relative to editor cwd", function()
	start("widget.hpp")
	vim.fn.chdir(directory)
	answer = "widget.cxx"
	cpp.switch()
	eq(current_path(), directory .. "/widget.cxx")
end)

test("clangd counterpart still takes precedence over creation", function()
	start("include/widget.hpp")
	local source = directory .. "/widget.cpp"
	vim.fn.writefile({}, source)
	vim.lsp.get_clients = function()
		return {
			{
				request = function(_, method, _, callback)
					eq(method, "textDocument/switchSourceHeader")
					callback(nil, vim.uri_from_fname(source))
					return true, 1
				end,
			},
		}
	end
	cpp.switch()
	assert(vim.wait(1000, function()
		return current_path() == source
	end))
	eq(#prompts, 0)
end)

vim.ui.input, vim.fn.confirm = original_input, original_confirm
vim.lsp.get_clients, vim.notify = original_clients, original_notify
vim.cmd("only!")
vim.cmd("enew!")
vim.fn.delete(root, "rf")
print(string.format("%d/%d counterpart tests passed", count - failures, count))
if failures > 0 then
	vim.cmd("cquit 1")
end
