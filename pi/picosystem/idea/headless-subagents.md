# Headless subagents (`delegate`)

Replaces `sub-agents/`. Workers run headless and return their answer as the
tool result, the way Claude Code's Agent tool does. Nobody watches or steers
them.

## Goals

- No cap on the number of subagents. A queue limits how many run at once.
- Depth 1: a worker can never spawn workers.
- Synchronous by default. `background: true` when the parent has other work.
- Small: about 300 lines of source, plus tests.

## Not in v1

tmux windows, open/pin/keep/release, worker footer, steering a running worker,
`ask_question` and its mailbox, heartbeat and stall detection, groups,
worktrees and integration, per-profile cost and time limits, surviving the
parent, cleanup of old task directories.

Worktrees come back only after two parallel workers clobber a file. Then do it
Claude Code's way: an opt-in `isolation: "worktree"` that removes the worktree
if nothing changed and otherwise returns its path and branch. No merging in the
extension.

## Tools

```ts
subagent({ agent, task, name?, cwd?, model?, background? })
subagent_continue({ name, message, background? })
subagent_cancel({ name })
```

- `subagent`: start a worker from profile `agent`.
  - Synchronous: the tool call waits for the worker and returns its final
    answer.
  - Background: returns the task name at once. The result is steered in
    (`pi.sendMessage(..., { deliverAs: "steer", triggerTurn: true })`): pi
    adds it after the parent's current tool calls, or starts a turn when the
    parent is idle. Not a follow-up: that waits for the parent's whole run to
    end, so a busy parent never sees the result, asks the worker again, and
    then gets every result as its own turn.
- `subagent_continue`: resume a finished worker's session with a new message.
  Same profile, tools and model as its first run. This replaces
  `ask_question`: a blocked worker says what it needs in its answer, and the
  parent answers by continuing it.
- `subagent_cancel`: kill a background or queued worker. Esc in the parent
  already cancels synchronous ones.
- Fan-out: several `subagent` calls in one turn run in parallel (pi's default
  tool execution), and their results come back together. A codemode script can
  also start many with `Promise.all`. **Never mark these tools
  `executionMode: "sequential"`:** that makes the whole turn sequential.
- Names default to `<agent>-<n>`, unique within the parent session.

Human command: `/subagents` lists running, queued and recent tasks with their
session paths. `/subagents cancel <name>` cancels one. Open a finished worker by
hand with `pi --session-dir <dir> --session <id>`.

## Profiles

Same discovery as now: bundled `agents/`, then `~/.pi/agent/agents/`, then the
nearest trusted project `.pi/agents/`. A later file with the same name wins.

Frontmatter: `name`, `description`, `tools`, and optionally `extensions`,
`skills` (preloaded into the prompt), `model`, `thinking`. The body is
appended to the system prompt.

**Any other key is an error for that profile.** An old `isolation: worktree`
must not be silently ignored and leave an editing worker in the shared
checkout. A broken override removes the profile rather than falling back to the
bundled one, as now.

Port from `sub-agents`: `parseAgent`/`discoverAgents`/`resolveLoadout` from
`src/agents.ts` (trimmed), `src/skills.ts` as is, and `piInvocation` from
`src/tmux.ts`.

## Launching a worker

```
pi --mode json --no-extensions -e <ext providing each tool>... \
   --no-prompt-templates --tools <profile tools> \
   --thinking <t> [--model <m>] \
   --session-dir <task>/session --session-id <uuid> \
   --append-system-prompt <task>/prompt.md \
   --approve | --no-approve \
   -- <task text>
```

- `--no-extensions` also turns off built-in MCP. `-e` loads only the extensions
  that provide the profile's tools (e.g. firecrawl for `web_search`). So no
  notifi, woke, log or footer in workers, and never this extension.
- `--tools` is an allowlist, so codemode is off unless the profile lists it.
- Skills and context files (`AGENTS.md`) are still discovered, as in a normal
  session.
- `--approve` only when the worker's cwd is the parent's and the parent's
  project is trusted.
- Spawn with `detached: true`, so the worker leads its own process group, and
  `stdio: ["ignore", "pipe", "pipe"]`. Env: the parent's, plus
  `PI_SUBAGENT=1`.
- `--session-id` is chosen up front, so continuing a worker needs no parsing
  of its output.

Worker prompt (`prompt.md`): profile body, preloaded skills, then:

