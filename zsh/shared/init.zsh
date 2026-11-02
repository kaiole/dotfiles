# Portable interactive preferences shared by host and ROS shells.
# Callers own PATH, Python/ROS setup, credentials, history/cache locations,
# Oh My Zsh's update policy, and environment-specific commands/keybindings.
export EDITOR=nvim
export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_THEME=""
plugins=(git)

# Resolve relative to this file, not $HOME (which differs inside Distrobox).
typeset _shared_zsh_themes="${${(%):-%x}:A:h:h}/themes"
if [[ -r "$_shared_zsh_themes/.dircolors" ]]; then
  if (( $+commands[dircolors] )); then
    eval "$(dircolors -b "$_shared_zsh_themes/.dircolors")"
  elif (( $+commands[gdircolors] )); then
    eval "$(gdircolors -b "$_shared_zsh_themes/.dircolors")"
  fi
fi
[[ -r "$_shared_zsh_themes/colors.zsh" ]] && source "$_shared_zsh_themes/colors.zsh"

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  print -u2 -- "Zsh: Oh My Zsh is missing at $ZSH (Git aliases/theme unavailable)."
  autoload -Uz compinit
  # Explicit dump path: the default is $ZDOTDIR, which is this repo for ROS shells.
  typeset _shared_zcompdump="${ZSH_COMPDUMP:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-$ZSH_VERSION}"
  mkdir -p -- "${_shared_zcompdump:h}"
  compinit -d "$_shared_zcompdump"
  unset _shared_zcompdump
fi
if (( $+functions[git_prompt_info] )) && [[ -r "$_shared_zsh_themes/zsh.zsh-theme" ]]; then
  source "$_shared_zsh_themes/zsh.zsh-theme"
fi
unset _shared_zsh_themes

# Keep the newest occurrence of each command; skip duplicates during search.
setopt HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS

alias tree="tree -Ia 'build|target|.cargo|node_modules|dist|.git|.cache|.venv|venv|__pycache__|*.pyc|*.egg-info|.pytest_cache|.mypy_cache|.ruff_cache|.tox|.nox|htmlcov|.coverage|.coverage.*|.ipynb_checkpoints'"
# GNU ls on Linux; avoid imposing unsupported GNU flags on macOS.
if [[ "$OSTYPE" == linux* ]]; then
  alias ls='ls -CA --color=auto'
else
  alias ls='ls -CAG'
fi
