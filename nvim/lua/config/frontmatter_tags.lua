-- Blink source: tags already used in the vault, offered inside a note's
-- frontmatter `tags:` (`tags: [a, b]`, `tags: a` or a `- a` list).
-- markdown-oxide only completes `#tag`, and `#` starts a YAML comment.

local M = {}

function M.new()
	return setmetatable({}, { __index = M })
end

function M:enabled()
	return vim.bo.filetype == "markdown" and vim.fs.root(0, ".obsidian") ~= nil
end

function M:get_trigger_characters()
	return { "[", ",", " ", "-" }
end

---@param lines string[]
---@return string[]
local function parse_tags(lines)
	local tags, in_list = {}, false
	for _, line in ipairs(lines) do
		local value = line:match("^tags:%s*(.-)%s*$")
		if value then
			in_list = value == ""
			for tag in value:gsub("^%[", ""):gsub("%]$", ""):gmatch("[^,%s]+") do
				tags[#tags + 1] = tag
			end
		elseif in_list then
			local item = line:match("^%s*%-%s*(%S+)")
			if item then
				tags[#tags + 1] = item
			else
				in_list = false
			end
		end
	end
	return tags
end

---@param path string
---@return string[]
local function read_frontmatter(path)
	local file = io.open(path, "r")
	if not file then
		return {}
	end
	local lines = {}
	if file:read("*l") == "---" then
		for line in file:lines() do
			if line == "---" then
				break
			end
			lines[#lines + 1] = line
		end
	end
	file:close()
	return lines
end

-- Rescanned per request: reads only frontmatter, so it stays cheap and never
-- goes stale after renames or Obsidian Sync.
---@param root string
---@return table<string, integer> tag -> number of notes using it
local function vault_tags(root)
	local counts = {}
	for name, kind in
		vim.fs.dir(root, {
			depth = math.huge,
			skip = function(dir)
				return not dir:match("^%.")
			end,
		})
	do
		if kind == "file" and name:match("%.md$") then
			for _, tag in ipairs(parse_tags(read_frontmatter(root .. "/" .. name))) do
				counts[tag] = (counts[tag] or 0) + 1
			end
		end
	end
	return counts
end

-- Whether the cursor is in a tag position: on a `tags:` line, or on a `- `
-- item of the list under it, inside the leading frontmatter.
---@param bufnr integer
---@param row integer 1-based
---@param before_cursor string
local function in_tags(bufnr, row, before_cursor)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, row, false)
	if lines[1] ~= "---" or row == 1 then
		return false
	end
	for i = 2, row - 1 do
		if lines[i] == "---" then
			return false
		end
	end
	if before_cursor:match("^tags:") then
		return true
	end
	if not before_cursor:match("^%s*%-%s*[^%s]*$") then
		return false
	end
	for i = row - 1, 2, -1 do
		if lines[i]:match("^tags:%s*$") then
			return true
		elseif not lines[i]:match("^%s*%-") then
			return false
		end
	end
	return false
end

function M:get_completions(ctx, callback)
	local root = vim.fs.root(ctx.bufnr, ".obsidian")
	local row, col = ctx.cursor[1], ctx.cursor[2]
	if not root or not in_tags(ctx.bufnr, row, ctx.line:sub(1, col)) then
		callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
		return
	end

	local present = {}
	for _, tag in ipairs(parse_tags({ ctx.line })) do
		present[tag] = true
	end

	local kind = require("blink.cmp.types").CompletionItemKind.Keyword
	local items = {}
	for tag, count in pairs(vault_tags(root)) do
		if not present[tag] then
			items[#items + 1] = {
				label = tag,
				kind = kind,
				labelDetails = { description = tostring(count) },
				-- Most-used tags first among equal matches.
				sortText = ("%06d%s"):format(1e6 - count, tag),
			}
		end
	end
	callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

return M
