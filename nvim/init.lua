vim.g.mapleader = " "

require("statusline")

require("config.set")
require("config.pack")
require("config.cmds")
require("config.cpp")

require("plugins.treesitter")
require("plugins.treesitter_context")
require("plugins.lsp")
require("plugins.telescope")
require("plugins.undotree")
require("config.theme").apply()
require("plugins.harpoon")
require("plugins.render_markdown")
require("plugins.luasnip")
require("plugins.blink")
require("plugins.oil")
require("plugins.conform")
require("plugins.command_center")

require("config.map")
