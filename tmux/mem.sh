#!/bin/sh
# The mem popup's command (prefix N in tmux.conf): attach to the mem session,
# creating it if needed with nvim on ~/vault/mem.md and a shell window to
# run an agent on the vault, then clear @mem_client and @mem_session so the
# window-resized hook stops reopening the popup. Quitting nvim kills the
# session, shell window included. The session turns detach-on-destroy back on, or
# that would move the popup's client to another session instead of closing it.
cd "$HOME/vault" || exit 1
if ! tmux has-session -t =mem 2>/dev/null; then
  tmux new-session -d -s mem -n vim 'nvim mem.md; tmux kill-session -t "$TMUX_PANE"'
  tmux set-option -t mem: detach-on-destroy on
  tmux new-window -d -t mem: -n agent
fi
TMUX= tmux attach-session -t =mem
tmux set -su @mem_client \; set -su @mem_session
