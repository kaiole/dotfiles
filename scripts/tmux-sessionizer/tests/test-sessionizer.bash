#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../tmux-sessionizer"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/personal" "$tmp/sandbox" "$tmp/outside" "$tmp/personal/ignored"
IGNORE_PATHS=("$tmp/personal/ignored")

expect_failure() {
    if "$@" >/dev/null 2>&1; then
        printf 'Expected failure: %s\n' "$*" >&2
        exit 1
    fi
}

[[ $(create_directory "$tmp/personal" 'rust/new project') == "$tmp/personal/rust/new project" ]]
[[ -d "$tmp/personal/rust/new project" ]]
[[ $(create_directory "$tmp/personal" 'rust/new project') == "$tmp/personal/rust/new project" ]]
expect_failure create_directory "$tmp/personal" ''
expect_failure create_directory "$tmp/personal" /absolute
expect_failure create_directory "$tmp/personal" ../escape
expect_failure create_directory "$tmp/personal" nested/../../escape
expect_failure create_directory "$tmp/personal" ignored/new
ln -s "$tmp/outside" "$tmp/personal/link"
expect_failure create_directory "$tmp/personal" link/new
[[ ! -e "$tmp/outside/new" ]]
printf 'file' > "$tmp/personal/file"
expect_failure create_directory "$tmp/personal" file/new
create_directory "$tmp/personal" 'literal $(touch nope)' >/dev/null
[[ -d "$tmp/personal/literal \$(touch nope)" ]]

printf '[TMUX] personal\n%s\n%s\n' "$tmp/personal" "$tmp/sandbox" > "$tmp/input"
printf '%s\n' "$tmp/personal" "$tmp/sandbox" > "$tmp/input.create"
[[ $(picker_filter "$tmp/input" 'pers:new-proj') == "$tmp/personal" ]]
[[ $(picker_filter "$tmp/input" 'sand:child:with-colon') == "$tmp/sandbox" ]]
[[ -z $(picker_filter "$tmp/input" 'does-not-exist:child') ]]
[[ $(picker_filter "$tmp/input" 'personal') == *'[TMUX] personal'* ]]
[[ $(picker_preview 'pers:new project' "$tmp/personal") == "Create: $tmp/personal/new project" ]]

# Active sessions hide directories only in normal mode, not creation mode.
TS_SEARCH_PATHS=("$tmp/personal:1" "$tmp/sandbox:0")
TS_MAX_DEPTH=1
SESSION_IDS=('$1' '$2')
SESSION_PATHS=("$tmp/personal" "$tmp/personal/ignored")
SESSION_NAMES=(personal ignored)
TMUX='' find_dirs > "$tmp/input"
TMUX='' find_dirs create > "$tmp/input.create"
! grep -Fx "$tmp/personal" "$tmp/input" >/dev/null
grep -Fx '[TMUX] personal' "$tmp/input" >/dev/null
grep -Fx "$tmp/personal" "$tmp/input.create" >/dev/null
! grep -F '[TMUX]' "$tmp/input.create" >/dev/null
! grep -Fx "$tmp/personal/ignored" "$tmp/input.create" >/dev/null
picker_filter "$tmp/input" 'pers:new-proj' | grep -Fx "$tmp/personal" >/dev/null
# The current session's path is also available for creation.
tmux() { printf '$1\n'; }
SESSION_IDS=('$1' '$2')
TMUX=test find_dirs create | grep -Fx "$tmp/personal" >/dev/null

# Exercise the complete CLI without touching the user's tmux server.
load_config() {
    TS_PRESET_DIR="$tmp/presets"
    TS_DEFAULT_PRESET=default
    RULE_PATHS=(); RULE_PRESETS=(); IGNORE_PATHS=()
}
snapshot_sessions() { SESSION_IDS=(); SESSION_PATHS=(); SESSION_NAMES=(); }
find_dirs() { printf '%s\n' "$tmp/personal"; }
tmux() {
    printf '%s\n' "$*" >> "$tmp/tmux.log"
    [[ "$1" != new-session ]] || printf '$42\n'
}
mkdir "$tmp/presets"
printf 'printf "%%s\\n" "$TS_PATH" > "%s/preset-path"\n' "$tmp" > "$tmp/presets/default"
TMUX=test main --new "$tmp/personal" cli-project
[[ -d "$tmp/personal/cli-project" ]]
[[ $(<"$tmp/preset-path") == "$tmp/personal/cli-project" ]]
grep -Fx 'switch-client -t $42' "$tmp/tmux.log" >/dev/null
expect_failure main --new "$tmp/outside" project
[[ ! -e "$tmp/outside/project" ]]
printf 'All tests passed\n'
