-- Indent counterpart of ftplugin/ocamlinterface.lua. It can't live there: the
-- indent loader runs afterwards and undoes indent settings set by ftplugins.
vim.cmd.runtime("indent/ocaml.vim")
