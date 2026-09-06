cfmt() {
  if (( $# == 0 )); then
    echo "Usage: cfmt <path> [...]" >&2
    return 1
  fi
  
  if ! command -v clang-format >/dev/null 2>&1; then
    echo "cfmt: clang-format not found" >&2
    return 127
  fi
  
  local target
  for target in "$@"; do
    if [[ ! -e "$target" ]]; then
      echo "cfmt: not found: $target" >&2
      return 1
    fi
  
    if [[ ! -d "$target" && ! -f "$target" ]]; then
      echo "cfmt: not a file or directory: $target" >&2
      return 1
    fi
  
    if [[ -f "$target" ]]; then
      case "$target" in
        *.c|*.h|*.cc|*.hh|*.cpp|*.hpp|*.cxx|*.hxx|*.m|*.mm) ;;
        *)
          echo "cfmt: unsupported file type: $target" >&2
          return 1
          ;;
      esac
    fi
  done
  
  for target in "$@"; do
    if [[ -f "$target" ]]; then
      clang-format -i -- "$target" || return 1
      continue
    fi
  
    find "$target" \
      \( -type d \( \
        -name .git -o \
        -name build -o \
        -name vendor -o \
        -name third_party -o \
        -name node_modules \
      \) -prune \) -o \
      \( -type f \( \
        -name '*.c' -o -name '*.h' -o \
        -name '*.cc' -o -name '*.hh' -o \
        -name '*.cpp' -o -name '*.hpp' -o \
        -name '*.cxx' -o -name '*.hxx' -o \
        -name '*.m' -o -name '*.mm' \
      \) -exec clang-format -i -- {} + \) || return 1
  done
}

tidy() {
  if (( $# == 0 )); then
    echo "Usage: tidy <path> [...]" >&2
    return 1
  fi
  
  if ! command -v clang-tidy >/dev/null 2>&1; then
    echo "tidy: clang-tidy not found" >&2
    return 127
  fi
  
  local target
  for target in "$@"; do
    if [[ ! -e "$target" ]]; then
      echo "tidy: not found: $target" >&2
      return 1
    fi
  
    if [[ ! -d "$target" && ! -f "$target" ]]; then
      echo "tidy: not a file or directory: $target" >&2
      return 1
    fi
  
    if [[ -f "$target" ]]; then
      case "$target" in
        *.c|*.h|*.cc|*.hh|*.cpp|*.hpp|*.cxx|*.hxx|*.m|*.mm) ;;
        *)
          echo "tidy: unsupported file type: $target" >&2
          return 1
          ;;
      esac
    fi
  done
  
  local target_dir compilation_dir project_dir search_dir header_filter exclude_header_filter
  for target in "$@"; do
    if [[ -d "$target" ]]; then
      target_dir="${target:A}"
    else
      target_dir="${target:A:h}"
    fi
  
    compilation_dir=""
    search_dir="$target_dir"
    while true; do
      if [[ -f "$search_dir/compile_commands.json" ]]; then
        compilation_dir="$search_dir"
        break
      fi
      if [[ -f "$search_dir/build/compile_commands.json" ]]; then
        compilation_dir="$search_dir/build"
        break
      fi
      [[ "$search_dir" == / ]] && break
      search_dir="${search_dir:h}"
    done
  
    if [[ -z "$compilation_dir" ]]; then
      echo "tidy: no compile_commands.json found for $target" >&2
      echo "tidy: configure CMake with -DCMAKE_EXPORT_COMPILE_COMMANDS=ON" >&2
      return 1
    fi
  
    if [[ "${compilation_dir:t}" == build ]]; then
      project_dir="${compilation_dir:h}"
    else
      project_dir="$compilation_dir"
    fi
    header_filter="^${project_dir}/"
    exclude_header_filter="^${project_dir}/(build|vendor|third_party|node_modules)/"
  
    if [[ -f "$target" ]]; then
      clang-tidy -p "$compilation_dir" --fix \
        --header-filter="$header_filter" \
        --exclude-header-filter="$exclude_header_filter" \
        "${target:A}" || return 1
      continue
    fi
  
    find "${target:A}" \
      \( -type d \( \
        -name .git -o \
        -name build -o \
        -name vendor -o \
        -name third_party -o \
        -name node_modules \
      \) -prune \) -o \
      \( -type f \( \
        -name '*.c' -o -name '*.cc' -o \
        -name '*.cpp' -o -name '*.cxx' -o \
        -name '*.m' -o -name '*.mm' \
      \) -exec clang-tidy -p "$compilation_dir" --fix \
        --header-filter="$header_filter" \
        --exclude-header-filter="$exclude_header_filter" {} + \) || return 1
  done
}
