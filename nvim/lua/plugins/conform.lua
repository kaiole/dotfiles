require("conform").setup({
	formatters_by_ft = {
		javascript = { "prettier" },
		javascriptreact = { "prettier" },
		typescript = { "prettier" },
		typescriptreact = { "prettier" },
		markdown = { "prettier" },
		json = { "prettier" },
		html = { "prettier" },
		css = { "prettier" },
		yaml = { "prettier" },
		cmake = { "cmake_format" },
		rust = { "rustfmt" },
		cpp = { "clang_format" },
		c = { "clang_format" },
		lua = { "stylua" },
		python = { "autopep8" },
	},
	formatters = {
		clang_format = {
			prepend_args = { "-style=file", "-fallback-style=LLVM" },
		},
		prettier = {
			command = vim.fn.expand("~/.npm-global/bin/prettier"),
			prepend_args = { "--prose-wrap", "always", "--ignore-path", "/dev/null" },
		},
		autopep8 = {
			prepend_args = { "--max-line-length=80", "--aggressive" },
		},
	},
})

vim.keymap.set("n", "gw", function()
	require("conform").format({ async = false, lsp_format = "fallback" })
end)

vim.keymap.set("x", "gw", function()
	require("conform").format({ async = false, lsp_format = "fallback" })
end)
