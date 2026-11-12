# Scripts

Standalone commands, one directory per tool.

| Directory | Commands |
| --- | --- |
| `clang/` | `cfmt`, `tidy` |
| `notifi/` | `notifi`: desktop notifications for coding agents (pi, Claude Code) with a Focus action back to their tmux pane, and waybar counts of the agents running, pending (notification closed unanswered) and seen; see [`notifi/README.md`](notifi/README.md) (Rust; Linux/Hyprland only) |
| `scratch/` | `scratch` (completion: `zsh/completions/_scratch`) |
| `theme/` | `theme` (see `../theme/AGENTS.md`) |
| `tmux-orphans/` | `tmux-orphans`: lists processes that outlived their tmux pane (each pane is a systemd scope); `-k` stops them; skips `wl-copy`, which must outlive the copy (Linux/systemd only) |
| `tmux-sessionizer/` | `tmux-sessionizer`, its config, presets and tests; ROS workflow in [`tmux-sessionizer/ROS.md`](tmux-sessionizer/ROS.md) |
| `wall_select/` | `wall_select`, the Super+W wallpaper picker (Rust; Linux/Hyprland only) |
| `waybar_media/` | `waybar_media`: what an MPRIS player is playing, for waybar's music module; scrolls a title wider than the module (Rust; Linux only) |

## Install

`scripts/install` applies the repo to the machine. It's safe to rerun:

1. **Links.** The `links` table in `install` has one row per link: platform,
   path in the repo, path under `~`. It covers every config directory and
   every command in `~/.local/bin` (already on the Zsh PATH). A missing link
   is made. A link that points elsewhere in this repo is repointed, so moving
   a component only needs its row changed. Anything else at a destination is
   a conflict: it is reported and left alone.
2. **Build.** On Linux, `notifi`, `wall_select` and `waybar_media` are built with
   `cargo build --release --locked`.
3. **Theme.** `theme` renders the generated files.

A failed step doesn't stop the later ones; the exit status is 1 if a step
failed, a conflict remains or a row's source is missing.

`scripts/install --check` changes nothing. It lists the links `install`
would make, the conflicts and the stale generated files, and exits 1 if there
are any.

**After a pull.** `install` links `hooks/apply` into `.git/hooks` as
`post-merge`, `post-checkout` and `post-rewrite`, so git reruns it after a
pull, a rebase or a branch switch. Run it by hand once per clone; after that
a new row or template arrives with `git pull`. The hooks do nothing in linked
worktrees, and `install` leaves them out when `core.hooksPath` is set.

**Per-machine exceptions.** To keep a file of your own where the table wants
a link, list the destination in the untracked `scripts/install.skip`, one per
line (`#` starts a comment):

```
~/.zshenv   # sources ~/.cargo/env first
```

`install` doesn't remove links: after deleting a row, remove its link by hand
on each machine.

## Dependencies

Commands are Zsh scripts, except `tmux-sessionizer` (Bash), and `notifi`,
`wall_select` and `waybar_media` (Rust, built with cargo). They use clang-format,
clang-tidy, fzf, and `$EDITOR` (default nvim). `notifi` needs `notify-send`,
tmux, Ghostty, Hyprland and dunst at runtime. `wall_select` needs Hyprland,
`awww`, CaskaydiaCove Nerd Font and fontconfig (`fc-match`) at runtime. Its
colors come from a theme template, and `WALL_SELECT_TRACE=1` logs startup
timings. `waybar_media` links libdbus (the `dbus` package), which it also
needs, with `pkg-config`, to build.
