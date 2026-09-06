local M = {}

local function notify(message, level)
	vim.notify(message, level, { title = "C/C++ counterpart" })
end

local header_extensions = { h = true, hh = true, hpp = true, hxx = true }
local source_extensions = { c = true, cc = true, cpp = true, cxx = true, m = true, mm = true }

local function adjacent_counterpart(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		return nil
	end

	local extension = vim.fn.fnamemodify(path, ":e"):lower()
	local stem = vim.fn.fnamemodify(path, ":r")
	if header_extensions[extension] then
		return stem .. ".cpp"
	end
	if source_extensions[extension] then
		return stem .. ".hpp"
	end
end

local function create_counterpart(path, callback)
	local extension = vim.fn.fnamemodify(path, ":e"):lower()
	local lines
	if header_extensions[extension] then
		lines = { "#pragma once", "" }
	elseif source_extensions[extension] then
		local header = vim.fn.fnamemodify(path, ":t:r") .. ".hpp"
		lines = { '#include "' .. header .. '"', "" }
	else
		notify("Cannot create a counterpart for this file type", vim.log.levels.WARN)
		return
	end

	local prompt = vim.fn.fnamemodify(path, ":t") .. " does not exist. Create it?"
	if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
		return
	end

	if vim.uv.fs_stat(path) then
		callback(path)
		return
	end

	local fd, open_error = vim.uv.fs_open(path, "wx", 420)
	if not fd then
		if vim.uv.fs_stat(path) then
			callback(path)
			return
		end
		notify("Could not create " .. path .. ": " .. (open_error or "unknown error"), vim.log.levels.ERROR)
		return
	end

	local _, write_error = vim.uv.fs_write(fd, table.concat(lines, "\n"), -1)
	vim.uv.fs_close(fd)
	if write_error then
		vim.uv.fs_unlink(path)
		notify("Could not write " .. path .. ": " .. write_error, vim.log.levels.ERROR)
		return
	end
	callback(path)
end

local function fallback_counterpart(bufnr, callback)
	local path = adjacent_counterpart(bufnr)
	if not path then
		notify("Cannot determine the corresponding file", vim.log.levels.WARN)
		return
	end
	if vim.uv.fs_stat(path) then
		callback(path)
		return
	end
	create_counterpart(path, callback)
end

local function counterpart(callback)
	local bufnr = vim.api.nvim_get_current_buf()
	local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })

	if #clients == 0 then
		fallback_counterpart(bufnr, callback)
		return
	end

	clients[1]:request("textDocument/switchSourceHeader", {
		uri = vim.uri_from_bufnr(bufnr),
	}, function(err, uri)
		vim.schedule(function()
			if err then
				notify(err.message or "clangd request failed", vim.log.levels.WARN)
				fallback_counterpart(bufnr, callback)
				return
			end
			if not uri or uri == "" then
				fallback_counterpart(bufnr, callback)
				return
			end

			local path = vim.uri_to_fname(uri)
			if vim.uv.fs_stat(path) then
				callback(path)
			else
				fallback_counterpart(bufnr, callback)
			end
		end)
	end, bufnr)
end

local function visible_window(path, tab)
	local target = vim.fs.normalize(path)

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
		if name ~= "" and vim.fs.normalize(name) == target then
			return win
		end
	end
end

function M.switch()
	local win = vim.api.nvim_get_current_win()

	counterpart(function(path)
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_current_win(win)
			vim.cmd("edit " .. vim.fn.fnameescape(path))
		end
	end)
end

function M.split()
	local win = vim.api.nvim_get_current_win()
	local tab = vim.api.nvim_get_current_tabpage()

	counterpart(function(path)
		if not vim.api.nvim_tabpage_is_valid(tab) then
			return
		end

		local existing = visible_window(path, tab)
		if existing then
			vim.api.nvim_set_current_win(existing)
			return
		end
		if not vim.api.nvim_win_is_valid(win) then
			return
		end

		local extension = vim.fn.fnamemodify(path, ":e"):lower()
		local target_is_header = extension == "h" or extension == "hh" or extension == "hpp" or extension == "hxx"
		local other_windows = {}
		for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
			if candidate ~= win and vim.api.nvim_win_get_config(candidate).relative == "" then
				table.insert(other_windows, candidate)
			end
		end
		if #other_windows == 1 then
			vim.api.nvim_set_current_win(other_windows[1])
			vim.cmd("edit " .. vim.fn.fnameescape(path))
			vim.cmd("wincmd " .. (target_is_header and "H" or "L"))
			return
		end

		vim.api.nvim_set_current_win(win)
		local direction = target_is_header and "h" or "l"
		vim.cmd("wincmd " .. direction)

		local neighbor = vim.api.nvim_get_current_win()
		if neighbor ~= win and vim.api.nvim_win_get_config(neighbor).relative == "" then
			vim.cmd("edit " .. vim.fn.fnameescape(path))
			return
		end

		vim.api.nvim_set_current_win(win)
		local position = target_is_header and "leftabove" or "rightbelow"
		vim.cmd(position .. " vsplit " .. vim.fn.fnameescape(path))
	end)
end

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "c", "cpp", "objc", "objcpp" },
	callback = function(event)
		vim.keymap.set("n", "<leader>hd", M.switch, {
			buffer = event.buf,
			desc = "Switch header/source",
		})
		vim.keymap.set("n", "<leader>hs", M.split, {
			buffer = event.buf,
			desc = "Open header/source split",
		})
	end,
})

return M
