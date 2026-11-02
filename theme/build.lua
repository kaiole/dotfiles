-- Render theme/templates/<path> into <repo>/<path> using the active palette.
-- Usage: nvim -l theme/build.lua [palette]
--
-- Placeholders:
--   {{key}}      #rrggbb
--   {{key:hex}}  rrggbb
--   {{key:rgb}}  r;g;b   (ANSI truecolor, e.g. dircolors / fastfetch)
--   {{key:list}} r, g, b (JSON integer arrays, e.g. Chromium themes)
--
-- See theme/AGENTS.md for what each palette key means.

local theme = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/load.lua")
local repo = vim.fs.dirname(theme.root)
local templates = theme.root .. "/templates"

local function fail(msg)
	io.stderr:write("theme: " .. msg .. "\n")
	os.exit(1)
end

local ok, palette, name = pcall(theme.palette, arg[1])
if not ok then
	fail(palette)
end

-- Every palette, not just the one being built, must define exactly the default
-- one's keys as #rrggbb, so `theme set` can never switch to a broken palette.
local reference = theme.palette(theme.default)
for file in vim.fs.dir(theme.root .. "/palettes") do
	local pname = file:match("^(.+)%.lua$")
	if pname then
		local p_ok, p = pcall(theme.palette, pname)
		if not p_ok then
			fail(p)
		end
		for key in pairs(reference) do
			if p[key] == nil then
				fail(("palette '%s' is missing key '%s'"):format(pname, key))
			end
		end
		for key, value in pairs(p) do
			if reference[key] == nil then
				fail(("palette '%s' has key '%s', which '%s' lacks"):format(pname, key, theme.default))
			end
			if type(value) ~= "string" or not value:match("^#%x%x%x%x%x%x$") then
				fail(("palette '%s': %s = %s is not #rrggbb"):format(pname, key, vim.inspect(value)))
			end
		end
	end
end

local formats = {
	[""] = function(v)
		return v:lower()
	end,
	hex = function(v)
		return v:sub(2):lower()
	end,
	rgb = function(v)
		return ("%d;%d;%d"):format(tonumber(v:sub(2, 3), 16), tonumber(v:sub(4, 5), 16), tonumber(v:sub(6, 7), 16))
	end,
	list = function(v)
		return ("%d, %d, %d"):format(tonumber(v:sub(2, 3), 16), tonumber(v:sub(4, 5), 16), tonumber(v:sub(6, 7), 16))
	end,
}

local function render(text, rel)
	return text:gsub("{{%s*([%w_]+):?(%w*)%s*}}", function(key, fmt)
		local value = palette[key]
		if not value then
			fail(("%s: unknown key '%s'"):format(rel, key))
		end
		if not formats[fmt] then
			fail(("%s: unknown format '%s:%s'"):format(rel, key, fmt))
		end
		return formats[fmt](value)
	end)
end

-- Render everything before writing anything, so a bad template leaves outputs untouched.
local outputs = {}
for rel, kind in vim.fs.dir(templates, { depth = math.huge }) do
	if kind == "file" then
		local f = assert(io.open(templates .. "/" .. rel))
		outputs[#outputs + 1] = { rel = rel, text = render(f:read("*a"), rel) }
		f:close()
	end
end
table.sort(outputs, function(a, b)
	return a.rel < b.rel
end)

for _, out in ipairs(outputs) do
	local path = repo .. "/" .. out.rel
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local f = assert(io.open(path, "w"))
	f:write(out.text)
	f:close()
	io.stdout:write("  " .. out.rel .. "\n")
	if vim.system({ "git", "-C", repo, "check-ignore", "-q", out.rel }):wait().code ~= 0 then
		io.stderr:write("theme: warning: " .. out.rel .. " is not in .gitignore\n")
	end
end
io.stdout:write(("theme: rendered %d files with '%s'\n"):format(#outputs, name))
