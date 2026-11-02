local comp_prog = require("config.actions.comp_prog")

vim.api.nvim_create_user_command("Cpp", function(opts)
	require("config.actions.cpp_project").create(opts.args)
end, {
	nargs = "?",
	complete = "dir",
	desc = "Create C++ project configs from saved snippets (default: current directory)",
})

vim.api.nvim_create_user_command("Whitebox", function(opts)
	comp_prog.create_problem(opts.args)
end, {
	nargs = 1,
	complete = "dir",
	desc = "Create a competitive programming problem directory and main.cpp",
})
