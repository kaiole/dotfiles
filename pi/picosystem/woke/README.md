# woke

Keep Linux awake while pi works. Allow normal automatic sleep when pi is idle.

## Load

For one session:

```sh
pi -e /home/red/dotfiles/pi/picosystem/woke/index.ts
```

To enable globally:

```sh
pi install /home/red/dotfiles/pi/picosystem/woke
```

Then run `/reload` in an existing pi session. No reboot or Hyprland configuration change is needed. `/woke` reports this session's inhibitor status.

Requires Linux, `systemd-inhibit`, a running systemd-logind, and permission to acquire idle inhibitors. Hypridle must respect systemd idle inhibitors, as it does by default. Requires a pi version with `agent_settled`, `ui_prompt_start`, `ui_prompt_end`, and `session_compact_failed` events. No npm runtime dependencies.

## Behavior

- Acquires an idle inhibitor on `agent_start` and waits for acquisition confirmation.
- Keeps it through model waits, tool calls, retries, and queued follow-ups. Releases on `agent_settled`, not `agent_end`.
- Also covers manual and automatic compaction.
- Releases during blocking extension UI prompts and reacquires when they close if work remains.
- Releases on shutdown, reload, or session replacement.
- Each pi process holds its own lock. One session finishing cannot release another session's lock.
- Reports acquisition failure or unexpected inhibitor exit without stopping the task. Check the warning before walking away; it does not silently claim protection or retry forever.

The inhibitor wraps a shell waiting on a private stdin pipe. Closing that pipe ends the shell and releases the lock. If pi crashes or receives SIGKILL, the kernel closes the pipe automatically. There are no persistent settings, lock files, or background daemons.

## Scope

This blocks **idle-triggered** sleep, not lid-close sleep, explicit suspend, shutdown, or critical-battery actions. It affects the machine running pi, not a laptop connected to a remote pi process over SSH.

Idle means pi has settled or is waiting in a blocking extension UI prompt. A hung tool or network request still counts as work until cancelled. Detached jobs continuing after pi settles do not keep the inhibitor. Standalone `!` shell commands and `/tree` summaries are outside the agent-task lifecycle and are not covered.

Your current `hypr/hypridle.conf` has one listener that suspends after 600 seconds. Woke pauses idle handling while active, then leaves sleep timing to hypridle. It does not explicitly suspend the laptop when the task ends.

Hypridle normally applies idle inhibitors to **all** listeners. If you later add automatic screen locking or display-off listeners and want those to run during pi tasks, set `ignore_inhibit = true` on those listeners only. Woke does not disable manual locking.

## Tests

```sh
cd /home/red/dotfiles/pi/picosystem/woke
npm test
```

Tests require Node.js with native TypeScript stripping and a working local systemd-logind. They acquire real idle inhibitors briefly and check lifecycle handling, independent sessions, missing executable errors, and cleanup after SIGKILL. They never request suspend or change sleep settings.
