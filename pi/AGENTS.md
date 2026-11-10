# AGENTS.md — pi config

Config and extensions for the pi coding agent. pi's runtime home is
`~/.pi/agent/`, which holds untracked state (auth, sessions, models). Only the
links below point into this repo.

## Wiring

| Live path | Repo source | Role |
| --- | --- | --- |
| `~/.pi/agent/settings.json` | `config/settings.json` | Default model, `packages`, `skills`, `theme` |
| `~/.pi/agent/keybindings.json` | `config/keybindings.json` | TUI key overrides |
| `~/.pi/agent/themes` | `themes/` | Generated `palette.json`; pi watches it, so `theme set` reloads pi live |
| `~/.pi/agent/prompts` | `prompts/` | Prompt templates: direct `.md` children become `/` commands |
| `~/.pi/agent/extensions/immortalize` | `picosystem/immortalize/` | Loaded as a bare extension, not a package |
| `~/.pi/agent/extensions/tmux-sessionizer` | `picosystem/tmux-sessionizer/` | Bare extension: `ctrl+f` → `~/.local/bin/tmux-sessionizer` |
| `~/.pi/agent/extensions/notifi.json` | `config/notifi.json` | Settings for the notifi package |
| `~/.pi/agent/extensions/split-editor.json` | `config/split-editor.json` | Settings for the split-editor package |
| `~/.pi/agent/AGENTS.md` | `config/global.md` | User's global instructions for pi, not pi docs; Claude Code has its own in `../claude/global.md` |

pi loads code in two ways:

- **Packages** are listed in `config/settings.json` → `packages`. Each is a
  directory whose `package.json` has a `pi.extensions` (and optionally
  `pi.skills`) entry pointing at its TypeScript sources.
- **Bare extensions** are directories symlinked into `~/.pi/agent/extensions/`.

## `picosystem/` (extensions)

| Dir | Loaded as | Purpose | In-repo or submodule |
| --- | --- | --- | --- |
| `firecrawl/` | package | Web search and page fetch tools | in-repo |
| `footer/` | package | Custom TUI footer | in-repo |
| `log/` | package | Logs conversations to Markdown | in-repo |
| `woke/` | package | Inhibits sleep while pi works (systemd, hypridle) | in-repo |
| `immortalize/` | bare extension | Session snapshot / branch persistence | in-repo |
| `tmux-sessionizer/` | bare extension | `ctrl+f` sessionizer launcher | in-repo |
| `notifi/` | package | Focus-aware desktop notifications on finish | submodule |
| `pdf-reader/` | package | Read, search, render and OCR PDFs; ships its own skills | submodule |
| `split-editor/` | package | Edit the prompt in a tmux split (`nvim`) | submodule |
| `sub-agents/` | package | Background subagents in tmux windows; definitions in `agents/` | submodule |

`../skills/` (submodule) is the skills directory pi loads: `brainstorm`, `cpp`,
`handoff`, `resume-optimizer`, `teach` (interactive, learner-paced lessons), and
manual-only `gcmsg` (`/skill:gcmsg`).

## Conventions

- **Add an extension:** create `picosystem/<name>/` with `index.ts` and a
  `package.json` (`"pi": { "extensions": ["./index.ts"] }`, peer dependency on
  `@earendil-works/pi-coding-agent`), then add it to `packages` in
  `config/settings.json`. Prefer packages over bare-extension symlinks.
- **Submodules** (`notifi`, `pdf-reader`, `split-editor`, `sub-agents`,
  `../skills`) are their own repos: commit and push there, then commit the
  pointer here.
- **Theme:** `themes/palette.json` is generated from
  `theme/templates/pi/themes/palette.json`; never edit it. pi finds it through
  the `~/.pi/agent/themes` link and reloads when it changes. See
  `../theme/AGENTS.md`.
- **nvim integration** is the separate `~/personal/wingman` plugin, loaded by
  `../nvim/lua/plugins/wingman.lua`.

## Verify

- Run `/reload` in a running pi, or restart it.
- Packages with tests: `npm test` in `firecrawl/`, `woke/`, `sub-agents/`;
  `npm run check` in `immortalize/`, `notifi/`. `typecheck` also exists in `firecrawl/` and
  `sub-agents/`.
