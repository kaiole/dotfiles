# AGENTS.md — Neovim config

Plain-Lua config (no framework), Neovim 0.12+, built-in `vim.pack`.
This is `~/dotfiles/nvim`, symlinked to `~/.config/nvim`. Leader is `<Space>`.

## How to investigate

- Treat questions here as questions about the user's configured editing and
  development workflows unless they indicate otherwise. This repo defines
  project templates and tool policies, not just Neovim UI settings.
- Use the maps below to find the owning definitions. Read those and follow
  their connections before asking the user where something lives or giving
  generic tool advice. Search contents, not just filenames: a tool's policy
  may be embedded in a snippet for another filetype.
- Distinguish inserted/generated text, editor behavior, and external tool
  transformations. Trace the relevant path from shortcut/command through
  provider to policy, including files outside this directory.
- Snippets are the user's reusable templates. Tools consume the resulting
  project files, not the snippets directly; inspect the actual project file
  when available before assuming it still matches its template.

## Templates and development policy

Snippet filenames describe the filetype where they expand, not necessarily
which language or workflow they configure.

| Purpose | Source and entry points |
| --- | --- |
| `.clangd`, `.clang-format`, `.clang-tidy` | `snippets/yaml.lua`: `clangd` (database in `build/dev`), `fmt`, `tidy`, `tidychill` (relaxations for `tests/`) |
| `.ocamlformat` | `snippets/conf.lua`: `ofmt` (default profile, pinned version, one line per match case, `;;` after multi-line top-level definitions); `.ocamlformat` is mapped to the `conf` filetype in `lua/plugins/lsp.lua` |
| CMake project files | `snippets/cmake.lua`: `cm` (top-level `CMakeLists.txt`), `cmsolo`/`cmsoloh` (`cm` plus one library at the root, named after the `project()` field), `cmwarn` (`<ns>::warnings`), `cminstall` + `cmconfig` (install export, package config). Its header comment states the rules every target follows |
| Library `CMakeLists.txt` | `snippets/cmake.lua`: `cmlib` (STATIC), `cmlibh` (header-only). Name defaults to the buffer's directory in snake_case, namespace to the nearest `project()` (`lua/config/cmake.lua`) |
| Dependencies and test/bench executables | `snippets/cmake.lua`: `cmfetch` (system package, else pinned, hashed download), `cmgt`/`cmgb` (GoogleTest/Benchmark that way), `cmgtx`/`cmgbx` (executables in `<lib>/tests`, `<lib>/bench`, linking the alias in the parent's saved `CMakeLists.txt`); `cmapp` (executable in `apps/CMakeLists.txt`: target `<project>_<name>`, binary `<name>`, main in `apps/<name>.cpp`) |
| CMake presets | `snippets/json.lua`: `cmpresets` (`dev` ASan/UBSan, `tsan`, `lint` clang-tidy, `release`/`release-clang`; warnings as errors, header self-containment check) |
| C++ gate script | `snippets/sh.lua`: `check` (clang-format, then the `lint`, `dev`, `tsan` workflows) |
| Markdown prompt drafts and notes | `snippets/markdown.lua`: `draft` (coding prompt), `frontmatter`, wiki `link`, `sol`, math/LaTeX and more |
| C++ project starter | `:Cpp [directory]` → `lua/config/actions/cpp_project.lua`: writes the files above from the saved snippets plus `.gitignore`, then expands `cm` into `CMakeLists.txt` |
| C++ single-library project | `:CppSolo[!] [directory]` → `create_solo` in `lua/config/actions/cpp_project.lua`: `:Cpp`'s files plus `include/<name>/<name>.hpp`, source (not with `!`), `tests/`; expands `cmsolo` (`!`: `cmsoloh`) into `CMakeLists.txt`. For a project that is one library; use `:Cpp` + `:CppLib` when it holds several or an app |
| C++ library starter | `:CppLib[!] <directory>` → `lua/config/actions/cpp_lib.lua`: header, source (not with `!`), `tests/`; expands `cmlib` (`!`: `cmlibh`); puts the parent's `add_subdirectory(...)` line in the unnamed register instead of editing it |
| Competitive-programming starter | `:Whitebox <directory>` → `lua/config/actions/comp_prog.lua`: creates and opens `main.cpp` |

The starters are registered in `lua/config/cmds.lua` and share
`lua/config/actions/scaffold.lua`: they only create missing files (an existing
path or modified buffer is skipped) and never touch Git, the build, or cwd.

## Editor behavior and tool connections

| Behavior | Owning source / connections |
| --- | --- |
| Options, typing indentation, search, undo persistence | `lua/config/set.lua`: two-space defaults, four-space C/C++ overrides, spaces rather than tabs; persistent undo in Neovim's default `stdpath("state")/undo` |
| Explicit formatting | `lua/plugins/conform.lua`: normal/visual `gw` → filetype formatter, LSP fallback; synchronous, no format-on-save |
| Formatter selection and arguments | Same file: C/C++ → clang-format (`-style=file`, LLVM fallback); JS/TS/Markdown/JSON/HTML/CSS/YAML → Prettier; CMake → cmake-format; Rust → rustfmt; OCaml (`.ml`/`.mli`) → ocamlformat (conform passes `--enable-outside-detected-project`); dune files → `dune format-dune-file`; Lua → StyLua; Python → ruff format (80 columns from user-level `~/dotfiles/ruff/ruff.toml` unless the project configures ruff); sh/Bash → shfmt |
| Snippet loading and navigation | `lua/plugins/luasnip.lua` loads `snippets/<filetype>.lua` the first time that filetype opens; insert/select `<C-j>` / `<C-k>` jump, `<C-n>` / `<C-p>` cycle choices. C++ workflow snippets come out `gw`-formatted; CMake ones reformat themselves on leaving their last field (`format_when_done`) |
| Completion and signature help | `lua/plugins/blink.lua` → LuaSnip, LSP, path, buffer, vault frontmatter-tag (`lua/config/frontmatter_tags.lua`) sources; Blink default keymap with local overrides (`<Tab>` disabled, `<C-s>` signature toggle, `<C-k>` reserved for snippets) |
| Language intelligence and diagnostics | `lua/plugins/lsp.lua` enables lua_ls, ts_ls, eslint, rust_analyzer, clangd, pyright, neocmake, markdown_oxide, ocamllsp (from the active opam switch on `$PATH`); it also maps `.mli`/`.mll`/`.mly` to `ocamlinterface`/`ocamllex`/`menhir` so they get the right parser and LSP language id, with `ftplugin/` and `indent/ocamlinterface.lua` reusing Neovim's OCaml settings; lua_ls gets Neovim API types from `$VIMRUNTIME`; `grd` definition; clangd runs with `--log=error` (its default info logging bloats `lsp.log`) and `-j=2` (lower peak memory while indexing); servers installed externally, no Mason |
| Syntax and semantic highlighting | `lua/plugins/treesitter.lua` installs/starts parsers and, after startup, precompiles queries for the cwd project's languages (first C++ buffer otherwise stalls ~400 ms); `after/queries/cpp/highlights.scm` extends C++ captures; LSP semantic tokens also contribute; highlight styles in `colors/palette.lua` |
| Sticky scope context | `lua/plugins/treesitter_context.lua` |
| Markdown rendering | `lua/plugins/render_markdown.lua` (headings, code, completion, transparency fixes); separate from snippets and Prettier |
| Statusline | `lua/statusline.lua`, no plugin: Git branch/diff counts fetched in the background (`vim.system`) and cached per repo root; per-buffer diagnostics |
| Theme loading and reload | `lua/config/theme.lua` → shared `../theme/load.lua` → `colors/palette.lua`; see Theming below |

Formatters and language servers are external executables. Conform's Prettier
command is explicitly `~/.npm-global/bin/prettier`; other formatter/server
commands must be discoverable on `$PATH` unless configured otherwise.

## Shortcuts, commands, navigation

Keymaps live with the feature they invoke, not in one central registry.
These are entry points; read the owning file for exact modes and overrides.

| Purpose | Source / entry points |
| --- | --- |
| Generic editing | `lua/config/map.lua`: `<C-c>` escape, centered scrolling/jumps/search, visual `J`/`K` move lines, `<leader>y`/`<leader>Y` system clipboard, `<leader>d` black-hole delete, `<leader>c` interactive tmux floating shell (tmux 3.8+; editor cwd; fresh shell with native scrollback/copy mode, closes on exit; inherits themed popup styles) |
| File/text/Git/help/diagnostic search | `lua/plugins/telescope.lua`: `<leader>ff`, `<leader>fd` (directories → oil), `<leader>gr`, `<leader>gf`, `<leader>gs`, `<leader>ht`, `<leader>vd`; also owns picker settings and loads the native fzf sorter (falls back to Telescope's Lua sorter with a warning if unbuilt); `find_files` uses `fd` (`fdfind` on Debian/Ubuntu, e.g. the ROS distrobox) and honors `.gitignore` (shows dotfiles, excludes `.git` and binary extensions), no global ignore patterns |
| Directory editing | `lua/plugins/oil.lua`: `<leader>nw`, default directory explorer, hidden files shown |
| C/C++ header/source navigation | `lua/config/cpp.lua`: buffer-local `<leader>hd` switch, `<leader>hs` split/reuse window; clangd lookup → adjacent `.cpp`/`.hpp` fallback → editable creation path with file completion; missing parent directories require confirmation; new sources are empty, headers get `#pragma once` |
| Undo history | `lua/plugins/undotree.lua`: `<leader>u` toggles mbbill/undotree (tree plus diff panel; `g:undotree_*` options); persistence configured in `lua/config/set.lua` |
| Session launcher | `lua/config/sessionizer.lua` (set up from `map.lua`): `<C-f>` → `~/.local/bin/tmux-sessionizer`; in ROS distrobox panes (`$ROS_TMUX_STATE`) it instead reports normal mode so host tmux opens the picker; source in `~/dotfiles/scripts/tmux-sessionizer/` (`ROS.md`) |
| Command center | `lua/plugins/command_center.lua` → local plugin `~/personal/command-center` (owns its behavior); skipped if missing |
| Pi integration (wingman) | `lua/plugins/wingman.lua` → local plugin `~/personal/wingman` (owns its behavior, commands and docs; needs `~/personal/pi-nvim`); skipped if either is missing. Maps: `<leader>pa` question, `<leader>pc` chat, `<leader>pf` file, `<leader>pd`/`<leader>pD` diagnostic(s), `<leader>pq` quickfix, visual `<leader>pv` selection |

Obsidian vault support (`~/vault`) is the markdown-oxide language server,
configured in `lua/plugins/lsp.lua`: wiki-link/heading/block completion,
references, broken-link diagnostics, and note rename via `grn` (renames the
file and updates links to it; a local handler stops it corrupting the note's
own `[[#...]]` links). It attaches only under a directory containing
`.obsidian/`, and enables file watching explicitly so changes outside the
buffer are seen. Renaming a note's file in oil does not update links (the
server lacks `willRenameFiles`); moving between folders is safe because wiki
links resolve by name. Frontmatter `tags:` completion is the separate Blink
source above, since oxide only completes `#tag`.

## Startup and modification conventions

- `init.lua` is the authoritative startup order; every plugin loads at startup,
  no lazy loading (only snippet files load per filetype). Options and package registration precede plugin setup;
  `config.theme.apply()` precedes render-markdown and completion setup;
  `config.map` runs last. Check this order when investigating overrides.
- **Add a plugin:** register it in `lua/config/pack.lua` (`vim.pack.add`),
  create `lua/plugins/<name>.lua`, require it in `init.lua`, and commit
  `nvim-pack-lock.json` after plugin changes. Use `vim.pack` only, not
  lazy.nvim, Mason, or packer. `vim.pack` ignores a `build` key: add build
  steps to the `PackChanged` hook at the top of `pack.lua` (it runs `make` for
  telescope-fzf-native and `:TSUpdate` after nvim-treesitter updates).
- **Keymaps:** plugin maps in that plugin's file; generic maps in
  `lua/config/map.lua`. Filetype-specific maps use `FileType` autocmds and
  buffer-local mappings.
- **Commands and helpers:** register general user commands in
  `lua/config/cmds.lua`; reusable action logic in `lua/config/actions/`.
- **Snippets:** LuaSnip Lua definitions in `snippets/<filetype>.lua`, loaded
  by `lua/plugins/luasnip.lua` and offered through Blink.
- Format Lua with StyLua (defaults, tabs). Keep this map current when adding
  or moving workflows, commands, templates, or external dependencies.

## Theming

Color values live outside this directory. Read `~/dotfiles/theme/AGENTS.md`
before touching colors.

- Palettes: `~/dotfiles/theme/palettes/<name>.lua`; the active one is named in
  the gitignored `theme/current`. `theme set <name>` switches it and calls
  `require("config.theme").reload()` on running nvims.
- `colors/palette.lua` is one `groups` table:
  `HlGroup = { fg = c.<role>, bg = c.<role> }`. Use palette roles, never raw
  hex. The UI is intentionally transparent (`NormalFloat`, `FloatBorder`,
  and Telescope groups are `{}`).
- Plugins can set `default = true` highlight links after colorscheme load,
  overriding groups left empty. `reload()` restores them;
  `lua/plugins/render_markdown.lua` re-clears its groups in `vim.schedule`.
  Do the same for any plugin that fights the palette.

## Verification

- `nvim --headless +qa` (startup errors), `:checkhealth`, `stylua --check .`.
- Tests: from `nvim/`, `nvim --headless -u NONE -l tests/<name>.lua`.

| Test | Covers | Needs |
| --- | --- | --- |
| `cpp_project`, `cpp_lib` | `:Cpp`, `:CppSolo`, `:CppLib` | LuaSnip |
| `snippet_format` | C++ snippets come out `gw`-formatted | cmake-format, Prettier, shfmt |
| `cpp` | header/source navigation and creation | — |
| `statusline` | Git segment | git |
| `sessionizer` | ROS mode reporting | — |
| `theme_cpp` | C++ highlight hierarchy, with and without semantic tokens (`tests/fixtures/theme.cpp`) | C++ parser, clangd |

The installed C++ parser misparses C++23 `if consteval`/`else` bodies; no
palette change fixes that.
