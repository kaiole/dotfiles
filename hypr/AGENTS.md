# AGENTS.md — hypr

Hyprland (0.57+), hypridle and hyprlock. Linked as `~/.config/hypr`, so edits
are live after a reload.

## The config is Lua, not hyprlang

`hyprland.lua` is the entry point; it `require`s `config/*.lua`. There is no
`hyprland.conf`. Everything goes through the `hl` global (`hl.config`,
`hl.bind`, `hl.dsp.*`, `hl.window_rule`, `hl.device`, `hl.on`). Don't write
`bind = ...`/`windowrule = ...` syntax from older docs.

- API reference: `/usr/share/hypr/stubs/hl.meta.lua` (LuaLS stubs, wired up by
  `.luarc.json`). Upstream example: `/usr/share/hypr/hyprland.lua`.
- `hyprctl dispatch` takes a Lua expression:
  `hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })'`. Used by
  `hypridle.conf` and `scripts/toggle_swap_space`.
- `hypridle.conf` and `hyprlock.conf` are still hyprlang.

## Files

| File | Holds |
| --- | --- |
| `config/monitors.lua` | Outputs |
| `config/appearance.lua` | Gaps, borders, decoration, layout; colors from `theme/load.lua` |
| `config/autostart.lua` | `hyprland.start` hook: daemons, apps, Hyprcast plugin (dev build) |
| `config/input.lua` | Keyboard, pointer, per-device settings |
| `config/keybindings.lua` | All binds, the `fastedit` submap, media keys |
| `config/window-rules.lua` | App → workspace assignments, per-app rules |
| `scripts/` | Bind targets, called by absolute `~/.config/hypr/scripts/...` path |
| `hypridle.conf` | Lock, DPMS off, suspend timeouts |
| `hyprlock.conf` | Lock screen; sources generated `hyprlock-colors.conf` |

## Invariants

- **Locking:** `hypridle.conf`'s `lock_cmd` (via `scripts/lock`, which links
  the current wallpaper for the background) is the only thing that starts
  hyprlock, behind a `pidof` guard. Binds, timeouts and sleep call
  `loginctl lock-session`; running `hyprlock` directly skips the guard.
- **Workspace 5 is the swap space**, numbered (not named) so waybar tracks it.
  It is hard-coded in `scripts/toggle_swap_space`, the Super+Shift+O bind and
  the Obsidian rule; change all three together.
- **Colors** come from the theme (`../theme/AGENTS.md`). Never hard-code one,
  and never edit `hyprlock-colors.conf`; it is generated.
- **Hyprcast** paths point at a dev build in `~/personal/hyprcast`
  (`autostart.lua`, Super+D/V); replace them when it's installed.

## Verify

Check offline first; this doesn't touch the running session:

```sh
Hyprland --verify-config -c ~/dotfiles/hypr/hyprland.lua   # exit 1 on unknown keys/rules
lua-language-server --check ~/dotfiles/hypr --checklevel=Warning   # misspelled hl.* calls
```

Then apply: `hyprctl reload && hyprctl configerrors`. hypridle and hyprlock
have no checker: hypridle reads its config only at startup, and hyprlock is
tested by locking (`loginctl lock-session`).
