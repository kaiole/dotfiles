vim.g.mapleader = " "

require("statusline")

require("config.set")
require("config.pack")
require("config.commands")

require("plugins.treesitter")
require("plugins.lsp")
require("plugins.telescope")
require("plugins.undotree")
require("plugins.theme")
require("plugins.harpoon")
require("plugins.render_markdown")
require("plugins.luasnip")
require("plugins.blink")
require("plugins.oil")
require("plugins.conform")

require("config.map")
