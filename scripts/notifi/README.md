# notifi

Desktop notifications for coding agents running in tmux, on Hyprland with
dunst and Ghostty, and the same agents listed in tmux itself, wherever tmux
runs. An agent calls `notifi show` when it finishes or needs you, `notifi
start` when it goes to work on your answer, and `notifi dismiss` when it
exits. pi and Claude Code both use it.

- **Super+N** closes the notification (`dunstctl close`) and leaves its agent
  **pending**: counted in waybar until you go to it.
- **Super+Y** (`notifi go`), or a click, runs its Focus action: the Hyprland
  window, tmux session, window and pane of that agent come to the front.
  With no notification up, Super+Y goes to the next waiting agent: the
  pending ones, longest wait first, then round the ones you have been to.
- **Super+Shift+Y** (`notifi next --running`) goes round the agents at
  work: the ones not gone to yet, longest at work first, then the one gone
  to longest ago. Each stays running.
- **Super+X** forgets the agent in the focused window
  (`notifi dismiss --focused`).

An agent you went to stays **seen** until you answer it, it exits, or you
press Super+X, so looking at it doesn't lose it. So does one that stops while
you can see it: nothing else decides that an agent is done with. An agent
you answered is **running** until it stops again. waybar counts each of the
three, running, pending and seen, in a module of its own that is always
there, so what you sent out stays in view as well as what waits for you. The
binds are in `hypr/config/keybindings.lua`; Super+N and Super+Y work for any
notification.

In tmux, with or without that desktop (the binds are in `tmux/tmux.conf`):

- **prefix g** opens the agents of this tmux server in a popup
  (`notifi pick`): the pending ones, the seen ones and the ones at work,
  each by its session (and window, where two share a session), its
  harness, what it stopped with and for how long. A ⸸ marks the agent in
  the pane the popup opened over, if it is one. The popup is as tall as
  the list. `j`/`k` or the arrows move, Enter goes to the selected agent
  and a digit to that row, `x` forgets the selected one and leaves the list
  open, `q` or Esc closes.
- **prefix y** goes to the next waiting agent of this tmux server
  (`notifi next --tmux`), in Super+Y's order.
- **The status line** counts the three, as waybar does, on a server that
  has no Hyprland in its environment.

Without a desktop to notify, which is a tmux server started over SSH and any
macOS, there is no notification: an agent that stops is pending until you go
to it, unless you were looking at it.

## Commands

```sh
notifi show [--event EVENT] [--app NAME] [--force] [-v]
notifi start [--app NAME] [--hook]
notifi dismiss [--app NAME | --focused]
notifi pending [--waybar]
notifi seen [--waybar]
notifi running [--waybar]
notifi next [--tmux | --running]
notifi pick
notifi go
notifi status
```

`show` notifies for the agent in this tmux pane (`$TMUX`, `$TMUX_PANE`) and
returns at once. It prints nothing unless `-v`, which prints the outcome:

| Outcome | Meaning |
| --- | --- |
| `sent` | The notification is up |
| `visible` | No notification: the agent's tmux window is on screen, so it is seen at once |
| `kept` | No notification: this tmux server has no desktop to notify, so the agent is on record for tmux to show |
| `blocked` | Skipped: outside tmux, with no desktop to notify |
| `failed: <why>` | `notify-send` failed; also on stderr, exit status 1 |

`start` says that this pane's agent is at work: it ends what the agent was
waiting with, as `dismiss` does, and records it as running until its next
`show` or `dismiss`. Outside tmux it records nothing. `--hook` is for Claude Code, whose hook input it reads from
standard input: a prompt (`UserPromptSubmit`) starts the agent, and any
other hook only an agent that stopped and went on, so one that is running
already, or that you forgot, is left as it is.

`dismiss` forgets this pane's agent: it closes its notification, or ends its
pending, seen or running state, and does nothing if the pane has none of them.
`dismiss --focused` does that for the agent you are looking at instead: the
one in the active pane of the tmux window in the focused Hyprland window or,
if that pane has no agent, every agent in that tmux window. It prints the
titles. `status` prints `allowed` or `blocked`. `--app` is the notification's
app name; outside tmux it is also the title and the identity, and there is
no Focus action.

