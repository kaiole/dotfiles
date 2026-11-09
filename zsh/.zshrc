# Host-only toolchain setup. Never sourced by the ROS container.
export PATH="$HOME/.cargo/bin:$PATH"
# OCaml: PATH and env for the default opam switch (ocaml, dune, ocamllsp).
[[ -r ~/.opam/opam-init/init.zsh ]] && source ~/.opam/opam-init/init.zsh >/dev/null 2>&1

export ZSH="$HOME/.oh-my-zsh"
zstyle ':omz:update' mode auto
source "${${(%):-%x}:A:h}/shared/init.zsh"

# Host-only secrets, completions, commands, and sessionizer entry.
[[ -r ~/.local/state/pi/secrets.zsh ]] && source ~/.local/state/pi/secrets.zsh
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
alias qpi="pi --no-session --provider openai-codex --model gpt-6.1-sol --thinking low"
alias wb="g++ -std=c++20 -O2 -Wall main.cpp -o test"
# Run directly instead of inserting a command into the current input buffer.
_tmux_sessionizer() {
  zle -I
  command tmux-sessionizer </dev/tty
  zle reset-prompt
}
zle -N _tmux_sessionizer
bindkey '^F' _tmux_sessionizer
