local treesitter_languages = {
	"lua",
	"vim",
	"vimdoc",
	"query",
	"javascript",
	"typescript",
	"tsx",
	"c",
	"cpp",
	"cmake",
	"json",
	"yaml",
	"css",
	"markdown",
	"markdown_inline",
	"bash",
	"toml",
	"rust",
	"python",
	"ocaml",
	"ocaml_interface",
	"ocamllex",
	"menhir",
}

require("nvim-treesitter").setup({
	install_dir = vim.fn.stdpath("data") .. "/site",
})

require("nvim-treesitter").install(treesitter_languages)

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("treesitter_start", { clear = true }),
	callback = function()
		pcall(vim.treesitter.start)
	end,
})

-- A language's queries compile when its first buffer opens, which blocked for
-- ~400 ms on C++ (mostly the nested qualified_identifier highlight patterns) and
-- ~350 ms on TSX. Sessions start without a file, so compile the languages of the
-- cwd project while idle instead; query.get caches them for every later buffer.
local project_languages = {
	{ markers = { "CMakeLists.txt", "compile_commands.json", ".clangd" }, languages = { "cpp" } },
	{ markers = { "Cargo.toml" }, languages = { "rust" } },
	{ markers = { "tsconfig.json" }, languages = { "typescript", "tsx" } },
	{ markers = { "pyproject.toml" }, languages = { "python" } },
}

vim.api.nvim_create_autocmd("UIEnter", {
	group = vim.api.nvim_create_augroup("treesitter_warm", { clear = true }),
	once = true,
	callback = function()
		local pending = {}
		for _, project in ipairs(project_languages) do
			if vim.fs.root(vim.fn.getcwd(), project.markers) then
				for _, language in ipairs(project.languages) do
					for _, query in ipairs({ "highlights", "injections", "context" }) do
						table.insert(pending, { language, query })
					end
				end
			end
		end
		-- One query per tick, so a key pressed meanwhile waits for one compile at most.
		local function step()
			local item = table.remove(pending, 1)
			if item then
				pcall(vim.treesitter.query.get, item[1], item[2])
				vim.defer_fn(step, 10)
			end
		end
		vim.defer_fn(step, 50)
	end,
})
