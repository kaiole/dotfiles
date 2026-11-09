-- .mli files get their own filetype (plugins/lsp.lua); Neovim ships settings
-- only for `ocaml`, so reuse its comments and matchit pairs.
vim.cmd.runtime("ftplugin/ocaml.vim")
