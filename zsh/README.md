# Zsh

Two entry points share one preferences file.

| File | Used by | Owns |
| --- | --- | --- |
| `.zshrc` | host (`~/.zshrc`) | Cargo PATH, secrets, `~/.zshrc.local` (→ `.zshrc.local.linux` or `.macbook`, both source `.zshrc.local.shared`), host aliases, Ctrl-F sessionizer |
| `ros.zsh` | ROS container (its `.zshrc` sources `/run/host/home/red/dotfiles/zsh/ros.zsh`) | Ubuntu PATH, clearing inherited Python variables, ROS setup, its own history and cache paths |
| `shared/init.zsh` | both | Oh My Zsh git plugin, editor, aliases, colors, prompt |

## Rules

- `shared/init.zsh` is sourced by both, so keep it portable: no PATHs,
  credentials or ROS setup. It finds theme files relative to itself, because
  `$HOME` differs in the container.
- Each environment has its own Oh My Zsh at `$HOME/.oh-my-zsh`. Auto-update is
  off in the container; run `omz update` there by hand.
- Caches always use explicit paths (`~/.cache/zsh`, `~/.cache/oh-my-zsh`), never
  `$ZDOTDIR`: for ROS panes `$ZDOTDIR` is this repo.

## Shell shortcut reference

In tmux, press **Ctrl-Space, then b** to open the shell-editing shortcut popup.
Close it with **q**, **Esc**, or **Ctrl-C**. It is a read-only reference, not a
keybinding setup; its contents live in [`tmux/shortcuts.sh`](../tmux/shortcuts.sh).

## ROS panes in tmux

`../scripts/tmux-sessionizer/ros-zsh/.zshrc` sources the container's `.zshrc`,
then adds per-pane directory and prompt reporting. Ctrl-F there is handled by
host tmux. See [the ROS workflow](../scripts/tmux-sessionizer/ROS.md).

## Reload

Open a new shell, or `source ~/.zshrc`.

## Checks

```sh
zsh -n zsh/.zshrc zsh/ros.zsh zsh/shared/init.zsh
zsh -ic 'alias gst; command -v python3'
distrobox enter ubuntu-ros --no-tty -- zsh -ic \
  'alias gst; command -v python3; print -r -- "$ROS_DISTRO"; print -r -- "$HISTFILE"'
bash scripts/tmux-sessionizer/tests/test-ros-integration.bash
```

The last check uses the existing container with a throwaway workspace and tmux
server. It doesn't run robot nodes.
