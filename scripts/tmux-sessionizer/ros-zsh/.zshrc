# Loaded only by ros-tmux through ZDOTDIR. Do not source the host's .zshrc.
[[ -r "$HOME/.zshrc" ]] && source "$HOME/.zshrc"

# One private runtime directory per pane, shared through Distrobox's /tmp mount.
# Atomic replacement keeps host reads consistent. Never evaluate file contents.
_ros_tmux_report_cwd() {
    [[ -n "$ROS_TMUX_STATE" && -d "$ROS_TMUX_STATE" ]] || return 0
    if ! { printf '%s\0' "$PWD" > "$ROS_TMUX_STATE/cwd.tmp" &&
           command mv -f -- "$ROS_TMUX_STATE/cwd.tmp" "$ROS_TMUX_STATE/cwd"; }; then
        print -u2 -- 'ros-tmux: directory tracking failed; new panes may use the previous directory.'
    fi
    return 0
}
_ros_tmux_prompt() {
    _ros_tmux_report_cwd
    [[ -d "$ROS_TMUX_STATE" ]] && : > "$ROS_TMUX_STATE/prompt"
    # A Neovim that crashed or was suspended no longer owns the foreground.
    command rm -f -- "$ROS_TMUX_STATE/nvim-normal"
    return 0
}
_ros_tmux_preexec() {
    command rm -f -- "$ROS_TMUX_STATE/prompt"
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _ros_tmux_report_cwd
# Also report on return from a nested shell, whose cwd may differ from ours.
add-zsh-hook precmd _ros_tmux_prompt
add-zsh-hook preexec _ros_tmux_preexec
