#!/usr/bin/env bash
# Opt-in test against an ALREADY CREATED, STOPPED disposable Distrobox container.
# Never use/stop the real ubuntu-ros. Creation/removal are the caller's job.
set -euo pipefail
container=${1:?Supply a stopped disposable container named ros-startup-check-*}
[[ "$container" == ros-startup-check-* ]] || {
    echo 'Refusing to cold-start a non-test container' >&2; exit 1;
}
status=$(podman inspect --format '{{.State.Status}}' "$container")
[[ "$status" == created || "$status" == exited || "$status" == configured ]] || {
    echo 'Test container must already be stopped' >&2; exit 1;
}
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
ROS_TEST_WORK="$work" ROS_TEST_CONTAINER="$container" ROS_TEST_HELPER="$root/ros-tmux" python3 - <<'PY'
import os
import subprocess
import time

work = os.environ['ROS_TEST_WORK']
container = os.environ['ROS_TEST_CONTAINER']
helper = os.environ['ROS_TEST_HELPER']
socket = work + '/tmux.sock'
env = dict(os.environ, TMUX=socket + ',0,0')
env.pop('TMUX_PANE', None)


def tmux(*args):
    return subprocess.check_output(
        ['tmux', '-S', socket, *args], env=env, text=True
    ).strip()


def is_ready(pane):
    state = tmux('show-options', '-pqv', '-t', pane, '@ros_state')
    return bool(state) and os.path.exists(state + '/prompt')


def wait_ready(panes, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if all(is_ready(pane) for pane in panes):
            return
        time.sleep(.2)
    for pane in panes:
        print(tmux('capture-pane', '-p', '-t', pane))
    raise RuntimeError('Container shells did not reach a prompt')


try:
    tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'cold-check', '-c', work)
    tmux('set-option', '-t', 'cold-check', '@ros_container', container)
    tmux('set-option', '-t', 'cold-check', '@ros_root', work)
    command = "'" + helper.replace("'", "'\\''") + "' shell"
    tmux('set-option', '-t', 'cold-check', 'default-command', command)
    first = tmux('display-message', '-p', '-t', 'cold-check:', '#{pane_id}')
    tmux('respawn-pane', '-k', '-t', first, command)
    second = tmux('new-window', '-t', 'cold-check:', '-P', '-F', '#{pane_id}')
    wait_ready([first, second], 180)
    # Both panes stay open: the lock must not follow their interactive lifetime.
    third = tmux('new-window', '-t', 'cold-check:', '-P', '-F', '#{pane_id}')
    wait_ready([third], 15)
    # Let Distrobox finish its exec sessions cleanly before killing the server.
    for pane in [first, second, third]:
        tmux('send-keys', '-t', pane, 'exit', 'Enter')
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        remaining = subprocess.run(
            ['tmux', '-S', socket, 'has-session', '-t', 'cold-check'],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if remaining.returncode:
            break
        time.sleep(.1)
    else:
        raise RuntimeError('Container exec sessions did not close cleanly')
    print('ROS cold-start test passed: simultaneous panes, then another while open')
finally:
    subprocess.run(
        ['tmux', '-S', socket, 'kill-server'], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
PY
