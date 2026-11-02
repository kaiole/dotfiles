#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../tmux-sessionizer"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

# Batch canonicalization keeps positional empty results, resolves each relative
# path against the original cwd, and does not change the caller's cwd/CDPATH.
mkdir -p "$tmp/tree/a/child/grandchild" "$tmp/tree/b/deep/leaf" \
    "$tmp/tree/b/.hidden" "$tmp/tree/b/.git/objects" \
    "$tmp/tree/b/ignored/nested" "$tmp/tree/b/ignored-sibling" \
    "$tmp/tree/weird [*] dir/child" "$tmp/outside"
ln -s "$tmp/tree/a" "$tmp/alias"
ln -s "$tmp/outside" "$tmp/tree/b/link"
(
    cd "$tmp"
    export CDPATH="$tmp/outside"
    resolved=()
    while IFS= read -r path; do resolved+=("$path"); done < <(
        canonical_dir missing tree/a alias tree/b missing-again
    )
    [[ ${#resolved[@]} == 5 ]]
    [[ -z ${resolved[0]} && -z ${resolved[4]} ]]
    [[ ${resolved[1]} == "$tmp/tree/a" && ${resolved[2]} == "$tmp/tree/a" ]]
    [[ ${resolved[3]} == "$tmp/tree/b" ]]
    [[ $PWD == "$tmp" && $CDPATH == "$tmp/outside" ]]
    [[ $(HOME="$tmp" canonical_dir '~/tree/a') == "$tmp/tree/a" ]]
    [[ $(HOME="$tmp" canonical_dir '~') == "$tmp" ]]
    if canonical_dir missing >/dev/null; then exit 1; fi
)

# Missing preset roots must not shift the remaining root-to-preset mapping.
(
    mkdir -p "$tmp/config/tmux-sessionizer/presets"
    printf ':\n' > "$tmp/config/tmux-sessionizer/presets/default"
    printf ':\n' > "$tmp/config/tmux-sessionizer/presets/other"
    printf 'TS_PRESET_RULES=("%s|default" "%s|other")\nTS_IGNORE_PATHS=("%s" "%s")\n' \
        "$tmp/missing" "$tmp/alias" "$tmp/missing" "$tmp/tree/b/ignored" \
        > "$tmp/config/tmux-sessionizer/tmux-sessionizer.conf"
    XDG_CONFIG_HOME="$tmp/config" load_config
    [[ ${#RULE_PATHS[@]} == 1 && ${RULE_PATHS[0]} == "$tmp/tree/a" ]]
    [[ ${RULE_PRESETS[0]} == other ]]
    [[ ${#IGNORE_PATHS[@]} == 1 && ${IGNORE_PATHS[0]} == "$tmp/tree/b/ignored" ]]
)

# Mixed depths, overlapping roots, symlink aliases, hidden directories, literal
# glob characters, and ignores retain the same candidate set. Find runs only
# once per distinct depth, regardless of how many roots use that depth.
TS_MAX_DEPTH=1
TS_SEARCH_PATHS=("$tmp/tree/a:0" "$tmp/missing:3" "$tmp/tree/b:2"
    "$tmp/alias" "$tmp/tree/a/child:1" "$tmp/tree/b:1"
    "$tmp/tree/weird [*] dir:1")
IGNORE_PATHS=("$tmp/tree/b/ignored")
SESSION_IDS=('$1' '$2')
SESSION_PATHS=("$tmp/tree/a" "$tmp/outside")
SESSION_NAMES=(a outside)
find() { printf '%s\n' invocation >> "$tmp/find.log"; command find "$@"; }
find_dirs create > "$tmp/create"
[[ $(wc -l < "$tmp/find.log") == 3 ]]
printf '%s\n' "$tmp/tree/a" "$tmp/tree/a/child" "$tmp/tree/a/child/grandchild" \
    "$tmp/tree/b" "$tmp/tree/b/deep" "$tmp/tree/b/deep/leaf" \
    "$tmp/tree/b/.hidden" "$tmp/tree/b/ignored-sibling" \
    "$tmp/tree/weird [*] dir" "$tmp/tree/weird [*] dir/child" | sort > "$tmp/expected"
sort "$tmp/create" > "$tmp/actual"
diff -u "$tmp/expected" "$tmp/actual"
TMUX='' session_candidates < "$tmp/create" > "$tmp/normal"
grep -Fx '[TMUX] a' "$tmp/normal" >/dev/null
grep -Fx '[TMUX] outside' "$tmp/normal" >/dev/null
! grep -Fx "$tmp/tree/a" "$tmp/normal" >/dev/null
# Suppressing the current session must not remove its path from creation mode.
tmux() { printf '%s\n' '$1'; }
TMUX=test session_candidates < "$tmp/create" > "$tmp/current"
! grep -Fx '[TMUX] a' "$tmp/current" >/dev/null
grep -Fx "$tmp/tree/a" "$tmp/create" >/dev/null

# Empty and missing-only configurations must not accidentally scan cwd.
: > "$tmp/find.log"
TS_SEARCH_PATHS=()
[[ -z $(find_dirs create) ]]
TS_SEARCH_PATHS=("$tmp/missing")
[[ -z $(find_dirs create) ]]
[[ ! -s "$tmp/find.log" ]]

# Picker preparation enumerates only once, derives normal candidates from the
# exact same snapshot, and cleans up temporary files on cancellation.
(
    find_dirs() {
        [[ ${1:-} == create ]] || return 1
        printf 'scan\n' >> "$tmp/scans"
        printf '%s\n' "$tmp/tree/a" "$tmp/tree/b"
    }
    mktemp() { mkdir "$tmp/picker"; printf '%s\n' "$tmp/picker"; }
    fzf() {
        grep -Fx '[TMUX] a' "$tmp/picker/input" >/dev/null || return 1
        if grep -Fx "$tmp/tree/a" "$tmp/picker/input" >/dev/null; then return 1; fi
        grep -Fx "$tmp/tree/b" "$tmp/picker/input" >/dev/null || return 1
        grep -Fx "$tmp/tree/a" "$tmp/picker/input.create" >/dev/null || return 1
        return 130
    }
    status=0
    TMUX='' fzf_select || status=$?
    [[ $status == 130 ]]
    [[ $(wc -l < "$tmp/scans") == 1 ]]
    [[ ! -e "$tmp/picker" ]]
)
printf 'Discovery tests passed\n'