> You are a subagent. No human reads this session. Your final message is
> returned to the parent agent as your result. If you are blocked, state
> exactly what you need and stop. You share the checkout with the parent and
> possibly other workers: edit only files your task concerns, and do not
> commit, stash, checkout, reset or rebase.

## Depth guard

1. `resolveLoadout` refuses any profile tool whose name starts with
   `subagent`.
2. Workers never load this extension (`--no-extensions`).
3. With `PI_SUBAGENT=1` set, the extension registers nothing, in case a
   profile's `extensions` loads it anyway.

A worker with `bash` can still run `pi -p` itself. Accepted.

## Queue

- `subagents.concurrency` in settings, default 8. Calls past the limit wait,
  FIFO. A spawn is never refused.
- A queued synchronous call shows "queued (n ahead)" through `onUpdate`.
- Status line: `agents 3 running · 5 queued` while any run.

## Reading the worker's output

Read stdout as JSONL events (`docs/json.md`).

- **Progress:** on each `tool_execution_start`, send `onUpdate` with the
  tool name and a short summary of its arguments, the elapsed time and the
  tokens.
- **Result:** the text of the last assistant `message_end`.
- **Success:** exit code 0, **and** that message's `stopReason` is not
  `error`, `aborted` or `length`, **and** `agent_settled.aborted` is
  false. In JSON mode a failed response does *not* give a non-zero exit code
  (`docs/cli-integration.md`), so the events decide.
- **Failure:** an error result naming the cause (exit code, stop reason or
  inactivity) with the last 40 lines of stderr. Never empty text that looks
  like success.
- **Inactivity:** no event for `subagents.inactivityTimeout` (default 10 min)
  kills the worker as failed. Long jobs are fine; silence isn't. pi already
  retries 429/529 itself (`auto_retry_*`).
- **Size:** cap the returned text at 2000 lines or 50 KB, like pi's bash
  output. Always save the full text to `<task>/result.md` and give its path
  when cut.
- Include the worker's token use and cost in the result details.

## Cancelling and parent exit

- Kill = SIGTERM to the process group (`process.kill(-pid)`), then SIGKILL
  after 5 s. That takes the worker's `bash` children too.
- Synchronous worker: on the tool's `AbortSignal` (Esc).
- Background or queued worker: `subagent_cancel`. A queued one is just
  removed.
- Parent exit: kill every worker on `session_shutdown` and on process
  `exit`. Background work dies with the parent. If the parent is killed
  outright, workers can be orphaned; `tmux-orphans` covers that.
- A background result that finishes after its parent session changed is
  dropped. The session file still has it.

## Task directory

`~/.pi/agent/subagents/<parent-session-id>/<name>/`:

- `meta.json`: profile, resolved loadout, cwd, session id, status. Lets
  `subagent_continue` work after a parent `/reload` or resume.
- `prompt.md`, `session/`, `result.md`, `stderr.log`.

Kept out of the project's `/resume` list by `--session-dir`. No automatic
deletion in v1.

## Auth

No work needed. pi takes a cross-process lock for every `auth.json` write, and
refreshes OAuth inside `credentials.modify()`, re-checking the token's expiry
on the fresh copy. Parallel workers do one refresh between them.

## Tests

Use the mock provider from `sub-agents/test/fixtures/mock-provider.ts`.

- Success, an error stop reason with exit code 0, a non-zero exit, and
  inactivity each give the right result.
- Queue: N+3 calls run at most N at once and start in order.
- Abort kills the whole process group (a worker running `sleep` in `bash`
  is gone).
- A busy parent sees a background result between its tool calls. Cancel
  removes a queued task.
- `subagent_continue` reuses the session and loadout, also after a reload.
- Truncation saves the full result and returns its path.
- Depth guard: a `subagent*` tool in a profile is refused, and nothing
  registers when `PI_SUBAGENT=1` is set.
- A profile with an unknown key (`isolation`) is rejected.

## Rollout

- In-repo package at `pi/picosystem/delegate/`, not a submodule.
- It uses the same tool names as `sub-agents`, so only one can be loaded.
  Swap it for `sub-agents` in `packages` in `config/settings.json`. To go
  back, swap again.
- Update the extensions table in `pi/AGENTS.md`.
- Once you stop missing the old one, remove the `sub-agents` submodule and its
  `subagents.maxConcurrent` setting.

## Check while building

- Can a tool result carry `usage`, so worker tokens count in the parent's
  `/session` totals? If not, report them only in the result.
- Does headless pi with `--no-approve` in an untrusted project run or exit?
  Make sure it never waits on a prompt.
