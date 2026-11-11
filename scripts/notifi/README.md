# notifi

Desktop notifications for coding agents running in tmux, on Hyprland with
dunst and Ghostty. An agent calls `notifi show` when it finishes or needs you,
and `notifi dismiss` when you're back. pi and Claude Code both use it.

- **Super+N** closes the notification (`dunstctl close`) and leaves its agent
  **pending**: counted in waybar until you go to it.
- **Super+Y** (`notifi go`), or a click, runs its Focus action: the Hyprland
  window, tmux session, window and pane of that agent come to the front.
  With no notification up, Super+Y goes to the next waiting agent: the
  pending ones, longest wait first, then round the ones you have been to.
- **Super+X** forgets the agent in the focused window
  (`notifi dismiss --focused`).

An agent you went to stays **seen** until you answer it, it exits, or you
press Super+X, so looking at it doesn't lose it. The binds are in
`hypr/config/keybindings.lua`; Super+N and Super+Y work for any notification.

## Commands

```sh
notifi show [--event EVENT] [--app NAME] [--force] [-v]
notifi dismiss [--app NAME | --focused]
notifi pending [--waybar]
notifi next
notifi go
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

`dismiss` forgets this pane's agent: it closes its notification, or ends its
pending or seen state, and does nothing if the pane has none of them.
`dismiss --focused` does that for the agent you are looking at instead: the
one in the active pane of the tmux window in the focused Hyprland window or,
if that pane has no agent, every agent in that tmux window. It prints the
titles. `status` prints `allowed` or `blocked`. `--app` is the notification's
app name; outside tmux it is also the title and the identity, and there is
no Focus action.

`pending` prints one line per waiting agent,
`<title><TAB><event text><TAB>pending|seen`, in the order `next` takes them.
`--waybar` prints the count as a waybar JSON module instead: the pending
agents with class `pending` or, when none is pending, the seen ones with
class `seen`; nothing for none, which hides the module. `next` brings the
first waiting agent to the front as Focus would, marks it seen and prints its
title; with none waiting it prints nothing. `go` is what Super+Y runs: with a
notification on screen it runs the action of the top one, as
`dunstctl action` does, whether or not it is an agent's; with none it is
`next`. `pending`, `next`, `go` and `dismiss --focused` run from anywhere,
not only from a pane.

Exit status is 0 or 1, never 2, which Claude Code reads from a hook as "block
this".

## Events

| Event | Text | Urgency | Expires | Skipped while on screen |
| --- | --- | --- | --- | --- |
| `finished` (default) | Task Finished | normal | never | yes |
| `attention` | Needs Input | normal | never | yes |
| `error` | Task Failed | critical | never | no |
| `aborted` | Task Aborted | critical | 5 s | no |

The title is `<session>:<window index>`. The table is `EVENTS` in
`src/agents.rs`; there is no config file.

## Behavior

- **One notification per pane.** `show` first closes whatever that pane
  already has up, even when it then skips because the window is on screen.
- **Pending.** An agent is pending when its notification was closed without
  Focus and nothing has dismissed it since. Three cases never become
  pending: an event that expires (`aborted`), because a timeout and Super+N
  look the same to `notify-send`; a notification closed while its pane is on
  screen, which takes no going to; and an agent outside tmux, which has no
  pane to go back to.
- **Seen.** Going to an agent, with Focus or `next`, leaves it seen. `next`
  takes the seen agents after the pending ones, the one visited longest ago
  first, so repeating it goes round them. A notification is the only way in:
  an agent that finishes on screen is not recorded at all.
- **Forgetting** a pending or seen agent takes the agent's next `show` or
  `dismiss` (you answered, or it exited) or `dismiss --focused`.
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
stays behind until the notification closes, and then removes `toast` from
the record, which is what pending is: a record whose notification is gone.
That also covers a notification lost because dunst restarted. If
`notify-send` printed `focus`, the action was chosen: the waiter runs it and
adds `seen`, the time of the visit, as `next` does.

`dismiss` reads the record from any later process and removes it, stops that
`notify-send` and asks the daemon to close the id. Ids restart when dunst
does, so it closes only an id the running daemon issued, and it checks the
start time so a reused pid is never signalled.

`pending`, `next`, `go` and `dismiss --focused` read every record, and ask
tmux whether each pane is still there. Nothing runs in between: there is no
daemon, and the records are the only state. `dismiss --focused` finds the
tmux client in the focused Hyprland window the way "on screen" does, when
the key is pressed. Whenever the counts may have changed, notifi sends
waybar `SIGRTMIN+8`, and `custom/agents` in `waybar/config.jsonc` runs
`notifi pending --waybar` again; `waybar/style.css` dims class `seen`.

notifi is one static binary, a Rust crate:

| File | What is in it |
| --- | --- |
| `src/main.rs` | The commands and their options |
| `src/show.rs` | `show`, and the waiter it leaves behind |
| `src/agents.rs` | The events; the waiting agents from the records; `next`, `go`, `dismiss` |
| `src/desktop.rs` | Which Hyprland window a tmux client is in; "on screen"; Focus |
| `src/state.rs` | The records, their lock, the signal to waybar |
| `src/tmux.rs`, `src/hyprland.rs`, `src/dbus.rs` | Talking to tmux, Hyprland and dunst |
| `src/run.rs` | Child processes, and what `/proc` says of a process |

It speaks to each program directly instead of starting that program's
command: to Hyprland over its request socket, as `hyprctl` does; to dunst
over the session bus, as `gdbus` and `dunstctl` do, with the few messages it
needs written out in `src/dbus.rs`; to waybar by signal, with waybar's pid
found in `/proc`. tmux is the exception. Its client protocol is private to
each version, so `tmux` is run.

## Speed

Super+Y and Super+X run this command, so how long it takes is felt. Medians
of 40 runs with two agents waiting, timed from just before the process is
started:

| What | Takes |
| --- | --- |
| Super+Y's bind (`sh -c 'notifi go'`) until Hyprland is told the window | 3.5 ms |
| The same until the command has exited | 5.3 ms |
| Super+Y's bind with nothing waiting | 1.5 ms |
| `notifi next` until Hyprland is told the window | 2.4 ms |
| `notifi dismiss --focused` (Super+X) | 2.6 ms |
| `notifi pending --waybar` | 2.3 ms; 0.4 ms with no records |

The Python script this replaced took 40 ms for the first row. Of the 3.5 ms,
0.9 is the shell that Hyprland starts every `exec` bind through (`/bin/sh`,
bash here), 0.35 is notifi starting, which is what `/usr/bin/true` takes,
and the rest is one tmux listing its server's panes and clients. tmux takes
1.1 ms to start before it asks the server anything, so that and the shell
are the floor: 2 of the 3.5 ms.

What keeps it there, and what to keep to when changing it:

- **Nothing is started that can be asked directly.** A process costs 0.4 ms
  before it does anything. Hyprland's socket answers in 0.5 ms where
  `hyprctl` takes 4; a connection to the session bus and a question to dunst
  take 0.2 ms where `dunstctl` and `gdbus` take 5; finding waybar in `/proc`
  takes 1 ms where `killall` takes 3, and its pid is then kept in
  `$XDG_RUNTIME_DIR/notifi/bar` and only checked (remove that file if a
  second bar is started while the first runs).
- **One tmux per server**, asked everything at once: commands joined with
  `;`, their lines told apart by the first field. It runs with an empty
  environment, which a tmux client otherwise sends to the server (0.15 ms).
- **Nothing waits for tmux that needn't.** tmux is started first, and the
  records, Hyprland and dunst are read while it runs. Its answer ends with a
  marker line, so it is read without waiting for tmux to exit.
- **The tmux that answered also switches the pane.** It is started with
  `source-file -` as its last command, so after answering it reads commands
  from its input; `select-window`, `select-pane` and `switch-client` reach
  the server 0.3 ms after they are written there, instead of the 1.6 ms a
  second tmux takes. Hyprland is told the window right after, and the record
  and waybar are done while the tmux server redraws (1 to 2 ms).
- **Statically linked** (`.cargo/config.toml`): with a dynamic loader notifi
  takes 0.57 ms to start instead of 0.35.
- **Calls to the bus never start a daemon** (the no-auto-start flag): with
  no dunst running nothing is on screen, and a key must not wait for one to
  start.

Reading `source-file -` from standard input is not in tmux's manual, though
`load-buffer -` is, which reads the same way. The tests go through it, so
they fail on a tmux that stops doing it.

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
1.5.2, so nothing stays pending or seen for a pane you closed.

## Requirements

Linux only. To build, cargo (Rust 1.98 here) and glibc's static library,
which Arch's `glibc` has; `scripts/install` builds it and links
`target/release/notifi`. To run, `notify-send` (libnotify), `tmux` (3.8
here), `ghostty`, Hyprland, and a notification daemon that supports actions.
`go` asks dunst what is on screen (the interface `dunstctl` uses); with
another daemon it is `next`. The pending count is shown by waybar.

## Tests

```sh
python3 scripts/notifi/test_notifi.py
```

They build the crate, then run the command against disposable tmux servers
with attached clients (needs `script`), with stubs on `PATH` for
`notify-send` and `ghostty`, and Hyprland and the session bus as sockets
answered from the test. The test process stands in for waybar: `NOTIFI_BAR`
names the process that notifi signals. Nothing reaches the desktop. The pi
adapter has its own: `npm test` in `pi/picosystem/notifi/`.
