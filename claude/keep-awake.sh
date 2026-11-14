#!/usr/bin/env bash
# Keeps the machine from idle-suspending while Claude Code is working.
#   keep-awake.sh hold     (UserPromptSubmit hook) take a sleep lock
#   keep-awake.sh release  (Stop, SessionEnd hooks) drop it
# The hook JSON on stdin gives the session id, so each session holds its own
# lock and the machine stays up until the last one finishes.
#
# Only sleep is blocked: the screen still blanks and locks on idle, and closing
# the lid still suspends. Linux holds a logind block inhibitor, which makes
# hypridle's `systemctl suspend` fail; macOS runs `caffeinate -i`. The lock also
# ends when the claude process exits, in case no release hook runs.
set -u

session=$(jq -r '.session_id // empty' 2>/dev/null)
[[ -n $session ]] || exit 0
dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/claude-keep-awake
pidfile=$dir/$session.pid

release() {
  [[ -f $pidfile ]] || return 0
  local pid
  pid=$(<"$pidfile")
  # Killing systemd-inhibit alone would orphan its waiting child.
  pkill -P "$pid" 2>/dev/null
  kill "$pid" 2>/dev/null
  rm -f "$pidfile"
}

# The claude process that ran this hook, found up the process tree.
claude_pid() {
  local pid=$PPID
  while ((pid > 1)); do
    [[ $(ps -o comm= -p "$pid") == *claude* ]] && { echo "$pid"; return; }
    pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
  done
}

hold() {
  [[ -f $pidfile ]] && kill -0 "$(<"$pidfile")" 2>/dev/null && return 0
  mkdir -p "$dir"
  local owner
  owner=$(claude_pid)
  case $(uname) in
    Darwin)
      # -w ends caffeinate with claude; with no owner it runs until released.
      caffeinate -i ${owner:+-w "$owner"} </dev/null >/dev/null 2>&1 &
      ;;
    Linux)
      command -v systemd-inhibit >/dev/null || return 0
      local wait=(sleep infinity)
      [[ -n $owner ]] && wait=(tail --pid="$owner" -f /dev/null)
      systemd-inhibit --what=sleep --mode=block --who="Claude Code" \
        --why="Agent is working" "${wait[@]}" </dev/null >/dev/null 2>&1 &
      ;;
    *) return 0 ;;
  esac
  echo $! >"$pidfile"
}

case ${1:-} in
  hold) hold ;;
  release) release ;;
esac
exit 0
