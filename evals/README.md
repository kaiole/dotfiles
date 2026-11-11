# evals

Tests how Claude Code behaves with and without candidate global instructions
(`~/.claude/CLAUDE.md`). The live config is never touched: each trial runs
`claude -p` in a throwaway directory with its own config dir.

    ./run                                   # every case, baseline arm, 3 trials
    ./run --arms baseline,v1 --trials 5     # compare candidates/v1.md
    ./run --cases 'w*' --trials 1 --keep    # subset; keep the trial dirs

Model and effort are pinned on every run (`--model claude-fable-5-2 --effort
high` by default). Results go to `results/<timestamp>/` (not committed);
start at `index.md` there. Re-running with the same `--out` resumes: finished
trials are skipped, failed ones run again.

## Layout

- `cases/<id>/case.toml`: `prompt`, `project` (the directory name the model
  sees), `good` (one line: what a good response does), optional `check` and
  `hidden_check` shell commands, and the answer key in comments.
- `cases/<id>/fixture/`: copied into the trial and committed as one commit.
- `cases/<id>/hidden/`: copied to `.hidden/` only after the model has
  finished, for checks it must not see.
- `candidates/<name>.md`: an arm. The file becomes the trial's `CLAUDE.md`.
  `baseline` is the arm with no file.

## What a trial is

1. A temp root (`$EVAL_TMP` or the system temp dir) with `.claude/` as
   `CLAUDE_CONFIG_DIR` and the fixture as a fresh git repo beside it. No path
   says "eval".
2. `.claude/settings.json` holds only `attribution` from the live settings, a
   sandbox block and an allow rule for Bash, so shell commands run without
   prompts but can't write outside the project and the trial's own temp dir
   (`CLAUDE_CODE_TMPDIR`). No plugins, hooks, memory or status line.
3. Auth: the OAuth access token is read from `~/.claude/.credentials.json`
   (or `$CLAUDE_CODE_OAUTH_TOKEN`) and passed in the child's environment. The
   child can't refresh it; if it has expired, open `claude` once or export a
   token from `claude setup-token`.
4. After the run: `git status`, the diff, then `check` and `hidden_check`.

Each trial writes `transcript.md` (prompt, every message and tool call, diff,
check output), `raw.jsonl`, `session.jsonl`, `diff.patch` and `meta.json`.
A trial is valid only if the served model matches the pin and the session
shows global instructions loaded exactly when the arm has them; anything else
is written as `invalid.json` and re-run on resume.

Checks are observations, not scores. Nothing here grades yet.
