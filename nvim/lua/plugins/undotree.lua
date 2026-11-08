-- mbbill/undotree. Options are read when its plugin/ script loads after init.lua.
vim.g.undotree_SetFocusWhenToggle = 1

vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle)
