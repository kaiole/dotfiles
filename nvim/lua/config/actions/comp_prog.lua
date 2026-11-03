local scaffold = require("config.actions.scaffold")

local M = {}

local template = {
	"#include <bits/stdc++.h>",
	"using namespace std;",
	"",
	"int main() {",
	"    ios::sync_with_stdio(false);",
	"    cin.tie(0);",
	"}",
}

local function create(directory_argument)
	local directory = scaffold.directory(directory_argument)
	local path = vim.fs.joinpath(directory, "main.cpp")
	local created = scaffold.write(directory, { { name = "main.cpp", lines = template } })
	if #created == 0 then
		error("main.cpp already exists: " .. path, 0)
	end
	vim.cmd.edit(vim.fn.fnameescape(path))
end

function M.create(directory_argument)
	return scaffold.run("Whitebox", create, directory_argument)
end

return M
