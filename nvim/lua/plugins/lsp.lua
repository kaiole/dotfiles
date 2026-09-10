vim.lsp.enable({ "lua_ls", "ts_ls", "eslint", "rust_analyzer", "clangd", "pyright", "neocmake" })

vim.lsp.config("neocmake", {
	cmd = { "neocmakelsp", "stdio" },
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
