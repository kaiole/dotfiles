#!/usr/bin/env bash
# Deterministic Ctrl-F dispatch for ROS panes; no real tmux or container touched.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/helper" "$work/state"
# picker execs the sessionizer next to ros-tmux; substitute a recorder there.
cp -- "$root/ros-tmux" "$work/helper/ros-tmux"
printf '#!/usr/bin/env bash\necho sessionizer >> "%s/log"\n' "$work" > "$work/helper/tmux-sessionizer"
cat > "$work/bin/tmux" <<MOCK
#!/usr/bin/env bash
case "\$*" in
    *'show-options'*'@ros_state'*) echo '$work/state' ;;
    'send-keys -t %1 C-f') echo forwarded >> '$work/log' ;;
    *) echo "unexpected tmux \$*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$work/bin/tmux" "$work/helper/tmux-sessionizer"
export PATH="$work/bin:$PATH"

dispatch() {
    rm -f -- "$work/log"
    "$work/helper/ros-tmux" picker %1
    cat "$work/log"
}
# Foreground program (no prompt, no Neovim normal mode): the key is forwarded.
[[ $(dispatch) == forwarded ]]
# Zsh prompt.
: > "$work/state/prompt"
[[ $(dispatch) == sessionizer ]]
rm -- "$work/state/prompt"
# Neovim in normal mode, whose own Ctrl-F cannot reach the host script.
: > "$work/state/nvim-normal"
[[ $(dispatch) == sessionizer ]]
rm -- "$work/state/nvim-normal"
[[ $(dispatch) == forwarded ]]
# The Zsh prompt hook clears a flag left by a crashed or suspended Neovim.
: > "$work/state/nvim-normal"
# HOME isolates the hook file from the real ~/.zshrc it would otherwise source.
HOME="$work" ROS_TMUX_STATE="$work/state" zsh -f -c "
    source '$root/ros-zsh/.zshrc' 2>/dev/null
    _ros_tmux_prompt"
[[ ! -e "$work/state/nvim-normal" && -e "$work/state/prompt" ]]
printf 'ROS picker tests passed\n'
