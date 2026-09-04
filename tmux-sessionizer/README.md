# tmux-sessionizer

A fuzzy directory → tmux session launcher. Originally forked from
[ThePrimeagen/tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer);
diverged significantly since.

## Requirements

`fzf`, `tmux`, `bash`.

## Usage

```bash
tmux-sessionizer [path]
```

No arg → fzf picker containing each `TS_SEARCH_PATHS` directory and its
 descendants (plus a `[TMUX] name` row per existing session). With a path →
jumps straight to / creates that session.

## Configuration

`~/.config/tmux-sessionizer/tmux-sessionizer.conf`:

```bash
TS_SEARCH_PATHS=(~/)
TS_EXTRA_SEARCH_PATHS=(~/ghq:3 ~/Git:3 ~/.config:2)   # :N = maxdepth override
TS_IGNORE_PATHS=(~/Git/junk)
TS_MAX_DEPTH=2             # descendant depth; the search path itself is depth 0
TS_FZF_POPUP_WIDTH=80    # tmux popup columns
TS_FZF_POPUP_HEIGHT=20   # tmux popup rows
TS_FZF_POPUP_Y=0         # tmux popup top row; 0 = top, C = centered
TS_FZF_BORDER=bold       # fzf border style; try bold, block, double, sharp
```

## Per-session hydration (presets)

On session creation, the script walks up from the selected dir looking for
`.tmux-sessionizer`. If found, it runs the file as bash with `TS_SESSION` and
`TS_PATH` exported, so the preset can lay out windows with explicit targets.

`presets/` holds reusable layouts (`default`, `agent`, `yazi`, `read`, `zsh`). Symlink
the one you want into a project as `.tmux-sessionizer`, or drop into `~/`
for a global default.

## Differences vs upstream

### This fork adds

- **Path-based session dedupe.** `~/personal/same` and `~/vault/same` get
  distinct sessions instead of colliding on basename. Re-entry matches by
  `#{session_path}`, not name.
- **Unique session naming.** On basename collision, walks up parents
  (`vault_same`, then `home_vault_same`, …) until unique. Sanitizes
  `.`, `:`, `/`, space → `_`.
- **`realpath` canonicalization.** Symlinked entries collapse to one session.
- **Walked `.tmux-sessionizer` lookup.** Searches from the selected dir up to
  `/`, not just the dir itself.
- **Direct-exec hydration.** Presets run via `bash` with `TS_SESSION`/
  `TS_PATH` env vars, instead of `tmux send-keys`. Avoids race conditions
  and stray keystrokes leaking into the caller pane.
- **`TS_IGNORE_PATHS`** to exclude noisy dirs from the picker.
- **Active-session filtering.** Paths already attached to a session are
  pruned from the picker (you pick *the session*, not the dir again).
- **`presets/` directory** of reusable hydration scripts.

### Upstream has, this fork doesn't

- CLI flags: `-h`, `-v`, `-s/--session`, `--vsplit`, `--hsplit`.
- `TS_SESSION_COMMANDS` for scratch windows at high indexes (69+).
- Persistent vsplit/hsplit pane toggling with a pane-id cache.
- Logging (`TS_LOG`, `TS_LOG_FILE`).
- Sourcing `./tmux-sessionizer.conf` from cwd.
- `~/.tmux-sessionizer` global hydrate fallback (this fork's walk-up
  replaces it; drop a `.tmux-sessionizer` in `~/` for the same effect).

## Credit

Original: [ThePrimeagen/tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer).
