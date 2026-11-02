-- Build steps. vim.pack has no `build` key; it fires PackChanged after a plugin
-- is installed or updated. Registered before vim.pack.add to catch first installs.
vim.api.nvim_create_autocmd("PackChanged", {
	group = vim.api.nvim_create_augroup("pack_build", { clear = true }),
	callback = function(ev)
		local name, kind = ev.data.spec.name, ev.data.kind
		if kind ~= "install" and kind ~= "update" then
			return
		end
		if name == "telescope-fzf-native.nvim" then
			-- Synchronous, so the library exists before plugins/telescope.lua loads it.
			local result = vim.system({ "make" }, { cwd = ev.data.path }):wait()
			if result.code ~= 0 then
				vim.notify("telescope-fzf-native: make failed\n" .. result.stderr, vim.log.levels.ERROR)
			end
		elseif name == "nvim-treesitter" and kind == "update" then
			-- New queries expect new parser revisions; first installs are handled by
			-- install() in plugins/treesitter.lua.
			if not ev.data.active then
				vim.cmd.packadd("nvim-treesitter")
			end
			vim.cmd("TSUpdate")
		end
	end,
})

vim.pack.add({
	{ src = "https://github.com/neovim/nvim-lspconfig" },
	{ src = "https://github.com/nvim-lua/plenary.nvim" },
	{ src = "https://github.com/nvim-telescope/telescope.nvim" },
	{ src = "https://github.com/nvim-telescope/telescope-fzf-native.nvim" },
	{ src = "https://github.com/MeanderingProgrammer/render-markdown.nvim" },
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter-context" },
	{ src = "https://github.com/L3MON4D3/LuaSnip" },
	{ src = "https://github.com/saghen/blink.cmp", version = vim.version.range("1.*") },
	{ src = "https://github.com/stevearc/oil.nvim" },
	{ src = "https://github.com/stevearc/conform.nvim" },
})
