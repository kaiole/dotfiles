# Nested shells re-run every prepend; keep only the first (frontmost) occurrence.
typeset -U path PATH

# User executables must also be available to non-interactive launchers.
export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
export PATH="$HOME/.pi/agent/bin:$PATH"

# Toolchains too: a git hook run over ssh (`ssh host 'git pull'`) starts
# scripts/install in a shell that reads only this file, and it needs cargo and
# nvim. Homebrew is macOS-only; login shells get the rest from `brew shellenv`.
[[ -d /opt/homebrew/bin ]] && export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
