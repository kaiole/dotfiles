-- Run from nvim/: nvim --headless -u NONE -l tests/sessionizer.lua
-- ROS panes: the nvim-normal flag must exist exactly in normal mode, since
-- ros-tmux opens the host sessionizer on Ctrl-F only while it exists. Drives a
-- child Neovim over RPC so mode changes go through a real event loop.
local module = vim.fn.getcwd() .. "/lua/config/sessionizer.lua"
local failures = 0

local function child(env)
	local channel = vim.fn.jobstart(
		{ vim.v.progpath, "--embed", "--headless", "-u", "NONE" },
		{ rpc = true, env = env }
	)
	assert(channel > 0, "could not start child Neovim")
	vim.rpcrequest(channel, "nvim_exec_lua", "dofile(...).setup()", { module })
	return channel
end

local function check(ok, label)
	if not ok then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

local state = vim.fn.tempname()
vim.fn.mkdir(state, "p")
local flag = state .. "/nvim-normal"
local ros = child({ ROS_TMUX_STATE = state })

local function expect(present, label)
	local ok = vim.wait(2000, function()
		return (vim.uv.fs_stat(flag) ~= nil) == present
	end, 10)
	check(ok, ("%s: flag should be %s"):format(label, present and "present" or "absent"))
end
local function input(keys)
	vim.rpcrequest(ros, "nvim_input", keys)
end
local function autocmd(event)
	vim.rpcrequest(ros, "nvim_exec_autocmds", event, {})
end

expect(true, "startup in normal mode")
input("i")
expect(false, "insert mode")
input("<Esc>")
expect(true, "back to normal")
input(":")
expect(false, "command line")
input("<Esc>")
expect(true, "normal after command line")
input("v")
expect(false, "visual mode")
input("<Esc>")
expect(true, "normal after visual")
-- Zsh's prompt hook deletes the flag while Neovim is suspended.
autocmd("VimSuspend")
expect(false, "suspended")
autocmd("VimResume")
expect(true, "resumed")
vim.fn.jobstop(ros)
expect(false, "exit")

-- Outside ROS panes nothing is reported.
local host = child({ ROS_TMUX_STATE = vim.NIL })
local tracked =
	vim.rpcrequest(host, "nvim_exec_lua", "return #vim.api.nvim_get_autocmds({ event = 'ModeChanged' })", {})
check(tracked == 0, "host: mode tracking installed without ROS_TMUX_STATE")
vim.fn.jobstop(host)

vim.fn.delete(state, "rf")
if failures > 0 then
	vim.cmd("cquit 1")
end
print("sessionizer tests passed")
