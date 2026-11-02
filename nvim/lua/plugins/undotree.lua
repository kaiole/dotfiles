vim.cmd.packadd("nvim.undotree") -- Built-in since Neovim 0.12; :Undotree toggles.

vim.keymap.set("n", "<leader>u", vim.cmd.Undotree)
