-- Shared by :Cpp, :CppSolo, :CppLib and :Whitebox: create missing files, from
-- saved snippets or literal lines, without overwriting anything.
local M = {}

-- Loads the snippet with this trigger from the saved snippets/<filetype>.lua.
-- `sources` caches each file for one command.
function M.load(filetype, trigger, sources)
	sources = sources or {}
	if not sources[filetype] then
		-- Execute the saved definitions afresh, rather than using LuaSnip's
		-- filetype/cache state (which may not have reloaded saved edits).
		local path = vim.fn.stdpath("config") .. "/snippets/" .. filetype .. ".lua"
		sources[filetype] = dofile(path)
	end
	local snippet
	for _, candidate in ipairs(sources[filetype]) do
		if candidate.trigger == trigger then
			assert(not snippet, "Duplicate snippet: " .. trigger)
			snippet = candidate
		end
	end
	return assert(snippet, "Missing snippet: " .. trigger)
end

local function render(file, sources)
	if file.lines then
		return file.lines
	end
	local snippet = M.load(file.filetype, file.trigger, sources)
	local types = require("luasnip.util.types")
	for _, node in ipairs(snippet.nodes) do
		assert(
			node.type == types.textNode or node.type == types.exitNode,
			"Snippet '" .. file.trigger .. "' must be static; expand interactive snippets manually"
		)
	end
	return snippet:get_static_text()
end

local function exists(path)
	-- lstat also protects dangling symlinks, not just readable regular files.
	local stat, err, code = vim.uv.fs_lstat(path)
	assert(stat or code == "ENOENT", err)
	if stat then
		return true
	end
	local buf = vim.fn.bufnr(path)
	return buf ~= -1 and vim.bo[buf].modified
end

local function write_new(path, lines, mode)
	-- Exclusive creation also prevents overwriting a file created after preflight.
	local fd, err, code = vim.uv.fs_open(path, "wx", mode or 438)
	if code == "EEXIST" then
		return false
	end
	assert(fd, err)
	local content = #lines > 0 and table.concat(lines, "\n") .. "\n" or ""
	local offset = 0
	while offset < #content do
		local written, write_err = vim.uv.fs_write(fd, content:sub(offset + 1), offset)
		if not written or written == 0 then
			vim.uv.fs_close(fd)
			vim.uv.fs_unlink(path)
			error(write_err or ("Could not write " .. path), 0)
		end
		offset = offset + written
	end
	local closed, close_err = vim.uv.fs_close(fd)
	assert(closed, close_err)
	return true
end

-- Absolute, normalized form of a command's directory argument (default: cwd).
function M.directory(argument)
	local directory = argument and argument ~= "" and vim.fn.expand(argument) or vim.fn.getcwd()
	return vim.fs.normalize(vim.fn.fnamemodify(directory, ":p"))
end

-- Creates each missing file in `files` under `directory`. A file is
-- { name, lines } or { name, filetype, trigger } naming a static snippet, plus
-- an optional permission `mode`. Returns the created and skipped names.
function M.write(directory, files, sources)
	sources = sources or {}
	local pending, skipped = {}, {}
	-- Resolve all needed snippets before creating the directory or any files.
	for _, file in ipairs(files) do
		local path = vim.fs.joinpath(directory, file.name)
		if exists(path) then
			skipped[#skipped + 1] = file.name
		else
			pending[#pending + 1] = { path = path, name = file.name, lines = render(file, sources), mode = file.mode }
		end
	end
	vim.fn.mkdir(directory, "p")
	assert(vim.fn.isdirectory(directory) == 1, "Could not create directory: " .. directory)
	local created = {}
	for _, file in ipairs(pending) do
		vim.fn.mkdir(vim.fs.dirname(file.path), "p")
		if write_new(file.path, file.lines, file.mode) then
			created[#created + 1] = file.name
		else
			skipped[#skipped + 1] = file.name
		end
	end
	return created, skipped
end

function M.summary(command, directory, created, skipped)
	local message = command .. ": created " .. #created .. " file(s) in " .. directory
	if #skipped > 0 then
		message = message .. "; skipped existing: " .. table.concat(skipped, ", ")
	end
	return message
end

-- Opens `path` for the follow-up expansion. Re-editing it while it is the
-- current buffer would reload it, failing if a previous run's expansion is
-- unsaved, so that buffer is kept as is.
function M.open(path)
	if vim.fn.isdirectory(path) == 0 and vim.fn.bufnr(path) ~= vim.api.nvim_get_current_buf() then
		vim.cmd.edit(vim.fn.fnameescape(path))
	end
end

-- Runs `create` and reports errors as notifications. Returns success.
function M.run(command, create, ...)
	local ok, err = pcall(create, ...)
	if not ok then
		vim.notify(command .. ": " .. tostring(err), vim.log.levels.ERROR)
	end
	return ok
end

return M
