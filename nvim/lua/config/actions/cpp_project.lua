local M = {}

local files = {
	{ name = ".clangd", filetype = "yaml", trigger = "clangd" },
	{ name = ".clang-format", filetype = "yaml", trigger = "fmt" },
	{ name = ".clang-tidy", filetype = "yaml", trigger = "tidy" },
	{ name = "CMakePresets.json", filetype = "json", trigger = "cmpresets" },
	{ name = ".gitignore", lines = { "/build/", ".cache/" } },
	{ name = "CMakeLists.txt", lines = {} },
	{ name = "cmake/warnings.cmake", lines = {} },
}

local function render(file, sources)
	if file.lines then
		return file.lines
	end
	if not sources[file.filetype] then
		-- Execute the saved definitions afresh, rather than using LuaSnip's
		-- filetype/cache state (which may not have reloaded saved edits).
		local path = vim.fn.stdpath("config") .. "/snippets/" .. file.filetype .. ".lua"
		sources[file.filetype] = dofile(path)
	end
	local snippet
	for _, candidate in ipairs(sources[file.filetype]) do
		if candidate.trigger == file.trigger then
			assert(not snippet, "Duplicate snippet: " .. file.trigger)
			snippet = candidate
		end
	end
	assert(snippet, "Missing snippet: " .. file.trigger)
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

local function write_new(path, lines)
	-- Exclusive creation also prevents overwriting a file created after preflight.
	local fd, err, code = vim.uv.fs_open(path, "wx", 438)
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

local function create(directory_argument)
	local directory = directory_argument and directory_argument ~= "" and vim.fn.expand(directory_argument)
		or vim.fn.getcwd()
	directory = vim.fs.normalize(vim.fn.fnamemodify(directory, ":p"))
	local pending, skipped, sources = {}, {}, {}
	-- Resolve all needed snippets before creating the directory or any files.
	for _, file in ipairs(files) do
		local path = vim.fs.joinpath(directory, file.name)
		if exists(path) then
			skipped[#skipped + 1] = file.name
		else
			pending[#pending + 1] = { path = path, name = file.name, lines = render(file, sources) }
		end
	end
	vim.fn.mkdir(directory, "p")
	assert(vim.fn.isdirectory(directory) == 1, "Could not create directory: " .. directory)
	local created = {}
	for _, file in ipairs(pending) do
		vim.fn.mkdir(vim.fs.dirname(file.path), "p")
		if write_new(file.path, file.lines) then
			created[#created + 1] = file.name
		else
			skipped[#skipped + 1] = file.name
		end
	end
	local lists = vim.fs.joinpath(directory, "CMakeLists.txt")
	if vim.fn.isdirectory(lists) == 0 then
		vim.cmd.edit(vim.fn.fnameescape(lists))
	end
	local message = "Cpp: created " .. #created .. " file(s) in " .. directory
	if #skipped > 0 then
		message = message .. "; skipped existing: " .. table.concat(skipped, ", ")
	end
	vim.notify(message)
end

function M.create(directory_argument)
	local ok, err = pcall(create, directory_argument)
	if not ok then
		vim.notify("Cpp: " .. tostring(err), vim.log.levels.ERROR)
	end
	return ok
end

return M
