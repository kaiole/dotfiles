# ROS-only initialization. The container's ~/.zshrc sources this file.
# Do not load the host's .zshenv, .zshrc, Python initialization, or secrets.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
unset PYENV_ROOT PYENV_VERSION PYTHONHOME PYTHONPATH VIRTUAL_ENV

# Software, history, and mutable caches belong to the container's own home.
export ZSH="$HOME/.oh-my-zsh"
export ZSH_CUSTOM="$ZSH/custom"
export ZSH_CACHE_DIR="$HOME/.cache/oh-my-zsh"
ZSH_COMPDUMP="$HOME/.cache/zsh/zcompdump-$ZSH_VERSION"
HISTFILE="$HOME/.zsh_history"
mkdir -p -- "${ZSH_COMPDUMP:h}" "$ZSH_CACHE_DIR"
# Avoid background upgrades during pane startup; update this independent clone
# explicitly with `omz update` when wanted.
zstyle ':omz:update' mode disabled

source "${${(%):-%x}:A:h}/shared/init.zsh"
# The micro-ROS overlay sources /opt/ros/jazzy itself; sourcing both doubled
# the cost (~185 ms per pane) for an identical environment.
if [[ -r /uros_ws/install/setup.zsh ]]; then
  source /uros_ws/install/setup.zsh
elif [[ -r /opt/ros/jazzy/setup.zsh ]]; then
  source /opt/ros/jazzy/setup.zsh
fi
# Workspace overlays remain explicit: source install/setup.zsh after building.
# Sessionizer Ctrl-F/directory tracking is owned by the ros-tmux wrapper, not
# imported from the host shell. Direct distrobox shells retain normal Ctrl-F.
true
