#!/usr/bin/env bash
# Claude Code status line:
#   model • effort | ctx% [used/size] | 5h% [󰜉 reset] | 7d% [󰜉 reset]      dir
# Rate-limit segments only appear when Claude Code provides them (subscription
# plans); otherwise session cost is shown instead.
input=$(cat)
j() { jq -r "$1" <<<"$input"; }

d=$'\e[2m' r=$'\e[0m'
sep=" ${d}|${r} "

human() {
  awk -v n="$1" 'BEGIN {
    if (n < 1000) printf "%d", n
    else if (n < 1000000) printf "%.1fk", n/1000
    else printf "%.1fm", n/1000000
  }' | sed 's/\.0\([km]\)$/\1/'
}

color() { # pct -> colored pct
  local c
  if   (( $1 < 50 )); then c=$'\e[32m'
  elif (( $1 < 80 )); then c=$'\e[33m'
  else                     c=$'\e[31m'; fi
  printf '%s%d%%%s' "$c" "$1" "$r"
}

# model • effort
model=$(j '.model.display_name // .model.id // "?"')
model_id=$(j '.model.id // ""')
effort=$(j '.effort.level // .effort // empty' 2>/dev/null)
if [[ -z $effort || $effort == null ]]; then
  effort=$(jq -r --arg m "$model_id" \
    '.modelSettings[$m].effortLevel // .effortLevel // empty' \
    ~/.claude/settings.json 2>/dev/null)
fi
out="$model"
[[ -n $effort ]] && out+=" ${d}•${r} $effort"

# context
size=$(j '.context_window.context_window_size // 200000')
used=$(j '(.context_window.current_usage // {}) as $u
  | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0))')
pct=$(( size > 0 ? used * 100 / size : 0 ))
out+="${sep}$(color $pct) ${d}[${r}$(human "$used")/$(human "$size")${d}]${r}"

# usage: rate limits if present, else cost
rl() { # key date-format
  local p t
  p=$(j ".rate_limits.$1.used_percentage // empty")
  [[ -z $p ]] && return 1
  t=$(j ".rate_limits.$1.resets_at // empty")
  out+="${sep}$(color "${p%.*}")"
  [[ -n $t ]] && out+=" ${d}[${r}󰜉 $( (date -d "@$t" +"$2" 2>/dev/null || date -r "$t" +"$2") | tr 'APM' 'apm')${d}]${r}"
}
shown=0
rl five_hour '%-I:%M%p' && shown=1
rl seven_day '%m/%d' && shown=1
if (( ! shown )); then
  out+="${sep}\$$(printf '%.2f' "$(j '.cost.total_cost_usd // 0')")"
fi

# right-aligned dir
dir=$(j '.workspace.project_dir // .workspace.current_dir // .cwd // ""')
dir=${dir/#$HOME/\~}
plain=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$out")
cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 0)}
# Claude Code indents the line 2 cols on each side; nerd-font icons render 2 cols wide
icons=$(grep -o '󰜉' <<<"$plain" | wc -l)
pad=$(( cols - ${#plain} - icons - ${#dir} - 4 ))
(( pad < 2 )) && pad=2
printf '%s%*s%s%s%s' "$out" "$pad" "" "$d" "$dir" "$r"
