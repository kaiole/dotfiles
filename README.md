<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/a8a58425-f930-4a42-8a3d-1212c323f971" />

## dotfiles

Personal config for Linux (Hyprland) and macOS. Each directory is symlinked into
place; [`AGENTS.md`](AGENTS.md) lists exactly where each one goes.

## What's configured

| Dir | Tool | Platform |
| --- | --- | --- |
| `hypr/` | [Hyprland](https://hyprland.org/) + hypridle + hyprlock | Linux |
| `waybar/` | [Waybar](https://github.com/Alexays/Waybar) | Linux |
| `rofi/` | [rofi](https://github.com/davatorium/rofi) (launcher, menus) | Linux |
| `dunst/` | [Dunst](https://dunst-project.org/) (notifications) | Linux |
| `hyprcast/` | Hyprcast overlay | Linux |
| `satty/` | [Satty](https://github.com/Satty-org/Satty) (screenshot annotation) | Linux |
| `fontconfig/`, `user-dirs.dirs` | fontconfig, xdg-user-dirs | Linux |
| `aerospace/` | [AeroSpace](https://github.com/nikitabobko/AeroSpace) (tiling WM) | macOS |
| `nvim/` | [Neovim](https://neovim.io/) | both |
| `tmux/` | [tmux](https://github.com/tmux/tmux) | both |
| `zsh/` | zsh (host + ROS container) | both |
| `ghostty/` | [Ghostty](https://ghostty.org/) | both |
| `yazi/` | [Yazi](https://github.com/sxyazi/yazi) | both |
| `sioyek/` | [Sioyek](https://sioyek.info/) (PDF reader) | both |
| `fastfetch/`, `btop/` | fastfetch, btop (theme only) | both |
| `ruff/` | ruff (fallback Python format settings) | both |
| `scripts/` | Standalone commands, incl. `tmux-sessionizer` and `theme` | both |
| `theme/` | Switchable palettes for every app's colors | both |
| `claude/`, `pi/`, `agents/` | Claude Code and pi agent config, shared agent instructions | both |

## Required packages

**Linux:** `hyprland`, `hypridle`, `hyprlock`, `waybar`, `rofi`, `dunst`, `libnotify`,
`ghostty`, `cava` (waybar visualizer), `fastfetch`, `wireplumber` (`wpctl`),
`playerctl`, `hyprpicker`, `grim`, `slurp`, `wl-clipboard`, `satty`, `awww` (wallpapers),
`cargo` (builds `wall_select`), `libvips` (its rofi fallback), and a browser (autostart runs `helium-browser`).

**macOS:** `aerospace`, `ghostty`.

**Both:** `zsh`, `tmux`, `neovim`, `yazi`, `sioyek`, `git`, `fzf`, `ripgrep`,
`fd`, `jq` (Claude status line), and a C compiler + `make` (nvim builds
telescope-fzf-native).

**Font:** CaskaydiaCove Nerd Font Mono, from [Nerd Fonts](https://www.nerdfonts.com/font-downloads).

## Install

```bash
git clone https://github.com/kyleqbnguyen/dotfiles ~/dotfiles
~/dotfiles/scripts/install          # link commands into ~/.local/bin, render theme files
ln -s ~/dotfiles/nvim ~/.config/nvim  # ...and so on, per AGENTS.md
```

There's no bootstrap script; link what you want on each machine.

## Theming

Colors come from the active palette in `theme/palettes/`. `theme` renders
`theme/templates/<path>` to `<path>`; the outputs are gitignored, so run it once
after cloning (`scripts/install` does).

```bash
theme               # rebuild with the current palette
theme list          # * marks the active palette
theme set <name>    # switch, rebuild, reload running apps
```

After `theme set`:

- **Reload live:** tmux, Ghostty, Waybar, Hyprland, Dunst, running nvims.
- **Reload themselves:** pi and the Hyprcast overlay (they watch their files).
- **Next launch:** rofi, yazi, btop, fastfetch, satty, hyprlock, new shells.
- **By hand:** Helium (press **Reload** on the Palette theme in
  `chrome://extensions`).
- **Not themed:** Sioyek, Claude Code.

One-time setup for apps that need a link outside `~/.config/<dir>`:

- **btop:** `ln -s ~/dotfiles/btop/themes ~/.config/btop/themes`, then set
  `color_theme = "palette"` in `btop.conf`.
- **pi:** `ln -s ~/dotfiles/pi/themes ~/.pi/agent/themes` (see `pi/AGENTS.md`).
- **Helium:** `chrome://extensions` → Developer mode → **Load unpacked** →
  `~/dotfiles/helium/theme`.
- **Ghostty on macOS** reloads through AppleScript; allow Automation access, or
  press **Cmd+Shift+,**.

To change colors, add a palette or theme a new app, see
[`theme/AGENTS.md`](theme/AGENTS.md).

## Credits

- `scripts/tmux-sessionizer/` derived from
  [ThePrimeagen/tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer).
- `hypr/scripts/wall_select`: based on the wallpaper selector by
  [gh0stzk](https://github.com/gh0stzk), via
  [Abhra00/Matuprland](https://github.com/Abhra00/Matuprland). GPL-3.0.
- waybar & rofi: I forgot who and where I got the config from from i'm sorry </3
