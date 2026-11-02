-- <C-f> opens tmux-sessionizer. In a ROS distrobox pane the script lives on the
-- host, out of reach, so host tmux intercepts <C-f> (`ros-tmux picker`) and this
-- module tells it when Neovim is in normal mode, where <C-f> means sessionizer.
-- See ~/dotfiles/scripts/tmux-sessionizer/ROS.md.
local M = {}

local sessionizer = vim.fn.expand("~/.local/bin/tmux-sessionizer")

local function open()
	if vim.fn.executable(sessionizer) == 0 then
		vim.notify("tmux-sessionizer is not installed here; use <prefix> <C-f>", vim.log.levels.WARN)
		return
	end
	vim.fn.jobstart({ sessionizer }, { detach = true })
end

-- Keep `<state_dir>/nvim-normal` present exactly while in normal mode, so other
-- modes (insert, command line, visual, terminal) still receive <C-f>.
function M.report_mode(state_dir)
	local flag = state_dir .. "/nvim-normal"
	local marked = false
	local function mark(normal)
		if normal == marked then
			return
		end
		marked = normal
		if normal then
			local file = io.open(flag, "w")
			if file then
				file:close()
			end
		else
			os.remove(flag)
		end
	end
	local function sync()
		local mode = vim.api.nvim_get_mode().mode
		mark(mode == "n" or mode == "nt")
	end

	local group = vim.api.nvim_create_augroup("RosTmuxMode", { clear = true })
	-- The shell prompt clears the flag while suspended; VimResume restores it.
	vim.api.nvim_create_autocmd({ "ModeChanged", "VimResume" }, { group = group, callback = sync })
	vim.api.nvim_create_autocmd({ "VimSuspend", "VimLeavePre" }, {
		group = group,
		callback = function()
			mark(false)
		end,
	})
	sync()
end

function M.setup()
	vim.keymap.set("n", "<C-f>", open, { silent = true, desc = "Open tmux-sessionizer" })
	local state = vim.env.ROS_TMUX_STATE
	if state and vim.fn.isdirectory(state) == 1 then
		M.report_mode(state)
	end
end

return M
