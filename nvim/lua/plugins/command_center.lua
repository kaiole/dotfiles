vim.opt.runtimepath:prepend(vim.fn.expand("~/personal/command-center"))
require("command-center").setup({
	width = 50, -- Columns or a percentage, e.g. "60%".
	max_height = 10, -- Rows or a percentage; caps wrapped content.
	border = "single", -- none, single, double, rounded, solid, shadow.
	wrap = false,
	position = {
		row = "50%", -- Percentage of available space, or a zero-based row.
		col = "50%", -- Percentage of available space, or a zero-based column.
	},
})
