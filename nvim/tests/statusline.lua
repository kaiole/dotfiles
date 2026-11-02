-- Run from nvim/: nvim --headless -u NONE -l tests/statusline.lua
vim.o.swapfile = false
vim.o.hidden = true

-- Isolate the throwaway repos from the user's Git configuration.
vim.env.GIT_CONFIG_GLOBAL = "/dev/null"
vim.env.GIT_CONFIG_NOSYSTEM = "1"
vim.env.GIT_AUTHOR_NAME, vim.env.GIT_AUTHOR_EMAIL = "test", "test@example.com"
vim.env.GIT_COMMITTER_NAME, vim.env.GIT_COMMITTER_EMAIL = "test", "test@example.com"

dofile(vim.fn.getcwd() .. "/lua/statusline.lua")

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local failures, count = 0, 0

local function git(directory, ...)
	local result = vim.system({ "git", "-C", directory, ... }, { text = true }):wait()
	assert(result.code == 0, "git " .. table.concat({ ... }, " ") .. ": " .. (result.stderr or ""))
end

local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end

local function repo(name, branch)
	local directory = root .. "/" .. name
	vim.fn.mkdir(directory, "p")
	git(directory, "init", "-q", "-b", branch or "main")
	return directory
end

local function commit(directory, message)
	git(directory, "add", "-A")
	git(directory, "commit", "-q", "-m", message)
end

-- Git segment only: everything before the file name.
local function git_segment()
	return vim.trim((StatusLine():gsub("%%f.*", "")))
end

local function expect(path, expected)
	vim.cmd.edit(vim.fn.fnameescape(path))
	vim.wait(3000, function()
		return git_segment() == expected
	end, 20)
	assert(git_segment() == expected, ("expected %q, got %q"):format(expected, git_segment()))
end

local function test(name, run)
	count = count + 1
	vim.cmd("enew!")
	local ok, err = pcall(run)
	if ok then
		print("PASS " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. "\n  " .. tostring(err))
	end
end

test("clean repository shows only the branch", function()
	local directory = repo("clean")
	write(directory .. "/f.txt", { "a" })
	commit(directory, "init")
	expect(directory .. "/f.txt", "[main]")
end)

test("staged and unstaged edits are summed against HEAD", function()
	local directory = repo("mixed")
	write(directory .. "/f.txt", { "a", "b", "c" })
	write(directory .. "/gone.txt", { "x" })
	commit(directory, "init")
	write(directory .. "/f.txt", { "a", "B", "c", "d" })
	git(directory, "add", "f.txt")
	write(directory .. "/f.txt", { "a", "B", "c", "d", "e" })
	vim.fn.delete(directory .. "/gone.txt")
	write(directory .. "/untracked.txt", {})
	expect(directory .. "/f.txt", "[main] +3 -2 ~1")
end)

test("a staged line removed again nets to no line change", function()
	local directory = repo("overlap")
	write(directory .. "/f.txt", { "a" })
	commit(directory, "init")
	write(directory .. "/f.txt", { "a", "b" })
	git(directory, "add", "f.txt")
	write(directory .. "/f.txt", { "a" })
	expect(directory .. "/f.txt", "[main] ~1")
end)

test("repository without commits shows its branch and staged lines", function()
	local directory = repo("unborn", "dev")
	write(directory .. "/f.txt", { "1", "2" })
	git(directory, "add", "f.txt")
	expect(directory .. "/f.txt", "[dev] +2")
end)

test("detached HEAD", function()
	local directory = repo("detached")
	write(directory .. "/f.txt", { "1" })
	commit(directory, "one")
	write(directory .. "/f.txt", { "2" })
	commit(directory, "two")
	git(directory, "checkout", "-q", "HEAD~1")
	write(directory .. "/f.txt", { "3" })
	expect(directory .. "/f.txt", "[HEAD] +1 -1 ~1")
end)

test("saving refreshes the counts", function()
	local directory = repo("save")
	write(directory .. "/f.txt", { "a" })
	commit(directory, "init")
	expect(directory .. "/f.txt", "[main]")
	vim.api.nvim_buf_set_lines(0, -1, -1, false, { "b" })
	vim.cmd("silent write")
	expect(directory .. "/f.txt", "[main] +1 ~1")
end)

test("symlinked paths resolve to the real repository", function()
	local directory = repo("target")
	write(directory .. "/sub/f.txt", { "a" })
	commit(directory, "init")
	local link = root .. "/link"
	assert(vim.uv.fs_symlink(directory .. "/sub", link))
	expect(link .. "/f.txt", "[main]")
end)

test("files outside a repository show no Git segment", function()
	local path = root .. "/loose/f.txt"
	write(path, { "a" })
	expect(path, "")
end)

vim.cmd("enew!")
vim.fn.delete(root, "rf")
print(string.format("%d/%d statusline tests passed", count - failures, count))
if failures > 0 then
	vim.cmd("cquit 1")
end
