# AGENTS.md — Neovim config

Plain-Lua config (no framework) using Neovim's built-in `vim.pack` (needs
Neovim 0.12+). It is `nvim/` in `~/dotfiles`, symlinked to `~/.config/nvim`.
Leader is `<Space>`.

## Where things are

```text
init.lua              entry point; requires everything in a fixed order
nvim-pack-lock.json   vim.pack lockfile (commit after plugin changes)
colors/palette.lua    the only colorscheme; palette-driven (see Theming)
snippets/             LuaSnip snippets, filename = filetype (cpp, cmake, markdown, yaml)
lua/statusline.lua    plugin-free statusline (git + diagnostics, cached per buffer)
lua/config/
  pack.lua            plugin list (vim.pack.add)
  set.lua             options and option-related autocmds
  map.lua             global keymaps (plugin keymaps live in the plugin's file)
  cmds.lua            user commands (:Whitebox, :MarkdownBlockquote)
  cpp.lua             C/C++ header/source switching (<leader>hd / <leader>hs)
  theme.lua           loads the active palette; apply() / reload()
  actions/            helper functions used by cmds.lua / map.lua
lua/plugins/<name>.lua   setup + keymaps for one plugin each
```

Plugins: lspconfig, treesitter (`main` branch), treesitter-context, telescope
(+ fzf-native), blink.cmp, LuaSnip, conform, oil, harpoon (v1 API), undotree,
render-markdown.

LSP servers are enabled in `plugins/lsp.lua`. They aren't installed by this
config (no Mason), so they must be on `$PATH`. Formatters are mapped per
filetype in `plugins/conform.lua` and run manually with `gw` (no
format-on-save).

## Conventions

- **Add a plugin:** add it to `config/pack.lua`, create `plugins/<name>.lua`,
  and add the `require` to `init.lua`. Everything loads at startup (no lazy
  loading), and order in `init.lua` matters: `config.theme`.apply() runs
  before plugins that read highlights, and `config.map` runs last.
- **Keymaps** go in the plugin's own file; only generic ones go in `map.lua`.
- **Reusable logic** goes in `config/actions/`. Filetype-specific behavior
  uses `FileType` autocmds with buffer-local maps.
- Use `vim.pack` only (no lazy.nvim, Mason or packer).
- Format with `stylua` (defaults, tabs). `stylua --check .` should pass.

## External pieces (outside this directory)

- `lua/blink_obsidian` is a symlink to `~/personal/blink-obsidian`. It is a
  custom blink.cmp source for Obsidian wiki links, registered in
  `plugins/blink.lua`. The symlink is relative, so `~/personal/` must sit next
  to `~/dotfiles/`.
- `plugins/command_center.lua` loads `~/personal/command-center` (a local
  plugin) and skips itself if that directory is missing.
- `<C-f>` in `map.lua` launches `~/.local/bin/tmux-sessionizer`
  (source: `~/dotfiles/scripts/`).

## Theming

Colors are not defined here. The shared system is documented in
`~/dotfiles/theme/AGENTS.md`; read it before touching colors.

- Palettes: `~/dotfiles/theme/palettes/<name>.lua`; the active one is named in
  the gitignored `theme/current`. Switch with `theme set <name>`, which also
  calls `require("config.theme").reload()` on running nvims.
- `colors/palette.lua` is one `groups` table of
  `HlGroup = { fg = c.<role>, bg = c.<role> }`. Use `c.<role>` keys, never raw
  hex. The UI is intentionally transparent (`NormalFloat`, `FloatBorder` and
  the Telescope groups are `{}`).
- **Gotcha:** plugins set `default = true` highlight links after the
  colorscheme loads, which override groups left empty. `reload()` restores
  them, and `plugins/render_markdown.lua` re-clears its groups in
  `vim.schedule`. Do the same for any plugin that fights the palette.

## Verifying changes

No test suite. Use `nvim --headless +qa` (startup errors), `:checkhealth`,
and `stylua --check .`.
