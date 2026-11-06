#!/usr/bin/env bash
# Read-only content for the prefix-b floating pane; prefix-b closes it.
printf '\033[?25l'
# Keys typed after focusing it by accident stay invisible instead of echoing.
stty -echo

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

exec sleep infinity
