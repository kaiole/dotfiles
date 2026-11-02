#!/usr/bin/env bash
# Deterministic startup regression; no real container or user tmux server touched.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/runtime" "$work/cache"
export ROS_STARTUP_TEST="$work" XDG_RUNTIME_DIR="$work/runtime"
export XDG_CACHE_HOME="$work/cache" PATH="$work/bin:$PATH"
cat > "$work/bin/distrobox" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1 $2 $3 $4 $5 $6 $7" == 'enter --name ubuntu-test --no-workdir --no-tty -- /bin/true' ]]
printf 'entry\n' >> "$ROS_STARTUP_TEST/entries"
if [[ -e "$ROS_STARTUP_TEST/fail" ]]; then exit 42; fi
# A concurrent entry is an error, just as two cold-start readers are unsafe.
mkdir "$ROS_STARTUP_TEST/active" || exit 99
sleep .05
# A successful cold start leaves the container running.
[[ ! -e "$ROS_STARTUP_TEST/starts" ]] || : > "$ROS_STARTUP_TEST/running"
rmdir "$ROS_STARTUP_TEST/active"
MOCK
cat > "$work/bin/podman" <<'MOCK'
#!/usr/bin/env bash
[[ "$1 $2 $3 $4 $5" == 'container inspect -f {{.State.Running}} ubuntu-test' ]] || exit 125
if [[ -e "$ROS_STARTUP_TEST/running" ]]; then echo true; else echo false; fi
MOCK
cat > "$work/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
    *'show-options'*'@ros_container'*) echo ubuntu-test ;;
    *'show-options'*'@ros_root'*) echo /tmp ;;
esac
MOCK
chmod +x "$work/bin/distrobox" "$work/bin/podman" "$work/bin/tmux"
unset DBX_CONTAINER_MANAGER
concurrent_entries() {
    local pids=() pid i
    : > "$work/entries"
    for ((i=0; i<8; i++)); do
        bash -c 'source "$1"; ensure_container_ready ubuntu-test' _ "$root/ros-tmux" &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do wait "$pid"; done
    wc -l < "$work/entries"
}
# Stopped container that never reports running: every entrant probes, serially.
[[ $(concurrent_entries) -eq 8 ]]
# Cold start: the first entrant probes; the rest wait on the lock, then see it running.
: > "$work/starts"
[[ $(concurrent_entries) -eq 1 ]]
# Already running: no probe at all.
[[ $(concurrent_entries) -eq 0 ]]
rm -- "$work/starts" "$work/running"
# Verify the non-runtime-directory fallback also locks correctly.
unset XDG_RUNTIME_DIR
bash -c 'source "$1"; ensure_container_ready ubuntu-test' _ "$root/ros-tmux"
[[ -f "$work/cache/ros-tmux/ubuntu-test.lock" ]]
# No lock persists after readiness: subsequent entries are immediately possible.
timeout 2 bash -c 'source "$1"; ensure_container_ready ubuntu-test' _ "$root/ros-tmux"
# Refuse names that could escape the lock directory.
if bash -c 'source "$1"; ensure_container_ready ../escape' _ "$root/ros-tmux" 2>/dev/null; then
    echo 'Invalid container name was accepted' >&2; exit 1
fi
# Failed preparation must not attempt the interactive shell or silently fall back.
: > "$work/entries"
: > "$work/fail"
set +e
printf '\n' | TMUX_PANE=%test "$root/ros-tmux" shell /tmp > "$work/error" 2>&1
status=$?
set -e
[[ "$status" -eq 42 ]]
[[ $(wc -l < "$work/entries") -eq 1 ]]
grep -q 'No host shell was started' "$work/error"
# A failed readiness probe must also release the startup lock.
rm -- "$work/fail"
timeout 2 bash -c 'source "$1"; ensure_container_ready ubuntu-test' _ "$root/ros-tmux"
printf 'ROS startup serialization tests passed\n'
