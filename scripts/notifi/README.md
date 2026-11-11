# notifi

Desktop notifications for coding agents running in tmux, on Hyprland with
dunst and Ghostty. An agent calls `notifi show` when it finishes or needs you,
and `notifi dismiss` when you're back. pi and Claude Code both use it.

- **Super+N** closes the notification (`dunstctl close`) and leaves its agent
  **pending**: counted in waybar until you go to it, answer it or it exits.
- **Super+Y**, or a click, runs its Focus action (`dunstctl action`): the
  Hyprland window, tmux session, window and pane of that agent come to the
  front. With no notification up, Super+Y goes to the agent that has been
  pending longest (`notifi next`).

Both binds are in `hypr/config/keybindings.lua` and work for any notification.

## Commands

```sh
notifi show [--event EVENT] [--app NAME] [--force] [-v]
notifi dismiss [--app NAME]
notifi pending [--count]
notifi next
notifi status
```

`show` notifies for the agent in this tmux pane (`$TMUX`, `$TMUX_PANE`) and
returns at once. It prints nothing unless `-v`, which prints the outcome:

| Outcome | Meaning |
| --- | --- |
| `sent` | The notification is up |
| `visible` | Skipped: the agent's tmux window is on screen |
| `blocked` | Skipped: this tmux server may not notify the desktop |
| `failed: <why>` | `notify-send` failed; also on stderr, exit status 1 |

`dismiss` closes this pane's notification, or ends its pending state; it does
nothing if the pane has neither. `status` prints `allowed` or `blocked`.
`--app` is the notification's app name; outside tmux it is also the title and
the identity, and there is no Focus action.

`pending` prints one line per pending agent, `<title><TAB><event text>`, the
longest wait first. `--count` prints how many there are instead, and nothing
for none, which hides the waybar module. `next` brings the first of them to
the front as Focus would, ends its pending state and prints its title; with
none pending it prints nothing. Both run from anywhere, not only from a pane.

Exit status is 0 or 1, never 2, which Claude Code reads from a hook as "block
this".

## Events

| Event | Text | Urgency | Expires | Skipped while on screen |
| --- | --- | --- | --- | --- |
| `finished` (default) | Task Finished | normal | never | yes |
| `attention` | Needs Input | normal | never | yes |
| `error` | Task Failed | critical | never | no |
| `aborted` | Task Aborted | critical | 5 s | no |

The title is `<session>:<window index>`. The table is `EVENTS` in the script;
there is no config file.

## Behavior

- **One notification per pane.** `show` first closes whatever that pane
  already has up, even when it then skips because the window is on screen.
- **Pending.** An agent is pending when its notification was closed without
  Focus and nothing has dismissed it since. Closing it is the only way in.
  The ways out are the ones that end a notification (the agent's next `show`
  or `dismiss`: you answered, or it exited) and `next`. Three cases never
  become pending: an event that expires (`aborted`), because a timeout and
  Super+N look the same to `notify-send`; a notification closed while its
  pane is on screen, which counts as seen; and an agent outside tmux, which
  has no pane to go back to.
- **A pane that died** without a `dismiss` (the agent was killed outright) is
  dropped the next time anything asks what is pending, which waybar does
  every 30 s. So is a record from an earlier tmux server on the same socket,
  whose pane ids a new server reuses.
- **On screen** means a tmux client is showing the pane's window, and that
  client runs in a Hyprland window on a workspace some monitor is showing
  (special workspaces count). Clients are matched to Hyprland windows by
  process ancestry. `--force` skips this check.
