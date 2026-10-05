-- Attachment capture/serialization. Nothing here starts Pi or changes editor text.
local pi = require("pi")
local api = vim.api
local M = {}

function M.path(path, workspace)
	path = vim.fs.normalize(path)
	local prefix = workspace:gsub("/$", "") .. "/"
	return path:sub(1, #prefix) == prefix and path:sub(#prefix + 1) or path
end

local function stat(path)
	local value = vim.uv.fs_stat(path)
	return value and { size = value.size, mtime = value.mtime, type = value.type } or false
end

function M.file(path, workspace)
	path = vim.fn.expand(path)
	if path:sub(1, 1) ~= "/" then
		path = workspace .. "/" .. path
	end
	path = vim.fs.normalize(path)
	assert(vim.fn.filereadable(path) == 1, "Not a readable file: " .. path)
	local name = M.path(path, workspace)
	return {
		kind = "file",
		path = path,
		spec = { kind = "file", path = path },
		baseline = stat(path),
		label = "File         " .. name,
		text = string.format("File reference (disk, not unsaved editor text): %q\nAbsolute path: %q", name, path),
	}
end

local function captured(snapshot, kind, spec, workspace)
	local name = snapshot.source.name
	name = name ~= "" and M.path(name, workspace) or "[unnamed buffer]"
	local detail = ""
	if snapshot.range then
		local range = snapshot.range
		local last = range["end"].row + (range["end"].col > 0 and 1 or 0)
		detail = string.format(":%d–%d · %d lines", range.start.row + 1, last, #snapshot.lines)
	elseif snapshot.diagnostics then
		detail = " · " .. #snapshot.diagnostics .. " diagnostics"
	elseif snapshot.lines then
		detail = " · " .. #snapshot.lines .. " lines (unsaved snapshot)"
	end
	return {
		kind = kind,
		spec = spec,
		capture = snapshot,
		label = string.format("%-12s %s%s", kind, name, detail),
		text = pi.format.context(snapshot),
	}
end

function M.buffer(bufnr, workspace)
	return captured(pi.context.buffer(bufnr), "Buffer", { kind = "buffer", bufnr = bufnr }, workspace)
end

function M.selection(workspace)
	local snapshot = pi.context.selection()
	return captured(snapshot, "Selection", {
		kind = "range",
		bufnr = snapshot.source.bufnr,
		range = vim.deepcopy(snapshot.range),
	}, workspace)
end

function M.range(bufnr, range, workspace)
	return captured(pi.context.range(bufnr, range), "Selection", {
		kind = "range",
		bufnr = bufnr,
		range = vim.deepcopy(range),
	}, workspace)
end

function M.diagnostics(bufnr, workspace, selected)
	local snapshot = pi.context.diagnostics(bufnr)
	if selected then
		snapshot.diagnostics = { vim.deepcopy(selected) }
	end
	assert(#snapshot.diagnostics > 0, "No diagnostics to attach")
	return captured(snapshot, selected and "Diagnostic" or "Diagnostics", {
		kind = "diagnostics",
		bufnr = bufnr,
		-- A refreshed single diagnostic is selected at this original position.
		position = selected and { selected.lnum, selected.col } or nil,
	}, workspace)
end

function M.at_cursor(bufnr, row, col)
	local found = {}
	for _, d in ipairs(vim.diagnostic.get(bufnr)) do
		local end_row, end_col = d.end_lnum or d.lnum, d.end_col or d.col
		local starts = row > d.lnum or (row == d.lnum and col >= d.col)
		local ends = row < end_row or (row == end_row and col < end_col)
		local empty = row == d.lnum and end_row == d.lnum and end_col == d.col and col == d.col
		if starts and (ends or empty) then
			found[#found + 1] = d
		end
	end
	return found
end

function M.quickfix(workspace, id)
	local list = vim.fn.getqflist({ id = id or 0, title = 0, items = 0, changedtick = 0 })
	assert(list.id and list.id > 0 and #list.items > 0, "Quickfix list is empty or unavailable")
	local text = {
		string.format(
			"Quickfix snapshot: %q (%d entries). Positions are one-based; zero means unspecified.",
			list.title,
			#list.items
		),
	}
	local sources = {}
	for i, item in ipairs(list.items) do
		local path = item.bufnr > 0 and api.nvim_buf_is_valid(item.bufnr) and api.nvim_buf_get_name(item.bufnr) or ""
		if item.bufnr > 0 and api.nvim_buf_is_loaded(item.bufnr) then
			sources[item.bufnr] = api.nvim_buf_get_changedtick(item.bufnr)
		end
		text[#text + 1] = string.format(
			"%d. file=%q location=%d:%d–%d:%d column=%s type=%q valid=%s pattern=%q module=%q nr=%s\n%s",
			i,
			path ~= "" and M.path(path, workspace) or "[no file]",
			item.lnum,
			item.col,
			item.end_lnum or 0,
			item.end_col or 0,
			item.vcol == 1 and "display" or "byte",
			item.type,
			tostring(item.valid),
			item.pattern or "",
			item.module or "",
			tostring(item.nr),
			item.text
		)
	end
	return {
		kind = "Quickfix",
		spec = { kind = "quickfix", id = list.id },
		list = vim.deepcopy(list),
		sources = sources,
		label = string.format("Quickfix     %s · %d entries", list.title, #list.items),
		text = table.concat(text, "\n"),
	}
end

function M.freshness(item)
	if item.kind == "file" then
		return vim.deep_equal(stat(item.path), item.baseline) and "unchanged" or "changed"
	elseif item.capture then
		local status = pi.context.check(item.capture).status
		if status ~= "unchanged" then
			return status
		end
		if item.capture.diagnostics then
			local current = vim.diagnostic.get(item.spec.bufnr)
			if item.spec.position then
				current = M.at_cursor(item.spec.bufnr, unpack(item.spec.position))
				for _, d in ipairs(current) do
					if vim.deep_equal(d, item.capture.diagnostics[1]) then
						return "unchanged"
					end
				end
				return "changed"
			end
			return vim.deep_equal(current, item.capture.diagnostics) and "unchanged" or "changed"
		end
		return status
	end
	local list = vim.fn.getqflist({ id = item.list.id, changedtick = 0 })
	if list.id ~= item.list.id or list.changedtick ~= item.list.changedtick then
		return "changed"
	end
	for bufnr, tick in pairs(item.sources) do
		if not api.nvim_buf_is_loaded(bufnr) or api.nvim_buf_get_changedtick(bufnr) ~= tick then
			return "changed"
		end
	end
	return "unchanged"
end

function M.refresh(item, workspace)
	local spec = item.spec
	if item.capture then
		local status = pi.context.check(item.capture).status
		assert(
			status ~= "identity-changed" and status ~= "unavailable",
			"Source identity changed or unavailable; attach again"
		)
	end
	if spec.kind == "file" then
		return M.file(spec.path, workspace)
	elseif spec.kind == "buffer" then
		return M.buffer(spec.bufnr, workspace)
	elseif spec.kind == "range" then
		return M.range(spec.bufnr, spec.range, workspace)
	elseif spec.kind == "quickfix" then
		return M.quickfix(workspace, spec.id)
	else
		local selected
		if spec.position then
			local found = M.at_cursor(spec.bufnr, unpack(spec.position))
			assert(#found == 1, "Diagnostic moved, disappeared, or overlaps; attach it again")
			selected = found[1]
		end
		return M.diagnostics(spec.bufnr, workspace, selected)
	end
end

function M.prompt(question, attachments, workspace)
	local parts = {
		"Workspace: " .. string.format("%q", workspace),
		"User question:\n" .. question,
	}
	for i, item in ipairs(attachments) do
		parts[#parts + 1] = string.format("Attachment %d:\n%s", i, item.text)
	end
	return table.concat(parts, "\n\n")
end

return M
