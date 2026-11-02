# Scripts

Standalone commands, one directory per tool.

| Directory | Commands |
| --- | --- |
| `clang/` | `cfmt`, `tidy` |
| `scratch/` | `scratch` (completion: `zsh/completions/_scratch`) |
| `theme/` | `theme` (see `../theme/AGENTS.md`) |
| `tmux-sessionizer/` | `tmux-sessionizer`, its config, presets and tests; ROS workflow in [`tmux-sessionizer/ROS.md`](tmux-sessionizer/ROS.md) |

## Install

`scripts/install` links every command into `~/.local/bin` (already on the Zsh
PATH), then runs `theme`. It's safe to rerun and refuses to replace unrelated
files. The command list lives in `install`.

tmux-sessionizer also reads its config from `~/.config/tmux-sessionizer`:

```sh
ln -sfn ~/dotfiles/scripts/tmux-sessionizer ~/.config/tmux-sessionizer
```

## Dependencies

Commands are Zsh scripts, except `tmux-sessionizer` (Bash). They use
clang-format, clang-tidy, fzf, and `$EDITOR` (default nvim).
