# AGENTS.md — dotfiles

Map of this repo. Find the component, read its deep doc **before editing it**
if one is listed, then follow the entry file. Use `rg` for details; this file
only says where things live and how they connect.

## Rules that apply everywhere

- **Edits are live.** `scripts/install` symlinks directories into place (table
  below), so editing here changes the running config. Configs refer to the
  same files as both `~/.config/<dir>` and `~/dotfiles/<dir>`.
- **Generated files.** Every path under the `# theme:` block in `.gitignore` is
  rendered from `theme/templates/<same path>`. Never edit an output; edit the
  template and run `theme`. Any color change goes through `theme/AGENTS.md`.
- **Submodules are separate repos:** `pi/skills` and
  `pi/picosystem/{pdf-reader,split-editor,sub-agents}`. Commit inside
  them first, then commit the pointer bump here.
- **Platforms.** Linux (Hyprland) is primary. macOS-only: `aerospace/`,
  `zsh/.zshrc.local.macbook`, Ghostty's untracked `mac.ghostty`.
- **Global agent instructions** are per harness and kept separate on purpose.
  pi's are `pi/config/global.md` → `~/.pi/agent/AGENTS.md`; they aren't about
  this repo. Claude Code's are `claude/CLAUDE.md` → `~/.claude/CLAUDE.md`,
  chosen by the runs in `evals/` (currently candidate `v2`); change them
  through a new candidate there, and don't copy pi's.
- When you add, move or rewire a component, update its row here and its row
  in the `links` table of `scripts/install`; the next pull links it on the
  other machine.

## Commits

- Commit coherent changes, not each iteration. Include their tests and docs.
- Small incidental cleanup can ride along; keep unrelated behavior changes separate.
- Follow Conventional Commits (`type(scope): summary`, scope = component dir)
  and standard git message format: imperative subject under 50 characters,
  then optionally a blank line and a short body wrapped at 72 columns.
- Add a body only for what the subject and diff can't show: the cause, a
  non-obvious reason, a measurement, or a rejected alternative. Removals,
  renames and doc fixes usually need none. Use `- ` bullets for several
  distinct changes.

## Components

