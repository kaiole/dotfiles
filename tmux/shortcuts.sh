#!/usr/bin/env bash
# Read-only content for the prefix-b popup; tmux also handles Esc and Ctrl-C.
printf '\033[?25l'
trap 'printf "\033[?25h"' EXIT

printf '%s\n' \
  ' Start / end of line     Ctrl-A / Ctrl-E' \
  ' Back / forward word     Alt-B / Alt-F' \
  '' \
  ' Cut previous word       Ctrl-W' \
  ' Cut whole line          Ctrl-U' \
  ' Cut to end              Ctrl-K' \
  ' Paste last cut          Ctrl-Y' \
  '' \
  ' Undo                    Ctrl-X then Ctrl-U'
# No final newline: it would scroll the first row away and leave a blank bottom row.
printf '%s' ' Previous last argument  Alt-.'

while IFS= read -rsn1 key; do
  case "$key" in
    q|$'\e') break ;;
  esac
done
