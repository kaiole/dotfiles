vim.filetype.add({
	extension = {
		mdx = "markdown.mdx",
	},
})

require("conform").setup({
	formatters_by_ft = {
		javascript = { "prettier" },
		javascriptreact = { "prettier" },
		typescript = { "prettier" },
		typescriptreact = { "prettier" },
		markdown = { "prettier" },
		["markdown.mdx"] = { "prettier" },
		json = { "prettier" },
		html = { "prettier" },
		css = { "prettier" },
		yaml = { "prettier" },
		cmake = { "cmake_format" },
		rust = { "rustfmt" },
		cpp = { "clang_format" },
		c = { "clang_format" },
		lua = { "stylua" },
		python = { "ruff_format" },
		ocaml = { "ocamlformat" },
		ocamlinterface = { "ocamlformat" },
		dune = { "format-dune-file" },
		sh = { "shfmt" },
		bash = { "shfmt" },
	},
	formatters = {
		clang_format = {
			prepend_args = { "-style=file", "-fallback-style=LLVM" },
		},
		prettier = {
			command = vim.fn.expand("~/.npm-global/bin/prettier"),
			prepend_args = { "--prose-wrap", "always", "--ignore-path", "/dev/null" },
			options = {
				ft_parsers = {
					["markdown.mdx"] = "mdx",
				},
			},
		},
	},
})

vim.keymap.set({ "n", "x" }, "gw", function()
	require("conform").format({ async = false, lsp_format = "fallback" })
end)
