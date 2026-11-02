-- Git info is cached per repository root and refreshed in the background;
-- buffers only remember which root they belong to.
local git_cache = {}
local buf_repo = {}
local git_jobs = {}
local diag_cache = {}

local group = vim.api.nvim_create_augroup("statusline", { clear = true })

local function run_git(repo, args, on_exit)
	local cmd = { "git", "--no-optional-locks", "-C", repo }
	vim.list_extend(cmd, args)
	on_exit = vim.schedule_wrap(on_exit)

	local ok = pcall(vim.system, cmd, { text = true }, function(result)
		on_exit(result.code == 0 and vim.split(result.stdout or "", "\n", { trimempty = true }) or nil)
	end)
	if not ok then
		on_exit(nil)
	end
end

local function buf_dir(bufnr)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local dir = vim.uv.cwd()

	if bufname ~= "" then
		local normalized = vim.fs.normalize(bufname)
		if vim.fn.isdirectory(normalized) == 1 then
			dir = normalized
		else
			dir = vim.fs.dirname(normalized)
		end
	end

	return dir
end

-- Resolve symlinks first, as git does, so ~/.config/nvim maps to ~/dotfiles.
local function find_repo(bufnr)
	local dir = vim.uv.fs_realpath(buf_dir(bufnr))
	return dir and vim.fs.root(dir, ".git")
end

local function parse_numstat(lines)
	local added = 0
	local removed = 0

	for _, line in ipairs(lines) do
		local a, r = line:match("^(%d+)%s+(%d+)%s+")
		if a and r then
			added = added + tonumber(a)
			removed = removed + tonumber(r)
		end
	end

	return added, removed
end

local function parse_status(lines)
	local branch = ""
	local unborn = false
	local changed = 0

	for _, line in ipairs(lines) do
		local head = line:match("^# branch%.head (.+)$")
		if head then
			branch = head == "(detached)" and "HEAD" or head
		elseif line == "# branch.oid (initial)" then
			unborn = true
		elseif line:match("^[12] ") then
			local x = line:sub(3, 3)
			local y = line:sub(4, 4)
			if x ~= "D" and y ~= "D" and (x == "M" or x == "R" or y == "M") then
				changed = changed + 1
			end
		end
	end

	return branch, unborn, changed
end

local function redraw_statusline()
	vim.cmd("redrawstatus")
end

-- Line counts are relative to HEAD; with no commits yet, relative to the
-- empty tree (its hash depends on the repo's object format).
local function diff_numstat(repo, unborn, numstat, on_done)
	if numstat or not unborn then
		on_done(numstat or {})
		return
	end

	run_git(repo, { "hash-object", "-t", "tree", "/dev/null" }, function(tree)
		if not tree or not tree[1] then
			on_done({})
			return
		end
		run_git(repo, { "diff", "--numstat", tree[1], "--" }, function(lines)
			on_done(lines or {})
		end)
	end)
end

-- At most one refresh per repo runs at a time; requests made meanwhile
-- collapse into a single rerun once it finishes.
local function refresh_git(repo)
	if git_jobs[repo] then
		git_jobs[repo] = "queued"
		return
	end
	git_jobs[repo] = "running"

	local function finish(info)
		local queued = git_jobs[repo] == "queued"
		git_jobs[repo] = nil

		if not vim.deep_equal(git_cache[repo], info) then
			git_cache[repo] = info
			vim.cmd("redrawstatus!")
		end
		if queued then
			refresh_git(repo)
		end
	end

	local status, numstat
	local pending = 2
	local function collect()
		pending = pending - 1
		if pending > 0 then
			return
		end
		if not status then
			finish(nil)
			return
		end

		local branch, unborn, changed = parse_status(status)
		diff_numstat(repo, unborn, numstat, function(lines)
			local added, removed = parse_numstat(lines)
			finish({ branch = branch, added = added, removed = removed, changed = changed })
		end)
	end

	run_git(repo, { "status", "--porcelain=v2", "--branch" }, function(lines)
		status = lines
		collect()
	end)
	run_git(repo, { "diff", "--numstat", "HEAD", "--" }, function(lines)
		numstat = lines
		collect()
	end)
end

local function update_git_cache(bufnr)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local repo = find_repo(bufnr)
	buf_repo[bufnr] = repo
	if repo then
		refresh_git(repo)
	end
end

local function update_diag_cache(bufnr)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	diag_cache[bufnr] = {
		errors = #vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR }),
		warns = #vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.WARN }),
		info = #vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.INFO }),
		hints = #vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.HINT }),
	}
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "FocusGained", "VimEnter", "DirChanged" }, {
	group = group,
	callback = function(args)
		local bufnr = args.buf == 0 and vim.api.nvim_get_current_buf() or args.buf
		update_git_cache(bufnr)
		redraw_statusline()
	end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "DiagnosticChanged", "VimEnter" }, {
	group = group,
	callback = function(args)
		local bufnr = args.buf == 0 and vim.api.nvim_get_current_buf() or args.buf
		update_diag_cache(bufnr)
		redraw_statusline()
	end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
	group = group,
	callback = function(args)
		buf_repo[args.buf] = nil
		diag_cache[args.buf] = nil
	end,
})

local function cached_git(bufnr)
	local repo = buf_repo[bufnr]
	return repo and git_cache[repo] or {
		branch = "",
		added = 0,
		removed = 0,
		changed = 0,
	}
end

local function cached_diag(bufnr)
	return diag_cache[bufnr] or {
		errors = 0,
		warns = 0,
		info = 0,
		hints = 0,
	}
end

function StatusLine()
	local bufnr = vim.api.nvim_get_current_buf()
	local git = cached_git(bufnr)
	local diag = cached_diag(bufnr)
	local parts = {}

	if git.branch ~= "" then
		table.insert(parts, "[" .. git.branch .. "]")
	end

	local git_parts = {}
	if git.added > 0 then
		table.insert(git_parts, "+" .. git.added)
	end
	if git.removed > 0 then
		table.insert(git_parts, "-" .. git.removed)
	end
	if git.changed > 0 then
		table.insert(git_parts, "~" .. git.changed)
	end
	if #git_parts > 0 then
		table.insert(parts, table.concat(git_parts, " "))
	end

	table.insert(parts, "%f %m")

	local diag_parts = {}
	if diag.errors > 0 then
		table.insert(diag_parts, "E:" .. diag.errors)
	end
	if diag.warns > 0 then
		table.insert(diag_parts, "W:" .. diag.warns)
	end
	if diag.info > 0 then
		table.insert(diag_parts, "I:" .. diag.info)
	end
	if diag.hints > 0 then
		table.insert(diag_parts, "H:" .. diag.hints)
	end
	if #diag_parts > 0 then
		table.insert(parts, table.concat(diag_parts, " "))
	end

	table.insert(parts, "%=%l,%c %y%r")

	return table.concat(parts, " ")
end

vim.o.statusline = "%{%v:lua.StatusLine()%}"
