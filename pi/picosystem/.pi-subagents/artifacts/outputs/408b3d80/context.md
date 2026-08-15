# Code Context

## Files Retrieved
1. `footer/index.ts` (lines 1-246) and `footer/package.json` (lines 1-20) — custom TUI footer, model/context/git/session display, and Codex weekly-usage polling.
2. `tmux-sessionizer/index.ts` (lines 1-31) — Ctrl+F launcher for a hard-coded user-local sessionizer.
3. `notifi/index.ts` (lines 1-516), `notifi/README.md` (lines 1-205), `notifi/package.json` (lines 1-38), `notifi/scripts/notifi-focus`, `notifi/tsconfig.json` — focus-aware task-completion notifications and the only explicit validation setup.
4. `pdf-reader/index.ts` (lines 1-7), `pdf-reader/src/tools.ts` (lines 1-514), `pdf-reader/src/core.ts` (lines 1-1027), `pdf-reader/src/constants.ts` (lines 1-8), `pdf-reader/src/types.ts` (lines 1-75) — 11 PDF tools, cache/index backend, limits, and shared data model.
5. `pdf-reader/skills/pdf-reading/SKILL.md` (lines 1-115), `pdf-reader/README.md` (lines 1-48), `pdf-reader/package.json` (lines 1-30) — packaged workflow skill and user-facing documentation.
6. `split-editor/index.ts` (lines 1-322), `split-editor/README.md` (lines 1-105), `split-editor/package.json` (lines 1-40) — configurable tmux split prompt editor.

## Key Code
- All runtime components are Pi TypeScript extensions exporting `default function (pi: ExtensionAPI)` and registering lifecycle hooks, tools, commands, shortcuts, or UI components.
- `footer/index.ts:145-166,171-246` reads Pi auth, polls an undocumented ChatGPT usage endpoint every 60 seconds, and renders model/reasoning, context consumption, weekly usage, cwd/branch, and session name.
- `notifi/index.ts:480-516` listens for final `agent_end`, skips headless/pending-message cases, classifies completion status, and exposes `/notifi`; earlier helpers map tmux clients through `/proc` to visible Hyprland windows and persist per-notification focus targets.
- `pdf-reader/src/tools.ts:56-514` registers scan, info, outline, reference resolution, extraction, search, index build/update, render, OCR, and image extraction. `src/core.ts` shells out through `pi.exec` and stores JSON/JSONL under `~/.cache/pi-pdf`; `skills/pdf-reading/SKILL.md:16-115` directs narrow, page-cited extraction and visual/OCR fallback.
- `split-editor/index.ts:43-156,158-192,194-220,308-321` replaces the editor component, locks input, writes a temp prompt, opens tmux, waits via `tmux wait-for`, reloads text, and merges defaults/global/project/env configuration.
- `tmux-sessionizer/index.ts:6-29` binds Ctrl+F and detached-spawns `~/.local/bin/tmux-sessionizer` only inside tmux.

## Architecture
This is a thin umbrella repository rather than a workspace. Root Git tracks two local extensions (`footer/`, `tmux-sessionizer/`), three gitlinks (`notifi`, `pdf-reader`, `split-editor`), and no root manifest, settings, README, CI, or test harness. Each package is independently loadable through Pi package metadata. `notifi` and `split-editor` specialize a Hyprland/Ghostty/tmux workflow; `footer` enhances Pi UI; `pdf-reader` adds both tools and one skill. `sub-agents/` is empty and untracked by Git, so it currently contributes nothing.

## Assessment

### Strengths
- **High value / well-factored:** PDF reader separates registration, backend, constants, and types (`pdf-reader/index.ts`, `src/tools.ts`, `src/core.ts`, `src/types.ts`) and embeds safety limits (`src/constants.ts:1-8`) plus a strong citation-oriented skill (`skills/pdf-reading/SKILL.md`).
- **Good UX resilience:** split-editor prevents concurrent prompt mutation, falls back outside tmux, bounds stderr, cleans temp files, and documents configuration precedence (`split-editor/index.ts:43-156,194-220`; `README.md`).
- **Operationally thoughtful:** notifi handles multiple tmux clients, visible workspaces, unique cached targets, stale target cleanup, and pending follow-ups (`notifi/index.ts`; `scripts/notifi-focus`; `README.md`). It alone has `typecheck`/`check` scripts (`notifi/package.json:20-31`).
- Nested repositories are clean and pinned exactly: `notifi` at `v1.0.0`, `pdf-reader` at `main` commit `4ad0582`, and `split-editor` at `v0.1.8`.