| Dir | Linked as | Entry point and wiring | Read first |
| --- | --- | --- | --- |
| `nvim/` | `~/.config/nvim` | `init.lua` (load order); plugins via `vim.pack` | `nvim/AGENTS.md` |
| `theme/` | `theme` command → `scripts/theme/theme` | `build.lua` renders `templates/`; `load.lua` gives Lua configs the palette; `theme set` live-reloads apps; `theme check` lists stale outputs | `theme/AGENTS.md` |
| `pi/` | `~/.pi/agent/{settings,keybindings}.json`, `~/.pi/agent/AGENTS.md`, `~/.pi/agent/{extensions/*,prompts,themes}` | `config/settings.json` lists packages, skills, theme | `pi/AGENTS.md` |
| `zsh/` | `~/.zshrc`, `~/.zshenv`, `~/.zshrc.local` → `.zshrc.local.linux`, `~/.dircolors` → `themes/.dircolors` | `.zshrc` (host), `ros.zsh` (ROS container), both source `shared/init.zsh` | `zsh/README.md` |
| `scripts/` | `~/.local/bin/<cmd>` via `scripts/install` | One dir per tool; `install` applies the repo to the machine: its `links` table makes every link in this column, then it builds the Rust commands and runs `theme`; `install --check` only reports; `hooks/apply`, linked into `.git/hooks`, reruns it after a pull, rebase or branch switch; untracked `install.skip` lists links a machine keeps as its own files | `scripts/README.md` |
| `scripts/tmux-sessionizer/` | `~/.local/bin/tmux-sessionizer`, `~/.config/tmux-sessionizer` | `tmux-sessionizer` (bash), `presets/`, `ros-tmux` for container panes; bound to `C-f` in tmux (host Claude Code panes, via the root binding), nvim, pi, and tmux `prefix C-f` everywhere | `scripts/tmux-sessionizer/ROS.md` (ROS) |
| `scripts/notifi/` | `~/.local/bin/notifi` (Linux) | Rust crate, built by `scripts/install`; `src/main.rs` (commands), `show.rs` (`show` and its waiter), `agents.rs` (records, `next`, `go`, `dismiss`), `desktop.rs` (focus), `tmux.rs`/`hyprland.rs`/`dbus.rs` (speaks to each directly); key binds run it, so read Speed in the README before starting a process or waiting for one; `notifi show` raises a dunst notification for the agent in this tmux pane, whose Focus action (Super+Y) brings up its Hyprland window and tmux pane; closing it instead (Super+N) leaves the agent pending, counted by waybar's `custom/agents` (`notifi pending --waybar`); `notifi go` is Super+Y: that action, or with no notification up `notifi next`, which goes to the pending agents, then round the ones already seen, until the agent's own `notifi dismiss` or `notifi dismiss --focused` (Super+X) forgets it; state is one JSON record per pane in `$XDG_RUNTIME_DIR/notifi/`, no daemon; called by the hooks in `claude/settings.json` and by `pi/picosystem/notifi/`; Super+N/Super+Y/Super+X are bound in `hypr/config/keybindings.lua` | `scripts/notifi/README.md` |
| `scripts/tmux-orphans/` | `~/.local/bin/tmux-orphans` (Linux) | Zsh; finds `tmux-spawn-*.scope` cgroups with no child of a tmux server, i.e. processes left by closed panes; skips `wl-copy` (Wayland clipboard owner); `-k` sends SIGTERM, then SIGKILL, to the listed PIDs | — |
| `scripts/wall_select/` | `~/.local/bin/wall_select` (built by `scripts/install`) | Rust crate; `src/main.rs` (startup, toggle), `ui.rs` (layer shell, input), `draw.rs` (layout matching the old rofi theme); bound to Super+W in `hypr/config/keybindings.lua`; colors from a theme template | — |
| `tmux/` | `~/.config/tmux` | `tmux.conf`; prefix is `C-Space`; sources generated `colors.conf`; `prefix r` reloads; `prefix b` toggles a floating, unfocused shell-shortcuts pane (`shortcuts.sh`), kept top-right by a `window-resized` hook; new-window/split binds go through `ros-tmux` only in ROS sessions (`@ros_container`) | — |
| `hypr/` | `~/.config/hypr` | `hyprland.lua` (Lua, `hl.*` API) requires `config/*.lua`; bind targets in `scripts/`; `hypridle.conf`, `hyprlock.conf` | `hypr/AGENTS.md` |
| `waybar/` | `~/.config/waybar` | `config.jsonc`, `style.css` imports generated `color.css`; modules run `mediaplayer.py`, `scripts/waybar_cava` (linked into `~/.local/bin`) and `notifi pending --waybar` (`custom/agents`, rerun on signal 8 from notifi) | — |
| `rofi/` | `~/.config/rofi` | `config.rasi` → `themes/theme.rasi` → generated `share/colors.rasi` + `share/fonts.rasi`; opened by `hypr/scripts/toggle_rofi` | — |
| `dunst/` | `~/.config/dunst` | `dunstrc` + generated drop-in `dunstrc.d/99-palette.conf` | — |
| `ghostty/` | `~/.config/ghostty` | `config.ghostty`; includes untracked per-host `arch.ghostty`/`mac.ghostty`; `theme = palette` (generated) | — |
| `yazi/` | `~/.config/yazi` | `yazi.toml`, `keymap.toml`; `theme.toml` generated | — |
| `claude/` | `~/.claude/settings.json`, `~/.claude/statusline.sh`, `~/.claude/CLAUDE.md`, `~/.claude/themes` | Claude Code settings, status line and global instructions (`CLAUDE.md`, a copy of `evals/candidates/v2.md`); `theme: custom:palette` selects the generated `themes/palette.json`, which Claude Code reloads when it changes; `hooks` in `settings.json` call `notifi` when Claude finishes, fails or asks for input, and dismiss it when you answer; `.gitattributes` runs `settings.json` through the `claude-settings` filter in `git/config` (needs `jq`), which drops `model`/`modelSettings` and sorts keys, so `/model` and Claude's rewrites stay local | `evals/README.md` (before editing `CLAUDE.md`) |
| `evals/` | not linked | `run` (Python) runs `claude -p` on `cases/<id>` in isolated temp dirs, one arm per `candidates/<name>.md` plus `baseline`; tests candidate global instructions for Claude Code; `results/` is ignored | `evals/README.md` |
| `ruff/` | `~/.config/ruff` | `ruff.toml`: user-level fallback (80 columns), ignored by projects with their own ruff config; used by nvim's `gw` | — |
| `btop/` | `~/.config/btop/themes` | Theme only (generated); `btop.conf` is untracked | — |
| `fastfetch/` | `~/.config/fastfetch` | `config.jsonc` is fully generated; edit the template | — |
| `helium/` | loaded unpacked in Helium (`chrome://extensions`) | `theme/manifest.json` is a generated theme extension; reload it there after `theme set` | — |
| `hyprcast/` | `~/.config/hyprcast` | `overlay.toml` generated | — |
| `satty/` | `~/.config/satty` | `config.toml`; `overrides.css` generated; opened by the Edit action on `hypr/scripts/screenshot` notifications | — |
| `git/` | `~/.config/git` | `config` (global; replaces `~/.gitconfig`, which git would read too): identity, signing, zdiff3 conflicts, rerere, histogram diffs, `git mergetool` → nvimdiff (`LOCAL,MERGED,REMOTE`); `ignore` is the global gitignore; defines the `claude-settings` clean filter | — |
| `pacman/` | `~/.config/pacman` (Linux) | `makepkg.conf`: user overrides sourced after `/etc/makepkg.conf` (`MAKEFLAGS` for AUR builds) | — |
| `pz/` | `~/.config/pz` | `config.toml`: sync folder and picker keys; plain config, not themed | — |
| `sioyek/`, `fontconfig/`, `user-dirs.dirs` | `~/.config/<name>` | Plain app configs, not themed | — |
| `aerospace/` | `~/.config/aerospace` (macOS) | `aerospace.toml`; `fl.md` = FL Studio tiling notes | — |

## Verify

- Links and generated files: `scripts/install --check` exits 0.
- Theme: `theme` exits 0 and `git status` shows no generated files.
- nvim, zsh, pi, tmux-sessionizer, notifi: the checks in their docs.
- Hyprland: the checks in `hypr/AGENTS.md`.
- Ghostty: `ghostty +validate-config`. tmux: `tmux source-file ~/dotfiles/tmux/tmux.conf`.
