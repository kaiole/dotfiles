-- Run from nvim/: nvim --headless -u NONE -l tests/theme_cpp.lua
-- Requires the installed C++ parser, nvim-treesitter queries, and clangd.
local api = vim.api
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(root .. "/after")
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site")
vim.cmd.packadd("nvim-treesitter")
vim.o.swapfile = false

-- Pin this regression to safespace without changing the active palette on disk.
local palette = dofile(root .. "/../theme/palettes/safespace.lua")
package.loaded["config.theme"] = {
	palette = function()
		return palette
	end,
}
vim.cmd.colorscheme("palette")

local roles = {
	keyword = "syntax_keyword",
	type = "syntax_type",
	variable = "syntax_variable",
	parameter = "syntax_param",
	member = "syntax_member",
	constant = "syntax_constant",
	builtin = "syntax_constant_builtin",
	["function"] = "syntax_function",
	call = "syntax_call",
	string = "syntax_string",
	comment = "syntax_comment",
	punctuation = "syntax_punctuation",
}
local checks, failures = 0, {}

local function foreground(buf, row, col, semantic)
	local color, priority = nil, -1
	local groups = {}
	local function overlay(group, rank)
		local fg = api.nvim_get_hl(0, { name = group, link = false }).fg
		groups[#groups + 1] = group
		if fg and rank >= priority then
			color, priority = fg, rank
		end
	end
	for _, capture in ipairs(vim.treesitter.get_captures_at_pos(buf, row, col)) do
		overlay("@" .. capture.capture .. ".cpp", tonumber(capture.metadata.priority) or vim.hl.priorities.treesitter)
	end
	if semantic then
		-- Public token inspection works for the entire fixture, even off-screen in headless mode.
		for _, token in ipairs(vim.lsp.semantic_tokens.get_at_pos(buf, row, col) or {}) do
			overlay("@lsp.type." .. token.type .. ".cpp", vim.hl.priorities.semantic_tokens)
			for modifier in pairs(token.modifiers) do
				overlay("@lsp.mod." .. modifier .. ".cpp", vim.hl.priorities.semantic_tokens + 1)
				overlay(
					"@lsp.typemod." .. token.type .. "." .. modifier .. ".cpp",
					vim.hl.priorities.semantic_tokens + 2
				)
			end
		end
	end
	return color, groups
end

local function check(buf, row, col, role, token, semantic)
	checks = checks + 1
	local actual, groups = foreground(buf, row, col, semantic)
	local expected = tonumber(palette[assert(roles[role], role)]:sub(2), 16)
	if actual ~= expected then
		failures[#failures + 1] = ("%s:%d:%d %s should be %s (%s), got %s via %s"):format(
			semantic and "clangd" or "treesitter",
			row + 1,
			col + 1,
			token,
			role,
			palette[roles[role]],
			actual and ("#%06x"):format(actual) or "none",
			table.concat(groups, ", ")
		)
	end
end

local function verify(buf, semantic)
	for row, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
		local code, expectations = line:match("^(.-)// (.+:.+)$")
		if code then
			for role, tokens in expectations:gmatch("(%a+):([^;]+)") do
				for token in tokens:gmatch("[^,]+") do
					token = vim.trim(token)
					local first, last, offset = nil, nil, 1
					repeat
						first, last = code:find(token, offset, true)
						assert(first and last, "fixture token not found: " .. token .. " in " .. code)
						offset = last + 1
					until not token:match("^[%w_]+$")
						or (
							not code:sub(first - 1, first - 1):match("[%w_]")
							and not code:sub(last + 1, last + 1):match("[%w_]")
						)
					check(buf, row - 1, first - 1, role, token, semantic)
				end
			end
		elseif line:match("^%s*// this nullptr") then
			check(buf, row - 1, assert(line:find("nullptr", 1, true)) - 1, "comment", "comment keyword", semantic)
		end
	end
end

local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local source = directory .. "/theme.cpp"
vim.fn.writefile(vim.fn.readfile(root .. "/tests/fixtures/theme.cpp"), source)
vim.fn.writefile({ "-std=c++23" }, directory .. "/compile_flags.txt")
vim.cmd.edit(vim.fn.fnameescape(source))
local buf = api.nvim_get_current_buf()
vim.bo[buf].filetype = "cpp"
vim.treesitter.start(buf, "cpp")
local parser = vim.treesitter.get_parser(buf, "cpp")
assert(not parser:parse()[1]:root():has_error(), "fixture has C++ parse errors")
verify(buf, false)

-- Module syntax gets its own translation unit; it cannot coexist with the fixture's headers.
local modules = api.nvim_create_buf(false, true)
api.nvim_buf_set_lines(modules, 0, -1, false, {
	"export module sample; // keyword:export,module",
	"import other; // keyword:import",
})
vim.bo[modules].filetype = "cpp"
vim.treesitter.start(modules, "cpp")
assert(not vim.treesitter.get_parser(modules):parse()[1]:root():has_error(), "module sample has parse errors")
verify(modules, false)

local client = assert(
	vim.lsp.start({
		name = "theme-test-clangd",
		cmd = { "clangd", "--background-index=false", "--clang-tidy=false" },
		root_dir = directory,
	}),
	"could not start clangd"
)
assert(
	vim.wait(20000, function()
		local tokens = vim.lsp.semantic_tokens.get_at_pos(buf, 6, 10)
		return tokens and #tokens > 0
	end, 20),
	"timed out waiting for clangd semantic tokens"
)
verify(buf, true)
assert(vim.lsp.get_client_by_id(client)):stop(true)
vim.fn.delete(directory, "rf")
if #failures > 0 then
	error(table.concat(failures, "\n"))
end
print(("C++ highlighting: %d checks passed (Tree-sitter + clangd)"):format(checks))
