vim.lsp.enable({ "lua_ls", "ts_ls", "eslint", "rust_analyzer", "clangd", "pyright", "neocmake", "markdown_oxide" })

vim.lsp.config("neocmake", {
	cmd = { "neocmakelsp", "stdio" },
})

-- clangd logs at info level to stderr by default, and Neovim records all server
-- stderr in lsp.log, which grew to hundreds of MB. Only keep real errors.
-- -j defaults to one worker per core; each background-index worker holds a full
-- translation unit, so cold indexing peaked at ~1.5 GB on a Hyprland plugin.
-- Two workers cut that peak by ~30% at the cost of a slower first index; the
-- settled footprint (one AST and preamble per open file) is unchanged.
vim.lsp.config("clangd", {
	cmd = { "clangd", "--log=error", "-j=2" },
})

-- Scoped to Obsidian vaults: no `.obsidian` root, no client (e.g. READMEs, pi
-- drafts). Neovim only advertises file watching on macOS/Windows; without it the
-- server misses renames and edits made outside the buffer (oil, Obsidian Sync).
vim.lsp.config("markdown_oxide", {
	root_markers = { ".obsidian" },
	workspace_required = true,
	capabilities = {
		workspace = {
			didChangeWatchedFiles = { dynamicRegistration = true },
		},
	},
	handlers = {
		-- Renaming a note also rewrites the note's own `[[#...]]` links into
		-- `[[new-name#...]]` and drops the `^` of block refs, breaking them.
		-- Same-file links never need changing on a rename, so skip those edits.
		["textDocument/rename"] = function(err, result, ctx)
			local encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
			for _, change in ipairs(result and result.documentChanges or {}) do
				if change.edits then
					local buf = vim.uri_to_bufnr(change.textDocument.uri)
					vim.fn.bufload(buf)
					change.edits = vim.tbl_filter(function(edit)
						local s, e = edit.range.start, edit.range["end"]
						local line = vim.api.nvim_buf_get_lines(buf, s.line, s.line + 1, false)[1] or ""
						local first = vim.str_byteindex(line, encoding, s.character, false)
						local old = line:sub(first + 1, first + 3)
						return not (s.line == e.line and old == "[[#" and edit.newText:sub(1, 3) ~= "[[#")
					end, change.edits)
				end
			end
			vim.lsp.handlers["textDocument/rename"](err, result, ctx)
		end,
	},
})

vim.lsp.config("lua_ls", {
	settings = {
		Lua = {
			runtime = {
				version = "LuaJIT",
			},
			-- Neovim's runtime annotations define `vim` and type its API.
			workspace = {
				checkThirdParty = false,
				library = { vim.env.VIMRUNTIME },
			},
			telemetry = {
				enable = false,
			},
		},
	},
})

vim.keymap.set("n", "grd", vim.lsp.buf.definition, { silent = true })
