scratch() {
  if (( $# > 1 )); then
    echo "Usage: scratch [file]" >&2
    return 1
  fi
  
  local scratch_dir="/tmp/scratch-${USER:-$(id -un)}"
  mkdir -p -- "$scratch_dir" || return 1
  
  local file suffix
  if (( $# == 0 )); then
    file="$scratch_dir/$(date +%Y%m%d-%H%M%S).md"
    suffix=1
    while [[ -e "$file" ]]; do
      file="${file%.md}-$suffix.md"
      (( suffix++ ))
    done
    : > "$file" || return 1
  else
    if [[ "$1" == */* || "$1" != *.md ]]; then
      echo "scratch: invalid file: $1" >&2
      return 1
    fi
    file="$scratch_dir/$1"
    if [[ ! -f "$file" ]]; then
      echo "scratch: not found: $1" >&2
      return 1
    fi
  fi
  
  command "${EDITOR:-nvim}" -- "$file"
}

_scratch() {
  local scratch_dir="/tmp/scratch-${USER:-$(id -un)}"
  local file
  local -a files
  
  for file in "$scratch_dir"/*.md(NOm); do
    files+=("${file:t}")
  done
  _describe 'scratch file' files
}

compdef _scratch scratch
