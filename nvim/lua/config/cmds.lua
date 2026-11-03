vim.api.nvim_create_user_command("Cpp", function(opts)
	require("config.actions.cpp_project").create(opts.args)
end, {
	nargs = "?",
	complete = "dir",
	desc = "Create C++ project configs from saved snippets (default: current directory)",
})

vim.api.nvim_create_user_command("CppLib", function(opts)
	require("config.actions.cpp_lib").create(opts.args, opts.bang)
end, {
	nargs = 1,
	bang = true,
	complete = "dir",
	desc = "Create one C++ library and expand cmlib (! for header-only cmlibh) in its CMakeLists.txt",
})

vim.api.nvim_create_user_command("Whitebox", function(opts)
	require("config.actions.comp_prog").create(opts.args)
end, {
	nargs = 1,
	complete = "dir",
	desc = "Create a competitive programming problem directory and main.cpp",
})
