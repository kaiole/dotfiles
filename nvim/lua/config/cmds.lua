local comp_prog = require("config.actions.comp_prog")
local cpp = require("config.actions.cpp")
local markdown = require("config.actions.markdown")

vim.api.nvim_create_user_command("Whitebox", function(opts)
	comp_prog.create_problem(opts.args)
end, {
	nargs = 1,
	complete = "dir",
	desc = "Create a competitive programming problem directory and main.cpp",
})

vim.api.nvim_create_user_command("Construct", cpp.insert_special_members, {
	desc = "Insert a default constructor and Rule of Five declarations",
})

vim.api.nvim_create_user_command("MarkdownBlockquote", function(opts)
	markdown.wrap_in_blockquote(opts.line1, opts.line2)
end, {
	range = true,
	desc = "Wrap lines in a Markdown blockquote",
})
