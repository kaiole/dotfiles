#!/usr/bin/env bash
# Opt-in live test: requires the existing ubuntu-ros container. Never runs ROS nodes.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "$HOME/.local/share/distrobox/ros-home/.tmux-test.XXXXXXXX")
socket="$work/tmux.sock"
export TMUX="$socket,0,0"
unset TMUX_PANE
cleanup() {
    tmux -S "$socket" kill-server 2>/dev/null || true
    rm -rf -- "$work"
}
trap cleanup EXIT
mkdir -p "$work/project" "$work/project/space's \$(literal)" "$work/host"
tmux -S "$socket" -f /dev/null new-session -d -s check -c "$work/project"
TS_SESSION=check TS_PATH="$work/project" bash "$root/presets/ros"

cwd_of() {
    local state cwd
    state=$(tmux show-options -pqv -t "$1" @ros_state)
    [[ -n "$state" && -r "$state/cwd" ]] || return 1
    IFS= read -r -d '' cwd < "$state/cwd" || return 1
    printf '%s' "$cwd"
}
wait_cwd() {
    local i
    for ((i=0; i<100; i++)); do
        local state
        state=$(tmux show-options -pqv -t "$1" @ros_state)
        if [[ $(cwd_of "$1" || true) == "$2" && -e "$state/prompt" ]]; then return; fi
        sleep .1
    done
    tmux capture-pane -p -t "$1" >&2
    echo "Timeout waiting for $1 in $2" >&2
    exit 1
}
quote() { local text=${1//\'/\'\\\'\'}; printf "'%s'" "$text"; }
cd_pane() {
    tmux send-keys -l -t "$1" "cd -- $(quote "$2")"
    tmux send-keys -t "$1" Enter
    wait_cwd "$1" "$2"
}
[[ $(tmux list-windows -t check -F '#{window_name}' | paste -sd , -) == zsh,nvim ]]
[[ $(tmux display-message -p -t check: '#{window_name}') == nvim ]]
code=$(tmux display-message -p -t check:zsh '#{pane_id}')
build=$(tmux new-window -t check: -n test-shell -P -F '#{pane_id}')
wait_cwd "$code" "$work/project"
wait_cwd "$build" "$work/project"
cd_pane "$code" "$work/project/space's \$(literal)"
[[ $(cwd_of "$build") == "$work/project" ]]
new=$("$root/ros-tmux" create "$code" new-window -P -F '#{pane_id}')
wait_cwd "$new" "$work/project/space's \$(literal)"
# Container-only directories must never be used as host tmux's -c argument.
cd_pane "$code" /opt/ros/jazzy
split=$("$root/ros-tmux" create "$code" split-window -h -P -F '#{pane_id}')
wait_cwd "$split" /opt/ros/jazzy
[[ $(cwd_of "$new") == "$work/project/space's \$(literal)" ]]
# Default-command also protects direct tmux commands (root fallback).
direct=$(tmux new-window -t check: -P -F '#{pane_id}')
wait_cwd "$direct" "$work/project"
# Ctrl-F must reach foreground programs, not steal their key for sessionizer.
state=$(tmux show-options -pqv -t "$direct" @ros_state)
program='import sys,tty,termios; old=termios.tcgetattr(0); tty.setraw(0); c=sys.stdin.read(1); termios.tcsetattr(0,termios.TCSADRAIN,old); print("CONTROL_F="+str(ord(c)))'
tmux send-keys -l -t "$direct" "python3 -c $(quote "$program")"
tmux send-keys -t "$direct" Enter
for ((i=0; i<100; i++)); do [[ ! -e "$state/prompt" ]] && break; sleep .1; done
sleep .2
"$root/ros-tmux" picker "$direct"
for ((i=0; i<100; i++)); do
    if tmux capture-pane -p -t "$direct" | grep -q '^CONTROL_F=6'; then break; fi
    sleep .1
done
tmux capture-pane -p -t "$direct" | grep -q '^CONTROL_F=6'
# Missing cwd must leave an error, never a working host shell.
command="$(quote "$root/ros-tmux") shell /nonexistent-ros-tmux-test"
failed=$(tmux new-window -t check: -P -F '#{pane_id}' "$command")
for ((i=0; i<100; i++)); do
    if tmux capture-pane -p -t "$failed" | grep -q 'No host shell was started'; then break; fi
    sleep .1
done
tmux capture-pane -p -t "$failed" | grep -q 'No host shell was started'
# Host sessions never route through ros-tmux; it refuses them rather than
# guessing at host behavior.
host=$(tmux new-session -d -s host-check -c "$work/host" -P -F '#{pane_id}')
if "$root/ros-tmux" create "$host" new-window 2>/dev/null; then
    echo 'ros-tmux create accepted a host session' >&2; exit 1
fi
# Parse the actual bindings, including quotes and Ctrl-F dispatch, on this server.
tmux source-file "$root/../../tmux/tmux.conf"
binding() { tmux list-keys -T "$1" "$2"; }
for key in c '%' '"'; do binding prefix "$key" | grep -q '@ros_container'; done
binding prefix c | grep -q ros-tmux
binding prefix c | grep -q 'new-window -c "#{pane_current_path}"'
binding prefix '%' | grep -q 'split-window -h }'
binding prefix '"' | grep -q 'split-window }'
binding root C-f | grep -q tmux-sessionizer
binding prefix C-f | grep -q tmux-sessionizer
# Run the host branches exactly as the bindings do, with a host pane as context.
# Each adds one host pane; new-window keeps following the pane's cwd.
for key in c '%' '"'; do
    before=$(tmux list-panes -s -t host-check -F '#{pane_id}')
    command=$(binding prefix "$key" | sed -E 's/^bind-key +-T prefix +[^ ]+ +//')
    tmux if-shell -t "$host" true "$command"
    added=$(comm -13 <(sort <<< "$before") <(tmux list-panes -s -t host-check -F '#{pane_id}' | sort))
    [[ -n "$added" && "$added" != *$'\n'* ]]
    [[ -z $(tmux show-options -pqv -t "$added" @ros_state) ]]
    [[ "$key" != c ]] || [[ $(tmux display-message -p -t "$added" '#{pane_current_path}') == "$work/host" ]]
done
printf 'ROS integration tests passed\n'
