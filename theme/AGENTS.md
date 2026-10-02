# Theming

Every themed app in this repo gets its colors from the active palette. Apps never
hardcode hex values: their color config is a template rendered by `theme/build.lua`.
Switching palettes (`theme set <name>`) re-colors everything at once.

Nothing here assumes a particular look. A palette can be dark, light, monochrome or
colorful. Keys name **roles** (`bg`, `fg`, `border`, `error`), and templates choose
keys by role, so any palette works in any app.

The two common jobs are **applying a palette the user found** and **theming a new
app**. Both are below.

## How it works

- `theme/palettes/<name>.lua` is a flat table of `key = "#rrggbb"`. Every palette must define exactly the keys of the default palette, `lackluster-red.lua`; the build rejects missing keys.
- `theme/templates/<path>` is rendered to `<repo root>/<path>`. The template path mirrors the output path, so `templates/tmux/colors.conf` becomes `tmux/colors.conf`.
- Placeholders:

  | Placeholder | Output | Use |
  |---|---|---|
  | `{{key}}` | `#rrggbb` | most configs |
  | `{{key:hex}}` | `rrggbb` | configs that want no `#`, or need alpha: `rgba({{bg:hex}}ff)` |
  | `{{key:rgb}}` | `r;g;b` | ANSI truecolor (`38;2;{{fg:rgb}}`) |

- An unknown key, an unknown format or a missing palette key makes the build exit 1 and write nothing.
- Rendered outputs are **gitignored**. Never edit an output; edit its template.
- Commands:

  | Command | Does |
  |---|---|
  | `theme` | rebuild with the current palette |
  | `theme list` | list palettes (`*` = active) |
  | `theme set <name>` | switch, rebuild, live-reload running apps (`reload()` in `scripts/theme/theme`) |

## Palette keys

The neutrals are a ramp from the background toward the foreground. That works the
same for light palettes: there, `bg` is the lightest color and `fg_max` the darkest.

