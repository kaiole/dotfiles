local square_borders = { "─", "│", "─", "│", "┌", "┐", "┘", "└" }

-- Committed files Neovim can't usefully open; ripgrep already skips binaries for live_grep.
local binary_extensions = {
	"png",
	"jpg",
	"jpeg",
	"gif",
	"webp",
	"ico",
	"bmp",
	"pdf",
	"zip",
	"gz",
	"tar",
	"xz",
	"7z",
	"o",
	"a",
	"so",
	"bin",
	"ttf",
	"otf",
	"woff",
	"woff2",
	"mp3",
	"mp4",
	"wav",
}
-- Debian/Ubuntu (e.g. the ROS distrobox) install fd as fdfind.
local fd = vim.fn.executable("fd") == 1 and "fd" or "fdfind"
local find_command = { fd, "--type", "f", "--color", "never", "--exclude", ".git" }
for _, extension in ipairs(binary_extensions) do
	-- fd globs are case-sensitive; match IMG.JPG as well as img.jpg.
	local glob = extension:gsub("%a", function(letter)
		return "[" .. letter:lower() .. letter:upper() .. "]"
	end)
	vim.list_extend(find_command, { "--exclude", "*." .. glob })
end

-- Directories only; selecting one :edits it, which opens oil.
local find_dirs_command = { fd, "--type", "d", "--color", "never", "--hidden", "--exclude", ".git" }

local dropdown = { theme = "dropdown", borderchars = square_borders }

require("telescope").setup({
	defaults = {
		preview = { treesitter = true },
		mappings = {
			n = {
				["<C-c>"] = require("telescope.actions").close,
			},
		},
	},
	pickers = {
		-- Respect .gitignore; show dotfiles, but never Git's own directory or binaries.
		find_files = vim.tbl_extend("force", dropdown, { find_command = find_command, hidden = true }),
		live_grep = dropdown,
		help_tags = dropdown,
		git_files = dropdown,
		diagnostics = dropdown,
	},
	extensions = {
		fzf = {
			fuzzy = true,
			override_generic_sorter = true,
			override_file_sorter = true,
			case_mode = "smart_case",
		},
	},
})

-- Native fzf sorter (built by the PackChanged hook in config/pack.lua). If the
-- build failed, Telescope keeps working with its Lua sorter.
local fzf_ok, fzf_err = pcall(require("telescope").load_extension, "fzf")
if not fzf_ok then
	vim.notify("telescope-fzf-native not loaded: " .. fzf_err, vim.log.levels.WARN)
end

vim.keymap.set("n", "<leader>ff", "<Cmd>Telescope find_files<CR>")
vim.keymap.set("n", "<leader>fd", function()
	require("telescope.builtin").find_files(vim.tbl_extend("force", dropdown, {
		prompt_title = "Find Directories",
		find_command = find_dirs_command,
	}))
end)
vim.keymap.set("n", "<leader>gr", "<Cmd>Telescope live_grep<CR>")
vim.keymap.set("n", "<leader>gf", "<Cmd>Telescope git_files<CR>")
vim.keymap.set("n", "<leader>gs", "<Cmd>Telescope git_status<CR>")
vim.keymap.set("n", "<leader>ht", "<Cmd>Telescope help_tags<CR>")
vim.keymap.set("n", "<leader>vd", "<Cmd>Telescope diagnostics<CR>")
