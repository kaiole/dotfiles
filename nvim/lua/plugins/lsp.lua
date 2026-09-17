vim.lsp.enable({ "lua_ls", "ts_ls", "eslint", "rust_analyzer", "clangd", "pyright", "neocmake" })

vim.lsp.config("neocmake", {
	cmd = { "neocmakelsp", "stdio" },
})

-- Used only when clangd cannot find a compile command for the file.
-- A project's compile_commands.json still takes precedence.
vim.lsp.config("clangd", {
	init_options = {
		fallbackFlags = { "-std=c++23" },
	},
})

vim.lsp.config("lua_ls", {
	settings = {
		Lua = {
			runtime = {
				version = "LuaJIT",
			},
			diagnostics = {
				globals = {
					"vim",
					"require",
				},
			},
			telemetry = {
				enable = false,
			},
		},
	},
})

vim.keymap.set("n", "grd", vim.lsp.buf.definition, { silent = true })