| Key | Role |
|---|---|
| `bg` | Base background (terminal, windows) |
| `bg_alt` | Slightly off the base: darkest panels; text on colored chips/badges |
| `surface` | Raised surfaces: bars, status lines, selected-row background |
| `border` | Borders, separators, inactive outlines |
| `fg_faint` | Faintest text: comments, hints, placeholders |
| `fg_dim` | Dim text: labels, inactive tabs |
| `fg_muted` | Secondary text |
| `fg` | Main text |
| `fg_strong` | Emphasized text, active borders |
| `fg_bright` | Stronger emphasis |
| `fg_max` | Strongest foreground: titles, active item, cursor |
| `accent` | Primary highlight: search matches, pointers, mode indicators |
| `accent_muted` | Subdued highlight: search items, links, special tokens |
| `accent_alt` | Tertiary highlight |
| `error` | Errors, deletions, cut, dangerous actions |
| `success` | Success, additions, executables |
| `warning` | Warnings, modified |
| `panel`, `popup`, `statusbar` | Extra background shades for apps with layered UIs (pi, Telescope) |
| `error_bg` | Background tint behind error blocks |
| `whitespace` | Visible whitespace characters |
| `syntax_*` | Code highlighting, shared by nvim and pi. One key per token kind: `comment`, `keyword`, `return`, `exception`, `function` (definitions), `call`, `param`, `variable`, `member`, `constant`, `constant_builtin`, `string`, `escape`, `type`, `type_def`, `type_builtin`, `builtin`, `special`, `tag`, `punctuation` (see the palette file's comments) |
| `ansi0`–`ansi15` | Terminal 16 colors (0–7 normal: black, red, green, yellow, blue, magenta, cyan, white; 8–15 bright) |

A palette may give several keys the same value. `lackluster-red` sets `accent` and `error` to the same red and `accent_muted` to a gray, for example.

## Applying a palette the user found

1. Get the scheme's colors from the user, or from its official source: a ghostty/kitty/alacritty theme, a base16 YAML, or a nvim colorscheme's palette file.
2. Copy `palettes/lackluster-red.lua` to `palettes/<name>.lua` and fill in **every** key by role:
   - **Neutrals:** sort the scheme's background, surface, border and foreground shades from the background outward into `bg` … `fg_max`. If the scheme has fewer shades than the ramp, interpolate between neighbors or repeat values.
   - **Accents:** the scheme's main highlight goes to `accent`; its red to `error`; its green to `success`; its yellow/orange to `warning`. Use other hues for `accent_muted` and `accent_alt`.
   - **Extras:** derive `panel`, `popup`, `statusbar`, `error_bg` and `whitespace` from shades near `bg`.
   - **Syntax:** take the `syntax_*` colors from the scheme's own nvim colorscheme where possible (its string, keyword, function, type, … colors). A monochrome palette can set them all to neutrals.
   - **Terminal colors:** use the scheme's 16 terminal colors for `ansi0`–`ansi15`.
3. Run `theme set <name>`, and report which apps reloaded live and which pick it up on next launch.

## Theming a new app

1. **Find where the app reads colors**, and pick the least invasive option:
   - **The app can include another file** (tmux `source-file`, ghostty `theme =`, CSS `@import`, rasi `@import`, a `*.d/` drop-in dir, Lua `dofile`): template only a small colors file and include it from the hand-written config. Examples: `templates/tmux/colors.conf`, `templates/ghostty/themes/palette`.
   - **The app has a separate theme file** (yazi `theme.toml`, btop `themes/*.theme`, pi themes JSON): template that whole file.
   - **Colors are mixed into the main config and there's no include** (fastfetch `config.jsonc`, `.dircolors`): move the whole config into `templates/` and stop tracking the original with `git rm --cached`.
   - **The app rewrites its own config** (btop): template only a theme file, and select it by hand in the untracked config.
   - **The app can just use the terminal's 16 colors** (bat `--theme=ansi`, any CLI using plain ANSI codes): don't write a template; it already follows `ansi0`–`ansi15`.
   - **Lua configs** (Hyprland) can load the palette directly instead of using a template: `dofile("<dotfiles>/theme/load.lua").palette()`. See `nvim/lua/config/theme.lua`.
   - **An nvim plugin:** see the nvim section below.
2. **Write the template** at `theme/templates/<repo path>`. If the format allows comments, make line 1:
   `# GENERATED by theme/build.lua from theme/templates/<path> -- edit that instead.`
   (Use `//` for jsonc. JSON allows no comments, so skip the header there.)
   Replace every hex value with the key whose **role** matches. Don't pick a key because of how its value happens to look in the current palette; the next palette may look completely different. Afterwards there should be no raw hex left:
   `grep -rnE '#[0-9a-fA-F]{6}\b' theme/templates` prints nothing.
3. **Add the output path to `.gitignore`** under the `# theme:` block. The build warns about any output that isn't ignored.
4. **Point the app at the output.** Configs in this repo are symlinked from `~/.config`, so the output usually sits right where the app looks. When converting an existing file, render it and `diff` it against the original: the only difference should be the header line.
5. **Live reload (optional).** If the app can reload without a restart (a signal, a CLI command or a socket), add a best-effort line to `reload()` in `scripts/theme/theme`. Skip it silently when the app isn't running, and update the "next launch:" message to match.
6. **Verify:**
   - `theme` exits 0 and has no `.gitignore` warning.
   - The app accepts the output (use its validator, e.g. `ghostty +validate-config`, or parse the TOML/JSON).
   - Copy the active palette to `palettes/test.lua`, set `accent` and `error` to `#00ff00`, and run `theme set test`; the app's highlights should change. Then switch back with `theme set <previous>` and delete `test.lua`.
   - `git status` shows no generated files.
7. **Docs:** add the app to the README table, and remove it from the "Not themed yet" line under `## Theming` if it's there.

## nvim

nvim uses this repo's own colorscheme, `nvim/colors/palette.lua` (`:colorscheme palette`), with no colorscheme plugin.
- `nvim/lua/config/theme.lua` loads the active palette; `apply()` sets the colorscheme and `reload()` re-applies it live (`theme set` calls it on every running nvim).
- `palette.lua` is one table, `groups`, of `GroupName = { fg = c.<key>, bg = c.<key>, bold = true, link = "Other" }`, in sections: editor UI, diagnostics, spelling, diff, treesitter captures, LSP semantic tokens, filetype syntax, then one `-- Plugin: <name>` section per plugin. Use only `c.<key>` values, never hex.
- Leaving out `fg` or `bg` means none, so the terminal background shows through.
- **Styling a new plugin:** list its groups with `:filter /^<Prefix>/ highlight` (plugins usually set `default = true` links to core groups, which already follow the palette). Only add a `-- Plugin: <name>` section for groups that need to differ from those defaults.
- **A group set to `{}`** gets overridden by the plugin's default link, which the plugin sets after the colorscheme loads. To force it empty, clear it again after the plugin's setup (see the Gotchas).

## Adding a key

Only add a key when an app has a role that no existing key covers. Add it, with a role comment, to **every** file in `theme/palettes/` and to the table above; the build flags any palette you miss.

## Gotchas

- In templates that already use braces, `%F{{{fg_dim}}}` works: the inner `{{fg_dim}}` is what matches.
- nvim: plugins set `default = true` highlight links after init, and those links override groups the colorscheme left empty. If clearing a group doesn't take effect, re-clear it in `vim.schedule` after the plugin's setup (see `nvim/lua/plugins/render_markdown.lua`).
- Not themed yet (they keep their own hardcoded colors and won't follow a switch): waybar, rofi, dunst, the Hyprland border.
