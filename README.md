<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/a8a58425-f930-4a42-8a3d-1212c323f971" />

## dotfiles

Personal config. Linux (Hyprland) + macOS. Symlink each subdir into `~/.config/`
(or its conventional location) to use.

## What's configured

### Linux (Hyprland)

| Dir               | Tool                                                    | Purpose                          |
| ----------------- | ------------------------------------------------------- | -------------------------------- |
| `hypr/`           | [Hyprland](https://hyprland.org/) + `hypridle`          | Wayland compositor + idle daemon |
| `waybar/`         | [Waybar](https://github.com/Alexays/Waybar)             | Status bar                       |
| `rofi/`           | [rofi-wayland](https://github.com/in0ni/rofi-wayland)   | App launcher / menus             |
| `dunst/`          | [Dunst](https://dunst-project.org/)                     | Notification daemon              |
| `ghostty/`        | [Ghostty](https://ghostty.org/)                         | Terminal emulator                |
| `cava/`           | [cava](https://github.com/karlstav/cava)                | Audio visualizer                 |
| `fontconfig/`     | fontconfig                                              | Font rendering tweaks            |
| `fastfetch/`      | [fastfetch](https://github.com/fastfetch-cli/fastfetch) | System info splash               |
| `pavucontrol.ini` | pavucontrol                                             | PulseAudio mixer UI              |
| `user-dirs.dirs`  | xdg-user-dirs                                           | XDG user directories             |

### macOS

| Dir          | Tool                                                  | Purpose                      |
| ------------ | ----------------------------------------------------- | ---------------------------- |
| `aerospace/` | [AeroSpace](https://github.com/nikitabobko/AeroSpace) | i3-style tiling WM for macOS |

### Cross-platform

| Dir                 | Tool                                                                  | Purpose                                              |
| ------------------- | --------------------------------------------------------------------- | ---------------------------------------------------- |
| `nvim/`             | [Neovim](https://neovim.io/)                                          | Editor                                               |
| `tmux/`             | [tmux](https://github.com/tmux/tmux)                                  | Terminal multiplexer                                 |
| `tmux-sessionizer/` | Custom — see [tmux-sessionizer/README.md](tmux-sessionizer/README.md) | Fuzzy project → tmux session launcher                |
| `zsh/`              | zsh                                                                   | Shell config (`.zshrc` + platform splits)            |
| `yazi/`             | [Yazi](https://github.com/sxyazi/yazi)                                | TUI file manager                                     |
| `sioyek/`           | [Sioyek](https://sioyek.info/)                                        | PDF reader (used by `tmux-sessionizer/presets/read`) |
| `claude/`           | Claude Code                                                           | CLAUDE.md + scripts                                  |

## Required packages

### Core (used by configs in this repo)

**Linux:**

- `hyprland`, `hypridle` — compositor + idle
- `waybar`
- `rofi-wayland` (or `rofi` on X11)
- `dunst`, `libnotify` (for `notify-send`)
- `ghostty`
- `cava`
- `fastfetch`
- `fontconfig`
- `pavucontrol`, `wireplumber` (provides `wpctl`)
- `playerctl` (media keys)
- `hyprpicker` (color picker)
- `grim`, `slurp`, `wl-clipboard` (screenshots — bound in
  `hypr/config/keybindings.conf`)
- `swww` or `awww` (wallpaper daemon — `awww-daemon` referenced in autostart)
- A Wayland-compatible browser referenced as `helium-browser` in autostart —
  substitute as needed

**macOS:**

- `aerospace` (via Homebrew)

**Both:**

- `zsh`
- `tmux`
- `neovim`
- `yazi`
- `sioyek`
- `fzf` (required by `tmux-sessionizer`)
- `bash` (required by `tmux-sessionizer` script)
- `git`
- `ripgrep`, `fd` (used by nvim plugins / fzf)

### Fonts

- **CaskaydiaCove Nerd Font Mono** (set in `ghostty/config.ghostty`)

Install from [Nerd Fonts](https://www.nerdfonts.com/font-downloads).

### Optional / AI tooling

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — `claude/`
  configs

## Installation

Clone, then symlink the subdirs you want into `~/.config/`. Example:

```bash
git clone https://github.com/kyleqbnguyen/dotfiles ~/dotfiles
ln -s ~/dotfiles/hypr ~/.config/hypr
ln -s ~/dotfiles/nvim ~/.config/nvim
ln -s ~/dotfiles/zsh/.zshrc ~/.zshrc
ln -s ~/dotfiles/zsh/.zshenv ~/.zshenv
# ...etc
```

No bootstrap script — pick what you want per machine.

## Credits

- `tmux-sessionizer/` derived from
  [ThePrimeagen/tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer);
  see its README for the diff.
- `hypr/scripts/wall_select` — wallpaper selector by
  [gh0stzk](https://github.com/gh0stzk), picked up via
  [Abhra00/Matuprland](https://github.com/Abhra00/Matuprland). GPL-3.0.
- waybar & rofi: I forgot who and where I got the config from from i'm sorry </3