- **Focus** is worked out when you press it, not when the notification was
  sent. It selects the pane in tmux, picks an attached client (one already on
  the pane's session first, then the most recently active), focuses its
  Hyprland window and switches it to the session. If no client lives in a
  Hyprland window, it opens a new Ghostty attached to the session.
- **Single-instance Ghostty** serves every window from one process, so a
  client can match several windows; the most recently focused one is used.
- **Hyprland restarts.** A tmux server outlives Hyprland, so the inherited
  `HYPRLAND_INSTANCE_SIGNATURE` is used only while that instance is running;
  otherwise the newest instance is.
- **Remote sessions.** A tmux server started over SSH doesn't notify (its
  global environment has `SSH_CONNECTION`, `SSH_TTY` or `SSH_CLIENT`). The
  server's environment is checked, not the agent's, which can hold stale SSH
  variables after a reattach. Override per server:

  ```sh
  tmux set-option -s @notifi-desktop on    # or off, or auto (default)
  ```

## How it works

`show` starts `notify-send --print-id --wait --action=focus=Focus`, which
lives exactly as long as the notification, and writes a record to
`$XDG_RUNTIME_DIR/notifi/<socket + pane id>.json`: the event, the time, the
pane (socket, pane id, tmux server pid) and the notification (`toast`: id,
daemon bus name, pid and start time of that `notify-send`). A detached waiter
stays behind until the notification closes. `notify-send` prints `focus` if
the action was chosen, and then the waiter runs it and removes the record.
Otherwise it removes only `toast` from the record, which is what pending is:
a record whose notification is gone. That also covers a notification lost
because dunst restarted.

`dismiss` reads the record from any later process and removes it, stops that
`notify-send` and asks the daemon to close the id. Ids restart when dunst
does, so it closes only an id the running daemon issued, and it checks the
start time so a reused pid is never signalled.

`pending` and `next` read every record, and ask tmux whether each pane is
still there. Nothing runs in between: there is no daemon, and the records
are the only state. Whenever the pending count may have changed, notifi sends
waybar `SIGRTMIN+8` (`pkill`), and `custom/agents` in `waybar/config.jsonc`
runs `notifi pending --count` again. Its `exec-if` keeps Python from starting
while there are no records at all.

## Callers

| Agent | Where | Shows | Dismisses |
| --- | --- | --- | --- |
| Claude Code | `hooks` in `claude/settings.json` | `Stop` → `finished`, `StopFailure` → `error`, `PermissionRequest` → `attention` | `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure`, `SessionEnd` |
| pi | `pi/picosystem/notifi/` | `agent_end` → `finished`, `error` or `aborted` by stop reason | `agent_start`, `session_shutdown` |

Claude Code notes, measured on v2.1.321:

- `PermissionRequest` fires as soon as a permission dialog, a question
  (`AskUserQuestion`) or a plan approval appears. Commands that auto mode
  approves by itself don't fire it.
- Answering fires `PostToolUse`, which dismisses. Declining fires nothing, so
  that notification stays until your next prompt or the end of the turn.
- `Stop` doesn't fire when you interrupt, so there is no `aborted` hook.
- Don't hook `SubagentStop`: it also fires after every `Stop`.
- The hooks are `async` so they never delay Claude, except `SessionEnd`,
  which must finish before Claude exits. Each starts with
  `command -v notifi >/dev/null || exit 0`, so hosts without notifi stay
  quiet.

pi adds `/notifi on|off|test|status`; on/off is saved in the session.

Killing an agent's tmux pane, session or server still runs its last dismiss
(`SessionEnd`, `session_shutdown`), measured on Claude Code v2.1.321 and pi
1.5.2, so nothing stays pending for a pane you closed.

## Requirements

Linux only. Python 3 (standard library), `notify-send` (libnotify), `gdbus`
(glib2), `hyprctl`, `tmux`, `ghostty`, `pkill` (procps), and a notification
daemon that supports actions (dunst). The pending count is shown by waybar.

## Tests

```sh
python3 scripts/notifi/test_notifi.py
```

They run the real command against disposable tmux servers with attached
clients, with stubs on `PATH` for `notify-send`, `hyprctl`, `gdbus`,
`ghostty` and `pkill` (needs `jq` and `script`). Nothing reaches the desktop.
The pi
adapter has its own: `npm test` in `pi/picosystem/notifi/`.
