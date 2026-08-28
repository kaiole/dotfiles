local competitive_programming_template = {
    "#include <bits/stdc++.h>",
    "using namespace std;",
    "",
    "int main() {",
    "    ios::sync_with_stdio(false);",
    "    cin.tie(0);",
    "",
    "    return 0;",
    "}",
}

vim.api.nvim_create_user_command("WB", function(opts)
    local directory = vim.fn.fnamemodify(vim.fn.expand(opts.args), ":p")
    local main_cpp = directory .. "/main.cpp"

    if vim.fn.filereadable(main_cpp) == 1 then
        vim.notify("main.cpp already exists: " .. main_cpp, vim.log.levels.ERROR)
        return
    end

    if vim.fn.mkdir(directory, "p") == 0 and vim.fn.isdirectory(directory) == 0 then
        vim.notify("Could not create directory: " .. directory, vim.log.levels.ERROR)
        return
    end

    local ok, error_message = pcall(vim.fn.writefile, competitive_programming_template, main_cpp)
    if not ok then
        vim.notify("Could not create main.cpp: " .. error_message, vim.log.levels.ERROR)
        return
    end

    vim.cmd.edit(vim.fn.fnameescape(main_cpp))
end, {
    nargs = 1,
    complete = "dir",
    desc = "Create a competitive programming problem directory and main.cpp",
})
