local M = {}
local View = {}
View.__index = View
local next_id = 0

local function valid_buf(buf)
	return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function copy_lines(lines)
	local result = {}
	for _, line in ipairs(lines or {}) do
		if line:find("\n", 1, true) then
			for _, part in ipairs(vim.split(line, "\n", { plain = true })) do
				result[#result + 1] = part
			end
		else
			result[#result + 1] = line
		end
	end
	return #result > 0 and result or { "" }
end

local function single_line(text)
	return (tostring(text):gsub("%c", " "))
end

local function fit(text, width)
	text = single_line(text)
	if vim.fn.strdisplaywidth(text) <= width then
		return text
	end
	while vim.fn.strdisplaywidth(text) > width - 1 do
		text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
	end
	return text .. "…"
end

local function notify_small()
	vim.notify("Pi: not enough room to open this view", vim.log.levels.WARN)
end

local function window_options(win)
	for name, value in pairs({
		number = false,
		relativenumber = false,
		signcolumn = "no",
		foldcolumn = "0",
		colorcolumn = "",
		wrap = true,
		linebreak = true,
		spell = false,
	}) do
		vim.api.nvim_set_option_value(name, value, { win = win })
	end
end

-- A tracked window may have been repurposed with :edit or :buffer. Never
-- focus, modify, or close it once it no longer displays our buffer.
function View:_window(field, buffer_field)
	local win = self[field]
	if valid_win(win) and valid_buf(self[buffer_field]) and vim.api.nvim_win_get_buf(win) == self[buffer_field] then
		return true
	end
	self[field] = nil
	return false
end

function View:_check_composer()
	if self._closing_draft then
		return
	end
	local detached = false
	for field, buffer_field in pairs({ draft_win = "draft_buf", attachment_win = "attachment_buf" }) do
		if self[field] and not self:_window(field, buffer_field) then
			detached = true
		end
	end
	if detached then
		self:hide_draft()
	end
end

function View:_buffer(field, filetype, readonly)
	if valid_buf(self[field]) then
		return self[field]
	end
	local buf = vim.api.nvim_create_buf(false, true)
	self[field] = buf
	self._buffers[buf] = field
	for name, value in pairs({
		buftype = "nofile",
		bufhidden = "hide",
		swapfile = false,
		undofile = false,
		filetype = filetype,
		modifiable = not readonly,
		readonly = readonly,
	}) do
		vim.api.nvim_set_option_value(name, value, { buf = buf })
	end
	return buf
end

function View:_replace(buf, lines, readonly)
	if not vim.api.nvim_buf_is_loaded(buf) then
		vim.fn.bufload(buf)
	end
	vim.bo[buf].readonly = false
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, copy_lines(lines))
	vim.bo[buf].modified = false
	vim.bo[buf].modifiable = not readonly
	vim.bo[buf].readonly = readonly
end

function View:_map(buf, modes, key, callback, description)
	vim.keymap.set(modes, key, function()
		if not self._disposed then
			local ok, err = pcall(callback)
			if not ok then
				vim.notify("Pi: " .. tostring(err), vim.log.levels.ERROR)
			end
		end
	end, { buffer = buf, silent = true, desc = "Pi: " .. description })
end

function View:_save_cursor()
	if self:_window("draft_win", "draft_buf") then
		self._draft_cursor = vim.api.nvim_win_get_cursor(self.draft_win)
	end
end

function View:_restore_cursor()
	if self:_window("draft_win", "draft_buf") then
		local lines = self:get_text()
		local row = math.min(self._draft_cursor[1], #lines)
		local col = math.min(self._draft_cursor[2], #lines[row])
		-- Restoring/replacing text can put a saved byte column inside a new
		-- multibyte character. Snap backward before any cursor-based insertion.
		while col > 0 do
			local byte = lines[row]:byte(col + 1)
			if not byte or byte < 128 or byte >= 192 then
				break
			end
			col = col - 1
		end
		vim.api.nvim_win_set_cursor(self.draft_win, { row, col })
	end
end

function View:get_text()
	if valid_buf(self.draft_buf) and vim.api.nvim_buf_is_loaded(self.draft_buf) then
		self._draft_lines = vim.api.nvim_buf_get_lines(self.draft_buf, 0, -1, false)
	end
	return copy_lines(self._draft_lines)
end

function View:set_text(lines)
	if self._disposed then
		return
	end
	self._draft_lines = copy_lines(lines)
	if valid_buf(self.draft_buf) then
		self:_replace(self.draft_buf, self._draft_lines, false)
		self:_restore_cursor()
	end
end

function View:insert_reference(reference)
	if self._disposed or type(reference) ~= "string" or not reference:match("^@%d+$") then
		return
	end
	self:_check_composer()
	if self:_window("draft_win", "draft_buf") and vim.api.nvim_get_current_win() == self.draft_win then
		self:_save_cursor()
	end
	if not self:_window("draft_win", "draft_buf") then
		self:open_draft()
	end
	self:_check_composer()
	if not self:_window("draft_win", "draft_buf") then
		return
	end
	vim.api.nvim_set_current_win(self.draft_win)
	self:_check_composer()
	if not self:_window("draft_win", "draft_buf") or vim.api.nvim_get_current_win() ~= self.draft_win then
		return
	end
	self:_restore_cursor()
	local cursor = vim.api.nvim_win_get_cursor(self.draft_win)
	local row, col = cursor[1], cursor[2]
	local line = vim.api.nvim_buf_get_lines(self.draft_buf, row - 1, row, false)[1]
	-- Treat non-ASCII neighbors as words too, without splitting their UTF-8 bytes.
	local before = line:sub(col, col):match("[%w_@\128-\255]") and " " or ""
	local after = line:sub(col + 1, col + 1):match("[%w_@\128-\255]") and " " or ""
	vim.api.nvim_buf_set_text(self.draft_buf, row - 1, col, row - 1, col, { before .. reference .. after })
	self._draft_cursor = { row, col + #before + #reference - 1 }
	self:_restore_cursor()
end

function View:_draft_buffer()
	if valid_buf(self.draft_buf) and vim.api.nvim_buf_is_loaded(self.draft_buf) then
		return self.draft_buf
	end
	local buf = self:_buffer("draft_buf", "markdown", false)
	self:_replace(buf, self._draft_lines, false)
	self:_map(buf, { "n", "i" }, "<C-s>", function()
		self.owner:send()
	end, "send draft")
	for key, method in pairs({ ["<C-g>"] = "pick_model", ["<C-t>"] = "pick_thinking" }) do
		self:_map(buf, { "n", "i" }, key, function()
			self.owner.settings[method](self.owner.settings)
		end, method)
	end
	for key, method in pairs({ gP = "preview_prompt", gR = "restore_last", gC = "clear_draft" }) do
		self:_map(buf, "n", key, function()
			self.owner[method](self.owner)
		end, method)
	end
	for _, key in ipairs({ "q", "<Esc>" }) do
		self:_map(buf, "n", key, function()
			self:hide_draft()
		end, "hide composer")
	end
	self:_map(buf, "n", "<Tab>", function()
		self:_check_composer()
		if self:_window("attachment_win", "attachment_buf") then
			self:_save_cursor()
			vim.api.nvim_set_current_win(self.attachment_win)
		end
	end, "focus attachments")
	return buf
end

function View:_attachment_buffer()
	if valid_buf(self.attachment_buf) then
		return self.attachment_buf
	end
	local buf = self:_buffer("attachment_buf", "", true)
	for key, method in pairs({ ["<CR>"] = "preview_attachment", d = "remove_attachment", r = "refresh_attachment" }) do
		self:_map(buf, "n", key, function()
			local index = vim.api.nvim_win_get_cursor(0)[1]
			if (self.owner.attachments or {})[index] then
				self.owner[method](self.owner, index)
			end
		end, method)
	end
	self:_map(buf, "n", "i", function()
		local index = vim.api.nvim_win_get_cursor(0)[1]
		local attachment = (self.owner.attachments or {})[index]
		if attachment then
			self:insert_reference(require("config.pi.context").reference(attachment))
		end
	end, "insert attachment reference")
	self:_map(buf, "n", "<Tab>", function()
		self:_check_composer()
		if self:_window("draft_win", "draft_buf") then
			vim.api.nvim_set_current_win(self.draft_win)
		end
	end, "focus draft")
	for _, key in ipairs({ "q", "<Esc>" }) do
		self:_map(buf, "n", key, function()
			self:hide_draft()
		end, "hide composer")
	end
	return buf
end

function View:_geometry()
	local width = math.min(100, vim.o.columns - 4)
	local available = vim.o.lines - math.max(1, vim.o.cmdheight) - 2
	local count = #(self.owner.attachments or {})
	local attachment_height = math.min(math.max(1, count), 6, math.max(1, available - 7))
	local draft_height = math.min(math.max(4, math.floor(available * 0.5)), available - attachment_height - 4)
	if width < 24 or draft_height < 3 then
		return nil
	end
	local row = math.max(0, math.floor((available - draft_height - attachment_height - 4) / 2) + 1)
	local col = math.floor((vim.o.columns - width - 2) / 2)
	local model, thinking = self.owner.settings:labels()
	local prefix, suffix = " Pi · ", " · " .. thinking .. " · ephemeral "
	-- Long provider/model IDs must not push thinking and persistence out of view.
	local model_width = math.max(1, width - vim.fn.strdisplaywidth(prefix .. suffix))
	local draft = {
		relative = "editor",
		style = "minimal",
		border = "single",
		width = width,
		height = draft_height,
		row = row,
		col = col,
		title = fit(prefix .. fit(model, model_width) .. suffix, width),
		footer = fit((self.owner.status or "") .. " | C-s send / C-g model / C-t thinking", width),
		zindex = 50,
	}
	local attachments = {
		relative = "editor",
		style = "minimal",
		border = "single",
		width = width,
		height = attachment_height,
		row = row + draft_height + 2,
		col = col,
		footer = fit(" Attachments (" .. count .. ") · i reference / Enter preview / d remove / r refresh ", width),
		zindex = 50,
	}
	return draft, attachments
end

function View:refresh_attachments()
	if self._disposed then
		return
	end
	self:_check_composer()
	local lines = {}
	local context = require("config.pi.context")
	for index, attachment in ipairs(self.owner.attachments or {}) do
		local suffix = ""
		local ok, freshness = pcall(context.freshness, attachment)
		if ok and freshness and freshness ~= "unchanged" then
			suffix = " [" .. freshness .. "]"
		end
		lines[index] = single_line(context.label(attachment) .. suffix)
	end
	if #lines == 0 then
		lines = { "(no attachments)" }
	end
	self:_replace(self:_attachment_buffer(), lines, true)
	if valid_win(self.draft_win) or valid_win(self.attachment_win) then
		local draft, attachments = self:_geometry()
		if not draft then
			self:hide_draft()
			notify_small()
			return
		end
		if valid_win(self.draft_win) then
			vim.api.nvim_win_set_config(self.draft_win, draft)
		end
		if valid_win(self.attachment_win) then
			vim.api.nvim_win_set_config(self.attachment_win, attachments)
		end
	end
end

function View:open_draft()
	if self._disposed then
		return
	end
	self:_check_composer()
	if type(self.owner.workspace_for_source) == "function" then
		local ok, err = pcall(self.owner.workspace_for_source, self.owner)
		if not ok then
			vim.notify("Pi: " .. tostring(err), vim.log.levels.WARN)
			return
		end
	end
	local draft, attachments = self:_geometry()
	if not draft then
		notify_small()
		return
	end
	self:refresh_attachments()
	local ok, err = pcall(function()
		if not valid_win(self.draft_win) then
			self.draft_win = vim.api.nvim_open_win(self:_draft_buffer(), true, draft)
			window_options(self.draft_win)
			self:_restore_cursor()
		else
			vim.api.nvim_set_current_win(self.draft_win)
		end
		if not valid_win(self.attachment_win) then
			self.attachment_win = vim.api.nvim_open_win(self.attachment_buf, false, attachments)
			window_options(self.attachment_win)
		end
	end)
	if not ok then
		self:hide_draft()
		vim.notify("Pi: " .. tostring(err), vim.log.levels.WARN)
	end
end

function View:hide_draft()
	if self._closing_draft then
		return
	end
	self._closing_draft = true
	self:_save_cursor()
	self:get_text()
	for _, field in ipairs({ "attachment_win", "draft_win" }) do
		self:_window(field, field == "draft_win" and "draft_buf" or "attachment_buf")
		local win = self[field]
		self[field] = nil
		if valid_win(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end
	self._closing_draft = false
end

function View:_close_preview()
	self:_window("preview_win", "preview_buf")
	local win, buf = self.preview_win, self.preview_buf
	self.preview_win = nil
	self.preview_buf = nil
	if valid_win(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
	if valid_buf(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end

function View:_preview_geometry()
	local width = math.min(100, vim.o.columns - 4)
	local height = math.min(#self._preview_lines, vim.o.lines - math.max(1, vim.o.cmdheight) - 4)
	if width < 12 or height < 1 then
		return nil
	end
	return {
		relative = "editor",
		style = "minimal",
		border = "single",
		width = width,
		height = height,
		row = math.max(0, math.floor((vim.o.lines - height - 3) / 2)),
		col = math.floor((vim.o.columns - width - 2) / 2),
		title = fit(" " .. self._preview_title .. " ", width),
		zindex = 60,
	}
end

function View:show_preview(title, text)
	if self._disposed then
		return
	end
	self._preview_title = title
	self._preview_lines = copy_lines(vim.split(text, "\n", { plain = true }))
	local geometry = self:_preview_geometry()
	if not geometry then
		notify_small()
		return
	end
	self:_close_preview()
	local buf = self:_buffer("preview_buf", "markdown", true)
	self:_replace(buf, self._preview_lines, true)
	self:_map(buf, "n", "q", function()
		self:_close_preview()
	end, "close preview")
	local ok, win = pcall(vim.api.nvim_open_win, buf, true, geometry)
	if not ok then
		self:_close_preview()
		vim.notify("Pi: " .. tostring(win), vim.log.levels.WARN)
		return
	end
	self.preview_win = win
	window_options(win)
end

function View:_save_chat_view()
	if self:_window("chat_win", "chat_buf") then
		vim.api.nvim_win_call(self.chat_win, function()
			self._chat_view = vim.fn.winsaveview()
			self._chat_follow = vim.fn.line("w$") >= vim.api.nvim_buf_line_count(self.chat_buf)
		end)
	end
end

function View:_restore_chat_view()
	if not self:_window("chat_win", "chat_buf") then
		return
	end
	vim.api.nvim_win_call(self.chat_win, function()
		if self._chat_follow then
			vim.api.nvim_win_set_cursor(self.chat_win, { vim.api.nvim_buf_line_count(self.chat_buf), 0 })
			vim.cmd("normal! zb")
		elseif self._chat_view then
			vim.fn.winrestview(self._chat_view)
		end
	end)
end

function View:_hide_chat()
	self:_save_chat_view()
	local win = self.chat_win
	self.chat_win = nil
	if valid_win(win) then
		local closed = pcall(vim.api.nvim_win_close, win, true)
		if not closed and valid_win(win) then
			-- Neovim cannot close its last ordinary window. Return it to a
			-- non-chat buffer instead, without discarding the conversation.
			local buf = self._chat_return_buf
			if not valid_buf(buf) or self:is_internal(buf) then
				buf = vim.api.nvim_create_buf(true, false)
			end
			vim.api.nvim_win_set_buf(win, buf)
		end
	end
end

function View:open_chat()
	if self._disposed then
		return
	end
	if self:_window("chat_win", "chat_buf") then
		vim.api.nvim_set_current_win(self.chat_win)
		return
	end
	if vim.o.columns < 30 or vim.o.lines < 6 then
		notify_small()
		return
	end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local candidate = vim.api.nvim_win_get_buf(win)
		if vim.api.nvim_win_get_config(win).relative == "" and not self:is_internal(candidate) then
			self._chat_return_buf = candidate
			break
		end
	end
	local buf = self:_buffer("chat_buf", "markdown", true)
	self:_replace(buf, self._chat_lines, true)
	self:_map(buf, "n", "q", function()
		self:_hide_chat()
	end, "hide chat")
	local ok, win = pcall(vim.api.nvim_open_win, buf, true, { split = "right", win = -1 })
	if not ok then
		vim.notify("Pi: " .. tostring(win), vim.log.levels.WARN)
		return
	end
	self.chat_win = win
	window_options(win)
	self:_restore_chat_view()
end

function View:write_chat(lines)
	if self._disposed then
		return
	end
	self:_save_chat_view()
	self._chat_lines = copy_lines(lines)
	local buf = self:_buffer("chat_buf", "markdown", true)
	self:_replace(buf, self._chat_lines, true)
	self:_restore_chat_view()
end

function View:is_internal(bufnr)
	return not self._disposed and self._buffers[bufnr] ~= nil
end

function View:dispose()
	if self._disposed then
		return
	end
	self._disposed = true
	vim.api.nvim_del_augroup_by_id(self._group)
	self:hide_draft()
	self:_hide_chat()
	self:_close_preview()
	for buf in pairs(self._buffers) do
		if valid_buf(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
	self._buffers = {}
	self.draft_buf, self.attachment_buf, self.chat_buf = nil, nil, nil
end

function M.new(owner)
	next_id = next_id + 1
	local self = setmetatable({
		owner = owner,
		_buffers = {},
		_draft_lines = { "" },
		_draft_cursor = { 1, 0 },
		_chat_lines = { "" },
		_chat_follow = true,
		_group = vim.api.nvim_create_augroup("PiView" .. next_id, { clear = true }),
	}, View)
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinLeave", "BufWinLeave" }, {
		group = self._group,
		callback = function(event)
			if event.buf == self.draft_buf then
				self:_save_cursor()
			elseif event.buf == self.chat_buf then
				self:_save_chat_view()
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
		group = self._group,
		callback = function(event)
			local field = self._buffers[event.buf]
			if not field then
				return
			end
			if field == "draft_buf" then
				self:get_text()
				self:_save_cursor()
			end
			if event.event == "BufWipeout" then
				self._buffers[event.buf] = nil
				if self[field] ~= event.buf then
					return
				end
				self[field] = nil
				if field == "draft_buf" or field == "attachment_buf" then
					self:hide_draft()
				elseif field == "preview_buf" then
					self:_close_preview()
				elseif field == "chat_buf" then
					self:_hide_chat()
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = self._group,
		callback = function(event)
			local win = tonumber(event.match)
			if win == self.draft_win or win == self.attachment_win then
				self:hide_draft()
			elseif win == self.chat_win then
				self.chat_win = nil
			elseif win == self.preview_win then
				self.preview_win = nil
				-- Buffer deletion is unsafe inside some window teardown paths.
				local buf = self.preview_buf
				self.preview_buf = nil
				vim.schedule(function()
					if valid_buf(buf) then
						pcall(vim.api.nvim_buf_delete, buf, { force = true })
					end
				end)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = self._group,
		callback = function()
			self:_check_composer()
			self:_window("chat_win", "chat_buf")
			self:_window("preview_win", "preview_buf")
		end,
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = self._group,
		callback = function()
			self:refresh_attachments()
			if self:_window("preview_win", "preview_buf") then
				local geometry = self:_preview_geometry()
				if geometry then
					vim.api.nvim_win_set_config(self.preview_win, geometry)
				else
					self:_close_preview()
					notify_small()
				end
			end
		end,
	})
	return self
end

return M
