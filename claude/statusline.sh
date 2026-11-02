#!/usr/bin/env bash
# Claude Code status line:
#   model • effort | ctx% [used/size] | 5h% [󰜉 reset] | 7d% [󰜉 reset]      dir
# Rate-limit segments only appear when Claude Code provides them (subscription
# plans); otherwise session cost is shown instead.
#
# This runs on every render, so one jq call extracts and formats every field.
# Fields are joined with \x1f, not IFS whitespace, so empty ones survive `read`.
IFS=$'\x1f' read -r model model_id effort pct used size p5 t5 p7 t7 cost dir < <(jq -r '
  def human: if . < 1000 then "\(floor)"
    elif . < 1000000 then "\((. / 100 | round) / 10)k"
    else "\((. / 100000 | round) / 10)m" end;
  def reset($f): if . == null then "" else tonumber | localtime | strflocaltime($f) | ascii_downcase end;
  def pct: if . == null then "" else floor end;
  (.context_window.context_window_size // 200000) as $size
  | ((.context_window.current_usage // {}) as $u
     | ($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) as $used
  | [ .model.display_name // .model.id // "?",
      .model.id // "",
      (.effort | if type == "object" then .level else . end) // "",
      (if $size > 0 then $used * 100 / $size | floor else 0 end),
      ($used | human), ($size | human),
      (.rate_limits.five_hour.used_percentage | pct),
      (.rate_limits.five_hour.resets_at | reset("%I:%M%p") | sub("^0"; "")),
      (.rate_limits.seven_day.used_percentage | pct),
      (.rate_limits.seven_day.resets_at | reset("%m/%d")),
      .cost.total_cost_usd // 0,
      .workspace.project_dir // .workspace.current_dir // .cwd // ""
    ] | map(tostring) | join("\u001f")')

d=$'\e[2m' r=$'\e[0m'
sep=" ${d}|${r} "

color() { # pct -> colored pct
  local c
  if   (( $1 < 50 )); then c=$'\e[32m'
  elif (( $1 < 80 )); then c=$'\e[33m'
  else                     c=$'\e[31m'; fi
  printf '%s%d%%%s' "$c" "$1" "$r"
}

# model • effort
if [[ -z $effort && -n $model_id ]]; then
  effort=$(jq -r --arg m "$model_id" \
    '.modelSettings[$m].effortLevel // .effortLevel // empty' \
    ~/.claude/settings.json 2>/dev/null)
fi
out="${model:-?}"
[[ -n $effort ]] && out+=" ${d}•${r} $effort"

# context
out+="${sep}$(color "${pct:-0}") ${d}[${r}${used:-0}/${size:-200k}${d}]${r}"

# usage: rate limits if present, else cost
icons=0
rl() { # pct reset
  [[ -z $1 ]] && return 1
  out+="${sep}$(color "$1")"
  if [[ -n $2 ]]; then
    out+=" ${d}[${r}󰜉 $2${d}]${r}"
    icons=$((icons + 1))
  fi
  return 0
}
shown=0
rl "$p5" "$t5" && shown=1
rl "$p7" "$t7" && shown=1
if (( ! shown )); then
  out+="${sep}\$$(printf '%.2f' "${cost:-0}")"
fi

# right-aligned dir
[[ $dir == "$HOME" || $dir == "$HOME"/* ]] && dir="~${dir#"$HOME"}"
shopt -s extglob
plain=${out//$'\e['*([0-9;])m/}
cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 0)}
# Claude Code indents the line 2 cols on each side; nerd-font icons render 2 cols wide
pad=$(( cols - ${#plain} - icons - ${#dir} - 4 ))
(( pad < 2 )) && pad=2
printf '%s%*s%s%s%s' "$out" "$pad" "" "$d" "$dir" "$r"