### Findings / risks
- **High — no ecosystem-level onboarding or reproducibility:** root contains no README, `.gitmodules`, package/workspace manifest, install/load configuration, CI, license, or ignore file. Git records gitlinks, but without `.gitmodules` a fresh clone cannot discover their URLs via normal `git submodule update --init` (`git ls-files`; root directory listing).
- **High — essentially no first-party tests:** repository search found no test files. PDF parsing/caching/reference logic spans ~1,027 backend lines, and notifi has substantial OS/process mapping, yet only notifi offers static/shell checks. `footer`, `pdf-reader`, and `split-editor` define no scripts (`*/package.json`). Regression risk is highest in parser and process edge cases.
- **Medium — inconsistent package maturity:** `notifi` has lockfile, TypeScript config, scripts, tags, and detailed operational docs; `pdf-reader` and `split-editor` have no dev dependencies/typecheck scripts/lockfiles; `footer` has only two files and no README; `tmux-sessionizer` lacks even a package manifest. This makes installation and validation uneven.
- **Medium — local disk bloat / hygiene:** clean nested repos occupy ~200 MB (`notifi`) and ~173 MB (`split-editor`) because local `node_modules` are present; root lacks an ignore policy. They are ignored within notifi and apparently untracked, but complicate scans and backups.
- **Medium — brittle external integrations:** footer reads private auth structure and calls undocumented `https://chatgpt.com/backend-api/wham/usage` (`footer/index.ts:102-166`); notifi assumes Linux/Hyprland/Ghostty/tmux/dunst/jq; PDF reader assumes six system binaries. Failures are generally swallowed/degraded, but compatibility changes may silently remove functionality.
- **Medium — launcher error handling:** `tmux-sessionizer/index.ts:16-26` wraps `spawn()` in `try/catch`, but Node spawn failures such as ENOENT normally arrive asynchronously on the child `error` event. No listener is installed, so a missing `~/.local/bin/tmux-sessionizer` may produce an unhandled error rather than the intended UI notification.
- **Low — dead/placeholder surface:** `sub-agents/` is empty; `tmux-sessionizer` and `footer` are unpublished-looking local fragments while three neighbors are standalone repositories. The ownership boundary and intended package set are undocumented.
- **Low — loose typing:** `pdf-reader/src/tools.ts` uses several `any` annotations for errors/update callbacks despite the otherwise explicit types, reducing compiler protection.

## Prioritized Next Steps
1. **P0:** Add root ecosystem documentation and restore declarative submodule metadata (`.gitmodules`), including component table, prerequisites, install/load instructions, and supported platform assumptions.
2. **P0:** Establish one repeatable validation command/CI job: typecheck all four TypeScript packages, `bash -n` shell helpers, and smoke-load each Pi manifest. Give `tmux-sessionizer` a manifest or explicitly document it as a raw extension.
3. **P1:** Add focused unit tests for PDF page specs/output parsing/cache freshness/reference resolution, split-editor config/shell quoting, notifi config/status/visibility helpers, and footer rate-limit/reset parsing.
4. **P1:** Fix tmux-sessionizer spawn handling by subscribing to the child `error` event and optionally checking executable access before launch.
5. **P1:** Normalize package metadata/tooling (README, license, repository, tsconfig, scripts, pinned dev tooling) while preserving independent package publishing.
6. **P2:** Decide whether `sub-agents/` is intentional; remove it or populate/document it. Add root ignore rules for runtime artifacts such as `.pi-subagents/`.
7. **P2:** Isolate/document the footer's private API dependency and expose disabled/poll-interval configuration to reduce auth/privacy and upstream-breakage risk.

## Start Here
Open the root first and create an ecosystem README/`.gitmodules`; this resolves the largest reproducibility gap and provides a place to define the intended relationship between local extensions and standalone packages. For code hardening, start with `pdf-reader/src/core.ts` because it contains the largest untested logic surface.

## Git State
- Umbrella: `master...origin/master`, commit `67835f1` (`2026-08-14`, `scrap texview`); only `?? .pi-subagents/` is untracked, with no staged changes.
- Nested repos: all clean and aligned with `origin/main`: notifi `9f6df14` (`v1.0.0`), pdf-reader `4ad0582`, split-editor `a53f13f` (`v0.1.8`).
- Root tracked files are only `footer/index.ts`, `footer/package.json`, three gitlinks, and `tmux-sessionizer/index.ts`.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Review findings above identify severity and exact paths; Git State and residualRisks provide concrete repository evidence."
    }
  ],
  "changedFiles": [],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {
      "command": "git status/log/submodule status across root and nested repositories",
      "result": "passed",
      "summary": "Root has only untracked .pi-subagents; all three nested repositories are clean and pinned."
    },
    {
      "command": "repository file/package/docs/test inventory",
      "result": "passed",
      "summary": "Mapped runtime sources, manifests, docs, skill, shell helper, empty sub-agents directory, and absence of first-party tests."
    }
  ],
  "validationOutput": [
    "No source files were modified and no tests were run for this read-only survey.",
    "Root status: master...origin/master with ?? .pi-subagents/; no staged files."
  ],
  "residualRisks": [
    "No runtime smoke tests or typechecks were executed, so findings are static-inspection based.",
    "System-specific Hyprland/tmux/Poppler/Tesseract behavior was not exercised.",
    "Large backend files were selectively inspected after architecture mapping; this is an initial, not exhaustive, code audit."
  ],
  "noStagedFiles": true,
  "diffSummary": "No repository source diff; only the required report artifact was written under the already-untracked .pi-subagents directory.",
  "reviewFindings": [
    "high: repository root - missing .gitmodules and root onboarding/validation metadata undermines reproducible cloning and setup",
    "high: repository-wide - no first-party tests found despite substantial parser/process logic",
    "medium: tmux-sessionizer/index.ts:16-26 - asynchronous spawn errors are not handled",
    "medium: footer/index.ts:102-166 - private auth shape and undocumented ChatGPT endpoint are brittle",
    "low: sub-agents/ - empty, undocumented placeholder"
  ],
  "manualNotes": "Assessment stopped after enough evidence for an initial ecosystem survey, per task scope."
}
```
