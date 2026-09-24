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
