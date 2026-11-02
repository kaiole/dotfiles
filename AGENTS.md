# AGENTS.md — dotfiles

Map of this repo. Find the component, read its deep doc **before editing it**
if one is listed, then follow the entry file. Use `rg` for details; this file
only says where things live and how they connect.

## Rules that apply everywhere

- **Edits are live.** Directories are symlinked into place (table below), so
  editing here changes the running config. Configs refer to the same files as
  both `~/.config/<dir>` and `~/dotfiles/<dir>`.
- **Generated files.** Every path under the `# theme:` block in `.gitignore` is
  rendered from `theme/templates/<same path>`. Never edit an output; edit the
  template and run `theme`. Any color change goes through `theme/AGENTS.md`.
- **Submodules are separate repos:** `pi/skills` and
  `pi/picosystem/{notifi,pdf-reader,split-editor,sub-agents}`. Commit inside
  them first, then commit the pointer bump here.
- **Platforms.** Linux (Hyprland) is primary. macOS-only: `aerospace/`,
  `zsh/.zshrc.local.macbook`, Ghostty's untracked `mac.ghostty`.
- **Global agent instructions** are `agents/global.md`, linked as
  `~/.claude/CLAUDE.md` and `~/.pi/agent/AGENTS.md`. They aren't about this repo.
- When you add, move or rewire a component, update its row here.

## Commits

- Commit coherent changes, not each iteration. Include their tests and docs.
- Small incidental cleanup can ride along; keep unrelated behavior changes separate.
- Follow Conventional Commits (`type(scope): summary`, scope = component dir)
  and standard git message format: imperative subject under 50 characters, a
  blank line, then a short body wrapped at 72 columns saying what changed and
  why. Skip the body when the subject says it all; use `- ` bullets for
  several distinct changes.

## Components

| Dir | Linked as | Entry point and wiring | Read first |
| --- | --- | --- | --- |
| `nvim/` | `~/.config/nvim` | `init.lua` (load order); plugins via `vim.pack` | `nvim/AGENTS.md` |
| `theme/` | `theme` command → `scripts/theme/theme` | `build.lua` renders `templates/`; `load.lua` gives Lua configs the palette; `theme set` live-reloads apps | `theme/AGENTS.md` |
| `pi/` | `~/.pi/agent/{settings,keybindings}.json`, `~/.pi/agent/{extensions/*,prompts,themes}` | `config/settings.json` lists packages, skills, theme | `pi/AGENTS.md` |
| `zsh/` | `~/.zshrc`, `~/.zshenv`, `~/.zshrc.local` → `.zshrc.local.linux`, `~/.dircolors` → `themes/.dircolors` | `.zshrc` (host), `ros.zsh` (ROS container), both source `shared/init.zsh` | `zsh/README.md` |
| `scripts/` | `~/.local/bin/<cmd>` via `scripts/install` | One dir per tool; `install` holds the command list | `scripts/README.md` |
| `scripts/tmux-sessionizer/` | `~/.local/bin/tmux-sessionizer`, `~/.config/tmux-sessionizer` | `tmux-sessionizer` (bash), `presets/`, `ros-tmux` for container panes; bound to `C-f` in tmux, nvim, pi, and tmux `prefix C-f` everywhere | `scripts/tmux-sessionizer/ROS.md` (ROS) |
| `scripts/wall_select/` | `~/.local/bin/wall_select` (built by `scripts/install`) | Rust crate; `src/main.rs` (startup, toggle), `ui.rs` (layer shell, input), `draw.rs` (layout matching the old rofi theme); bound to Super+W in `hypr/config/keybindings.lua`, which falls back to `hypr/scripts/wall_select` (rofi) if the binary is missing; colors from a theme template | — |
| `tmux/` | `~/.config/tmux` | `tmux.conf`; prefix is `C-Space`; sources generated `colors.conf`; `prefix r` reloads; `prefix b` opens the shell-shortcuts popup (`shortcuts.sh`); new-window/split binds go through `ros-tmux` only in ROS sessions (`@ros_container`) | — |
| `hypr/` | `~/.config/hypr` | `hyprland.lua` requires `config/*.lua`; `hyprland.conf` is a stub, ignore it. Colors: `config/aesthetic.lua` loads `theme/load.lua`. Bind targets in `hypr/scripts/` (`screenshot <region or full> <copy or save>`) | — |
| `waybar/` | `~/.config/waybar` | `config.jsonc`, `style.css` imports generated `color.css`; modules run `mediaplayer.py` and `scripts/waybar_cava` (linked by hand into `~/.local/bin`) | — |
| `rofi/` | `~/.config/rofi` | `config.rasi` → `themes/theme.rasi` → generated `share/colors.rasi` + `share/fonts.rasi`; opened by `hypr/scripts/toggle_rofi` | — |
| `dunst/` | `~/.config/dunst` | `dunstrc` + generated drop-in `dunstrc.d/99-palette.conf` | — |
| `ghostty/` | `~/.config/ghostty` | `config.ghostty`; includes untracked per-host `arch.ghostty`/`mac.ghostty`; `theme = palette` (generated) | — |
| `yazi/` | `~/.config/yazi` | `yazi.toml`, `keymap.toml`; `theme.toml` generated | — |
| `claude/` | `~/.claude/settings.json`, `~/.claude/statusline.sh` | Claude Code settings and status line | — |
| `ruff/` | `~/.config/ruff` | `ruff.toml`: user-level fallback (80 columns), ignored by projects with their own ruff config; used by nvim's `gw` | — |
| `btop/` | `~/.config/btop/themes` | Theme only (generated); `btop.conf` is untracked | — |
| `fastfetch/` | `~/.config/fastfetch` | `config.jsonc` is fully generated; edit the template | — |
| `helium/` | loaded unpacked in Helium (`chrome://extensions`) | `theme/manifest.json` is a generated theme extension; reload it there after `theme set` | — |
| `hyprcast/` | `~/.config/hyprcast` | `overlay.toml` generated; `demo-*.toml` are standalone variants | — |
| `satty/` | `~/.config/satty` | `config.toml`; `overrides.css` generated; opened by the Edit action on `hypr/scripts/screenshot` notifications | — |
| `sioyek/`, `fontconfig/`, `user-dirs.dirs` | `~/.config/<name>` | Plain app configs, not themed | — |
| `aerospace/` | `~/.config/aerospace` (macOS) | `aerospace.toml`; `fl.md` = FL Studio tiling notes | — |

## Verify

- Theme: `theme` exits 0 and `git status` shows no generated files.
- nvim, zsh, pi, tmux-sessionizer: the checks in their docs.
- Hyprland: `hyprctl reload`, then `hyprctl configerrors`.
- Ghostty: `ghostty +validate-config`. tmux: `tmux source-file ~/dotfiles/tmux/tmux.conf`.
