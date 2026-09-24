# Scripts

Standalone commands, grouped by purpose:

| Directory | Commands |
| --- | --- |
| `clang/` | `cfmt`, `tidy` |
| `pdf/` | `rip` |
| `portal/` | `pcpy`, `pmv`, `pclear` |
| `scratch/` | `scratch` |
| `tmux-sessionizer/` | `tmux-sessionizer`, its configuration, presets, and tests |

Run `~/dotfiles/scripts/install` to link the commands into `~/.local/bin`.
The installer can be rerun and refuses to overwrite unrelated files or links.
The configured Zsh PATH already includes this directory.

The migrated commands require Zsh, even when invoked from another shell.
`tmux-sessionizer` uses Bash. Other dependencies are unchanged: clang-format,
clang-tidy, qpdf, and the editor selected by EDITOR, defaulting to nvim.

Scratch completion remains in `zsh/completions/_scratch`, registered by
`zsh/.zshrc.local.shared`. Reload `~/.zshrc` after migrating to remove old shell
functions that would otherwise override the executables.

For tmux-sessionizer configuration, also link:

```sh
mkdir -p ~/.config
ln -sfn ~/dotfiles/scripts/tmux-sessionizer ~/.config/tmux-sessionizer
```

`portal/common.zsh` is a shared helper, not an executable command.
`pclear` deletes all contents of `~/portal`, including hidden files.
