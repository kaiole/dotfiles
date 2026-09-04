local M = {}

local function notify(message, level)
	vim.notify(message, level, { title = "C/C++ counterpart" })
end

local function counterpart(callback)
	local bufnr = vim.api.nvim_get_current_buf()
	local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })

	if #clients == 0 then
		notify("clangd is not attached to this buffer", vim.log.levels.WARN)
		return
	end

	clients[1]:request("textDocument/switchSourceHeader", {
		uri = vim.uri_from_bufnr(bufnr),
	}, function(err, uri)
		if err then
			notify(err.message or "clangd request failed", vim.log.levels.ERROR)
			return
		end
		if not uri or uri == "" then
			notify("clangd found no corresponding file", vim.log.levels.INFO)
			return
		end

		vim.schedule(function()
			callback(vim.uri_to_fname(uri))
		end)
	end, bufnr)
end

local function visible_window(path)
	local target = vim.fs.normalize(path)

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
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

	counterpart(function(path)
		local existing = visible_window(path)
		if existing then
			vim.api.nvim_set_current_win(existing)
			return
		end
		if not vim.api.nvim_win_is_valid(win) then
			return
		end

		vim.api.nvim_set_current_win(win)
		local extension = vim.fn.fnamemodify(path, ":e"):lower()
		local target_is_header = extension == "h" or extension == "hh" or extension == "hpp" or extension == "hxx"
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
