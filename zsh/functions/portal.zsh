portal_should_ignore() {
  case "$1" in
    .DS_Store|*/.DS_Store|.tmux-sessionizer|*/.tmux-sessionizer)
      return 0
      ;;
    node_modules|*/node_modules|*/node_modules/*)
      return 0
      ;;
    .cache|*/.cache|*/.cache/*)
      return 0
      ;;
    build|*/build|*/build/*)
      return 0
      ;;
    dist|*/dist|*/dist/*)
      return 0
      ;;
    .next|*/.next|*/.next/*)
      return 0
      ;;
    .claude|*/.claude|*/.claude/*)
      return 0
      ;;
    .obsidian/workspace.json|*/.obsidian/workspace.json)
      return 0
      ;;
    .obsidian/workspace-mobile.json|*/.obsidian/workspace-mobile.json)
      return 0
      ;;
    .obsidian/cache|*/.obsidian/cache|*/.obsidian/cache/*)
      return 0
      ;;
    .obsidian/graph.json|*/.obsidian/graph.json)
      return 0
      ;;
    .obsidian/backlink-cache.json|*/.obsidian/backlink-cache.json)
      return 0
      ;;
  esac
  
  return 1
}

pcpy() {
  if [ "$#" -eq 0 ]; then
    echo "Usage: pcpy <path> [...]"
    return 1
  fi
  
  mkdir -p ~/portal || return 1
  local src
  for src in "$@"; do
    if [ ! -e "$src" ]; then
      echo "pcpy: not found: $src"
      return 1
    fi
  
    if portal_should_ignore "$src"; then
      echo "pcpy: skipped ignored path: $src"
      continue
    fi
  
    cp -R -- "$src" ~/portal/ || return 1
  done
}

pmv() {
  if [ "$#" -eq 0 ]; then
    echo "Usage: pmv <path> [...]"
    return 1
  fi
  
  mkdir -p ~/portal || return 1
  local src
  for src in "$@"; do
    if [ ! -e "$src" ]; then
      echo "pmv: not found: $src"
      return 1
    fi
  
    if portal_should_ignore "$src"; then
      echo "pmv: skipped ignored path: $src"
      continue
    fi
  
    mv -- "$src" ~/portal/ || return 1
  done
}

pclear() {
  mkdir -p ~/portal || return 1
  rm -rf -- ~/portal/*(N) ~/portal/.[!.]*(N) ~/portal/..?*(N)
}