`pending` prints one line per waiting agent,
`<title><TAB><event text><TAB>pending|seen`, in the order `next` takes them.
`seen` prints only the seen ones, without the last field. With `--waybar`,
`pending`, `seen` and `running` each print a waybar JSON module instead: the
count of the pending, the seen or the running agents as `text`, their lines
as `tooltip` and the command's name as `class`; with none, `0`, `No agent
<name>` and class `none`. `next` brings the
first waiting agent to the front as Focus would, marks it seen and prints its
title; with none waiting it prints nothing. `next --running` does the
same for the agents at work, in the order above, and leaves each running:
its record keeps when it was gone to (`visited`), and nothing else
changes. `go` is what Super+Y runs: with a
notification on screen it runs the action of the top one, as
`dunstctl action` does, whether or not it is an agent's; with none it is
`next`. `running` prints one line per agent at work,
`<title><TAB><how long>` (`<1m`, `12m`, `1h05m`), longest first.
`pending`, `seen`, `running`, `next`, `go` and `dismiss --focused` run from
anywhere, not only from a pane.

`next --tmux` and `pick` are for a tmux key bind, whose `$TMUX` names the
server and the session of the client the key was pressed in. They take only
that server's agents, and tmux alone shows what they go to: the pane is
selected and that client switched to its session, with no Hyprland asked.
`next --tmux` prints nothing; with no agent waiting it says so in the
client's status line. It also takes an agent whose notification is still
up, which it closes. `pick` needs a terminal, which the popup gives it.

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
- **Every stop is kept.** An agent in a tmux pane that called `show` is on
  record, pending or seen, until it is forgotten. Only an agent outside
  tmux is not: it has no pane to go back to.
- **Pending.** An agent is pending when its notification was closed without
  Focus while its pane was off screen.
- **Seen.** Going to an agent, with Focus or `next`, leaves it seen. So does
  what takes no going to: an event skipped because the pane is on screen, a
  notification closed while it is, and one that expires (`aborted`), where
  a timeout and Super+N look the same to `notify-send` and you were there
  to abort it. `next` takes the seen agents after the pending ones, the one
  seen longest ago first, so repeating it goes round them.
- **Forgetting** a pending or seen agent takes the agent's next `show`,
  `start` or `dismiss` (it stopped again, you answered, or it exited) or
  `dismiss --focused`. Nothing else does: looking at an agent never marks
  it done.
- **Running.** An agent that called `start` is at work. It is not waiting,
  so `pending` and `next` pass it over; `running` lists it. Its next `show`
  makes it a waiting agent again, and `dismiss --focused` forgets it like
  any other, until its next prompt or stop.
- **Interrupted.** Claude Code tells nobody when you interrupt it, so the
  transcript of each running one is read whenever the records are, which
  waybar does every 30 s. Without waybar that is the next `pick` or `next`,
  and the list, while open, every second: until then tmux's status line
  still counts the agent as running. If the last turn in it since the agent started is
  your interrupt, the agent becomes `aborted` and seen, with no
  notification: you were there. pi says so itself.
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
- **Without a desktop** (such a server, `off`, or a build that is not for
  Linux) an agent in tmux is recorded as everywhere else, with no
  notification: `show` leaves it pending, or seen if it stopped in view or
  with an event that expires (`aborted`). In view is what tmux knows of it:
  an attached client whose terminal has focus is showing the pane's window.
  That holds for every event, `error` too, since there is no notification
  to show in spite of it; `--force` skips the check. tmux learns of focus
  from the terminal (`focus-events on`, and a terminal that reports it):
  one that doesn't counts as focused for as long as it is attached.
- **In tmux's own view** an agent belongs to the server it runs in. The
  list, `next --tmux` and the status line show that server's agents only,
  where the desktop commands take every server's.

## How it works

`show` starts `notify-send --print-id --wait --action=focus=Focus`, which
lives exactly as long as the notification, and writes a record to
`$XDG_RUNTIME_DIR/notifi/<socket + pane id>.json`: the event, the time, the
harness (`app`, from `--app`), the pane (socket, pane id, tmux server pid) and the notification (`toast`: id,
daemon bus name, pid and start time of that `notify-send`). A detached waiter
stays behind until the notification closes, and then removes `toast` from
the record, which is what pending is: a record whose notification is gone.
That also covers a notification lost because dunst restarted. If
`notify-send` printed `focus`, the action was chosen: the waiter runs it and
adds `seen`, the time of the visit, as `next` does. It adds `seen` as well
if the pane is on screen by then or the event expires. A `show` skipped
because the pane is on screen writes the record itself, with `seen` and no
`toast`. `start` writes one with the time, the harness, the pane and, in
place of the event, `running`: the transcript a hook named and how long that
file was.
Without a desktop `show` writes the record with no `toast`, and `seen` if
the pane was in view, and leaves no waiter.

Each time a record is written, its pane is told what it says in the pane
option `@notifi`, `running`, `pending` or `seen`, and the option is unset
when the agent is forgotten. That is all the status line reads: `tmux.conf`
counts the panes with each value in a format, so nothing is run for it and
tmux draws the line again as soon as an option changes. The records stay
the truth, and the option follows them: one already on record when this
was built gets it at its next change, and removing the records by hand
leaves the options behind (`tmux set-option -pu -t <pane> @notifi`).

`dismiss` reads the record from any later process and removes it, stops that
`notify-send` and asks the daemon to close the id. Ids restart when dunst
does, so it closes only an id the running daemon issued, and it checks the
start time so a reused pid is never signalled.

`pending`, `seen`, `running`, `next`, `go` and `dismiss --focused` read
every record, and ask tmux whether each pane is still there. They also read the
end of each running agent's transcript, at most 64 KB of what was written
since it started, and rewrite the record as `aborted` and seen if that ends
with an interrupt. Nothing runs in between: there is no daemon, and the
records are the only state. `dismiss --focused` finds the tmux client in
the focused Hyprland window the way "on screen" does, when the key is
pressed. `pick` reads the records of its server the same way, again every
second while it is open, and holds no lock in between. Its colors are the
palette's, in `colors` here, which `theme` renders from
`theme/templates/scripts/notifi/colors` and `pick` reads as it starts.
`tmux.conf` sizes its popup from the counts in `@notifi`, expanded by
`run-shell -C` since `display-popup -h` takes no format. Whenever the counts
may have changed, notifi sends waybar `SIGRTMIN+8`, and `custom/running`, `custom/pending` and `custom/seen` in
`waybar/config.jsonc` run `notifi running --waybar`, `notifi pending
--waybar` and `notifi seen --waybar` again; `waybar/style.css` makes the
class `none` of each faint.

notifi is one binary, a Rust crate, static on Linux:

| File | What is in it |
| --- | --- |
| `src/main.rs` | The commands and their options |
| `src/show.rs` | `show`, and the waiter it leaves behind; `start` |
| `src/agents.rs` | The events; the agents from the records, and whether a running one was interrupted; `next`, `go`, `dismiss` |
| `src/pick.rs` | `pick`: the list, its keys and the terminal it draws on |
| `src/desktop.rs` | Which Hyprland window a tmux client is in; "on screen"; Focus |
| `src/state.rs` | The records, their lock, the pane option, the signal to waybar |
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
| `notifi pending --waybar`, or `seen` or `running`, with one agent running | 2.3 ms each (waybar runs all three on each signal, and no key waits for them); 0.35 ms with no records |
| `notifi start --hook` after a tool (running already, or no record) | 0.5 ms |
| `notifi start --hook` for a prompt | 4.3 ms |

A prompt's `start` waits for the tmux that tells the pane its agent runs;
no key waits for it, nor does Claude, whose hooks are `async`. The
Python script this replaced took 40 ms for the first row. Of the 3.5 ms,
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

Telling each pane its agent's state (`@notifi`) left the keys as they were
and cost the hooks one tmux command. Against the binary from before it,
medians of 40, old and new by turns:

| What | Before | After |
| --- | --- | --- |
| Super+Y's bind until Hyprland is told the window | 3.2 ms | 3.2 ms |
| `notifi next` until Hyprland is told the window | 2.2 ms | 2.2 ms |
| `notifi dismiss --focused` | 2.3 ms | 2.4 ms |
| `notifi start --hook` for a prompt, on the live server | 5.2 ms | 5.2 ms |
| `notifi show`, notification sent, on the live server | 6.5 ms | 7.3 ms |
| `notifi dismiss`, on the live server | 3.0 ms | 5.2 ms |

The first three were timed in the tests' harness, which answers for
Hyprland; the last three against the tmux server in use, a busier one, with
the records elsewhere and a stub for `notify-send`. `show` tells the pane
through the tmux it had asked about the pane, which stayed for that; a tmux
of its own took `show` 3 ms more in the harness instead of 0.4. `start` and
`dismiss` had asked tmux nothing that could stay, so they start one and wait
for it, so that a later word for the pane can't overtake it. `dismiss` is
the one hook Claude waits for, once, as it exits. `dismiss --focused`
doesn't wait for its own.

The tmux binds, in the harness, on a server with two agents waiting:

| What | Takes |
| --- | --- |
| `notifi next --tmux` until it has exited | 2.9 ms |
| The same with nothing waiting | 2.5 ms |
| `notifi pick` until the list is drawn | 2.0 ms |

`run-shell` starts `next --tmux` through the server's `default-shell`, 1 ms
for zsh here; the popup's command is given to tmux in words, which it
starts without one.

Reading `source-file -` from standard input is not in tmux's manual, though
`load-buffer -` is, which reads the same way. The tests go through it, so
they fail on a tmux that stops doing it.

## Callers

| Agent | Where | Shows | Starts | Dismisses |
| --- | --- | --- | --- | --- |
| Claude Code | `hooks` in `claude/settings.json` | `Stop` → `finished`, `StopFailure` → `error`, `PermissionRequest` → `attention` | `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure`, all with `--hook` | `SessionEnd` |
| pi | `pi/picosystem/notifi/` | `agent_end` → `finished`, `error` or `aborted` by stop reason | `agent_start` | `session_shutdown` |

Claude Code notes, measured on v2.1.321:

- `PermissionRequest` fires as soon as a permission dialog, a question
  (`AskUserQuestion`) or a plan approval appears. Commands that auto mode
  approves by itself don't fire it.
- Answering fires `PostToolUse`, but only once the tool has run, so until
  then the agent still counts as waiting, and as running from there.
  Declining fires nothing, so that notification stays until your next
  prompt or the end of the turn.
- `Stop` doesn't fire when you interrupt, so there is no `aborted` hook.
  Nothing else fires then either: not `PostToolUse` or `PostToolUseFailure`
  for a tool cut short, nor the `Notification` hook's `idle_prompt`, which
  comes 60 s after a `Stop` and only then.
- The transcript does tell (`transcript_path` in every hook's input, one
  JSON row per line). After an interrupt its last `user` or `assistant` row
  is a user turn whose text starts with `[Request interrupted by user`,
  during a tool as well; rows of other types follow it. The format is not
  documented: if it changes, an interrupted agent stays running until its
  next prompt or Super+X.
- When `UserPromptSubmit` fires, the prompt is not in the transcript yet:
  its last row is still the turn before, which may be an interrupt. So
  `start` records how long the file is, and only what comes after counts.
- `/context` and `!command` fire no `UserPromptSubmit`.
- Hooks are read when a session starts: one that was running before a
  change to them keeps the old ones until it is restarted.
- Don't hook `SubagentStop`: it also fires after every `Stop`.
- The hooks are `async` so they never delay Claude, except `SessionEnd`,
  which must finish before Claude exits. Each starts with
  `command -v notifi >/dev/null || exit 0`, so hosts without notifi stay
  quiet.

pi adds `/notifi on|off|test|status`; on/off is saved in the session. Off,
or without a UI, it never shows, so it doesn't start either: `agent_start`
dismisses instead, and so does `/notifi off`.

Killing an agent's tmux pane, session or server still runs its last dismiss
(`SessionEnd`, `session_shutdown`), measured on Claude Code v2.1.321 and pi
1.5.2, so nothing stays waiting or running for a pane you closed.

## Requirements

To build, cargo (Rust 1.98 here); `scripts/install` builds it and links
`target/release/notifi`, on Linux and macOS. On Linux it also takes glibc's
static library, which Arch's `glibc` has.

For the desktop, Linux only: `notify-send` (libnotify), `tmux` (3.8 here),
`ghostty`, Hyprland, and a notification daemon that supports actions. `go`
asks dunst what is on screen (the interface `dunstctl` uses); with another
daemon it is `next`. The counts are shown by waybar.

For tmux alone, a `tmux` with popups and pane options: 3.8 here, and no
older one was tried. The macOS
build is the tmux part only: `show` answers `kept` or `visible` and never
notifies, and `go`, `next` without `--tmux` and `dismiss --focused` have no
Hyprland to work with. It compiles for `aarch64-apple-darwin`
(`cargo check --target aarch64-apple-darwin`); it has not been run on a Mac
yet. Without `$XDG_RUNTIME_DIR`, as there, the records are in
`/tmp/notifi-<uid>/notifi/`.

## Tests

```sh
python3 scripts/notifi/test_notifi.py
```

They build the crate, then run the command against disposable tmux servers
with attached clients (needs `script`), with stubs on `PATH` for
`notify-send` and `ghostty`, and Hyprland and the session bus as sockets
answered from the test. The test process stands in for waybar: `NOTIFI_BAR`
names the process that notifi signals. Nothing reaches the desktop. The
server started over SSH is the one without a desktop: the list runs in a
window of it, where the popup would be, and is driven with `send-keys`. The pi
adapter has its own: `npm test` in `pi/picosystem/notifi/`.
