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
| `scripts/tmux-sessionizer/` | Custom | Fuzzy project → tmux session launcher |
| `zsh/`              | zsh                                                                   | Shell config (`.zshrc` + platform splits)            |
| `yazi/`             | [Yazi](https://github.com/sxyazi/yazi)                                | TUI file manager                                     |
| `sioyek/`           | [Sioyek](https://sioyek.info/)                                        | PDF reader (used by `scripts/tmux-sessionizer/presets/read`) |
| `claude/`           | Claude Code                                                           | `settings.json`, status line script                  |
| `theme/`            | Custom (see [Theming](#theming))                                      | Switchable palettes for every app's colors           |
| `btop/`             | [btop](https://github.com/aristocratos/btop)                          | Theme only (`themes/` → `~/.config/btop/themes`)     |

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
  `hypr/config/keybindings.lua`)
- `swww` or `awww` (wallpaper daemon — `awww-daemon` referenced in autostart)
- A Wayland-compatible browser referenced as `helium-browser` in autostart —
  substitute as needed

**macOS:**

- `aerospace` (via Homebrew)
- `ghostty` (shared terminal config and palette)

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

Standalone commands live under `scripts/`, grouped by tool. Keep their executable
symlinks in `~/.local/bin`, which is already on the configured Zsh PATH.

To install tmux-sessionizer, or update its links after moving from the old layout:

```bash
mkdir -p ~/.local/bin ~/.config
ln -sfn ~/dotfiles/scripts/tmux-sessionizer/tmux-sessionizer ~/.local/bin/tmux-sessionizer
ln -sfn ~/dotfiles/scripts/tmux-sessionizer ~/.config/tmux-sessionizer
```

The configuration link includes its presets. Existing tmux, Neovim, Ghostty, and
shell bindings continue to use the same installed command path.

No bootstrap script — pick what you want per machine.

## Theming

Colors come from the active palette in `theme/palettes/` (default: `lackluster-red`).
`theme/build.lua` renders every file under `theme/templates/<path>` to `<path>`
in the repo. The rendered files are gitignored, so run `theme` once after cloning
(`scripts/install` does this).

```bash
theme                 # rebuild with the current palette
theme list            # * marks the active palette
theme set <name>      # switch, rebuild, reload tmux / ghostty / running nvims
```

- **Change a color:** edit the active palette in `theme/palettes/`, then run `theme`.
- **New palette:** copy that file to `theme/palettes/<name>.lua`. Every key is required.
- **Theme another app:** move its config to `theme/templates/<repo path>`, replace
  hex values with `{{key}}` (`#rrggbb`), `{{key:hex}}` (`rrggbb`) or `{{key:rgb}}`
  (`r;g;b`), and add the output path to `.gitignore`.
- **nvim** uses this repo's own colorscheme, `nvim/colors/palette.lua`, which
  reads the palette directly (no template, no colorscheme plugin).
### macOS setup

Run `./scripts/install` from the repo root to install `theme` and render the
shared palettes. Existing `~/.config/{ghostty,tmux,nvim,yazi,fastfetch}` links
continue to work. Zsh loads its generated prompt/fzf colors from the repo.
GNU dircolors is optional (`gdircolors` from Homebrew coreutils is supported);
macOS ls otherwise follows the terminal's ANSI palette.

For btop, keep its writable config and link only the generated theme:

```bash
mkdir -p ~/.config/btop/themes
ln -s ~/dotfiles/btop/themes/palette.theme ~/.config/btop/themes/palette.theme
# Set color_theme = "palette" in ~/.config/btop/btop.conf.
```

For Pi, link `~/dotfiles/pi/themes` to `~/.pi/agent/themes` and select `palette`
in `/settings`, without replacing your other Pi settings. The active theme
file hot-reloads on subsequent palette changes.

`theme set <name>` reloads tmux, running Neovims, and Ghostty. On macOS, Ghostty
uses AppleScript; allow Automation access if prompted. If unavailable, press
**Cmd+Shift+,** in Ghostty to reload manually. Open a new shell for prompt/fzf
changes; yazi, btop and fastfetch pick up colors on their next launch.

- **Not themed yet:** waybar, rofi, dunst and the Hyprland border.

## Credits

- `scripts/tmux-sessionizer/` derived from
  [ThePrimeagen/tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer).
- `hypr/scripts/wall_select` — wallpaper selector by
  [gh0stzk](https://github.com/gh0stzk), picked up via
  [Abhra00/Matuprland](https://github.com/Abhra00/Matuprland). GPL-3.0.
- waybar & rofi: I forgot who and where I got the config from from i'm sorry </3
