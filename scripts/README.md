# Scripts

Standalone commands, one directory per tool.

| Directory | Commands |
| --- | --- |
| `clang/` | `cfmt`, `tidy` |
| `notifi/` | `notifi`: desktop notifications for coding agents (pi, Claude Code) with a Focus action back to their tmux pane, and a waybar count of the agents whose notification was closed unanswered; see [`notifi/README.md`](notifi/README.md) (Rust; Linux/Hyprland only) |
| `scratch/` | `scratch` (completion: `zsh/completions/_scratch`) |
| `theme/` | `theme` (see `../theme/AGENTS.md`) |
| `tmux-orphans/` | `tmux-orphans`: lists processes that outlived their tmux pane (each pane is a systemd scope); `-k` stops them; skips `wl-copy`, which must outlive the copy (Linux/systemd only) |
| `tmux-sessionizer/` | `tmux-sessionizer`, its config, presets and tests; ROS workflow in [`tmux-sessionizer/ROS.md`](tmux-sessionizer/ROS.md) |
| `wall_select/` | `wall_select`, the Super+W wallpaper picker (Rust; Linux/Hyprland only) |

## Install

`scripts/install` links every command into `~/.local/bin` (already on the Zsh
PATH), then runs `theme`. On Linux it first builds `notifi` and
`wall_select` with `cargo build --release --locked`; rerun it after changing
either crate. It's safe to rerun and refuses to replace unrelated files. The
command list lives in `install`.

tmux-sessionizer also reads its config from `~/.config/tmux-sessionizer`:

```sh
ln -sfn ~/dotfiles/scripts/tmux-sessionizer ~/.config/tmux-sessionizer
```

## Dependencies

Commands are Zsh scripts, except `tmux-sessionizer` (Bash), and `notifi`
and `wall_select` (Rust, built with cargo). They use clang-format,
clang-tidy, fzf, and `$EDITOR` (default nvim). `notifi` needs `notify-send`,
tmux, Ghostty, Hyprland and dunst at runtime. `wall_select` needs Hyprland,
`awww`, CaskaydiaCove Nerd Font and fontconfig (`fc-match`) at runtime. Its
colors come from a theme template, and `WALL_SELECT_TRACE=1` logs startup
timings.
