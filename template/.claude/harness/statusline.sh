#!/bin/bash
# Claude Code 상태 표시줄 (하네스 템플릿 소유, .claude/settings.json의 statusLine이 실행한다)
# 표시 항목: 설치된 플러그인 모드(Ponytail, Caveman), 모델·effort, 컨텍스트 사용률과 토큰 수, 5시간·7일 사용 한도와 초기화까지 남은 시간
# 필요 도구: jq. 사용 한도 값은 구독 계정에서만 들어오며, 값이 없으면 해당 줄을 생략한다.
#   ● Ponytail ON ██░ FULL (2/3) | ● Caveman ON █░░ CAVEMAN (1/3)   ← 설치된 플러그인만
#   ● Model      Opus 5.5   Effort ■■■□□ HIGH (3/5)
#   ● 컨텍스트   ██░░░░  10%  103K / 1.0M 토큰
#   ● 5시간 한도 ██░░░░  25%  10분 후 초기화
#   ● 7일 한도   ░░░░░░   3%  6일 21시간 후 초기화
input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "상태 표시줄: jq가 필요하다 (brew install jq)"
  exit 0
fi

R=$'\033[0m'
B=$'\033[1m'
DIM=$'\033[2m'
GRAY=$'\033[38;5;245m'
EMPTY=$'\033[38;5;237m'
ORANGE=$'\033[38;5;209m'
CYAN=$'\033[38;5;80m'
BLUE=$'\033[38;5;69m'
PURPLE=$'\033[38;5;105m'
YELLOW=$'\033[38;5;221m'
RED=$'\033[38;5;203m'
BAR_W=16

j() { printf '%s' "$input" | jq -r "$1 // empty"; }

# 사용률에 따라 색 결정: 50% 미만은 항목 고유색, 50~79%는 노랑, 80% 이상은 빨강
fill_color() {
  if [ "$1" -ge 80 ]; then printf '%s' "$RED"
  elif [ "$1" -ge 50 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$2"
  fi
}

# $1: 사용률(정수) $2: 채움색 $3: 너비
bar() {
  local pct=$1 color=$2 width=$3 filled i out=""
  [ "$pct" -gt 100 ] && pct=100
  [ "$pct" -lt 0 ] && pct=0
  filled=$(( (pct * width + 99) / 100 ))
  [ "$pct" -eq 0 ] && filled=0
  out+="$color"
  for ((i = 0; i < filled; i++)); do out+="█"; done
  out+="$EMPTY"
  for ((i = filled; i < width; i++)); do out+="█"; done
  printf '%s%s' "$out" "$R"
}

fmt_tokens() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then
    printf '%d.%dM' $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
  elif [ "$n" -ge 1000 ]; then
    printf '%dK' $(( n / 1000 ))
  else
    printf '%d' "$n"
  fi
}

fmt_reset() {
  local diff=$(( $1 - $(date +%s) )) d h m
  [ "$diff" -le 0 ] && { printf '곧 초기화'; return; }
  d=$(( diff / 86400 )); h=$(( (diff % 86400) / 3600 )); m=$(( (diff % 3600) / 60 ))
  if [ "$d" -gt 0 ]; then printf '%d일 %d시간 후 초기화' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%d시간 %d분 후 초기화' "$h" "$m"
  else printf '%d분 후 초기화' "$(( m > 0 ? m : 1 ))"
  fi
}

# $1: 점 색 $2: 라벨(10칸 맞춤 완료) $3: 사용률 $4: 고유색 $5: 뒤 설명
row() {
  local pct
  pct=$(printf '%.0f' "$3")
  printf '%s●%s %s%s%s  %s  %s%3d%%%s  %s%s%s\n' \
    "$1" "$R" "$B" "$2" "$R" \
    "$(bar "$pct" "$(fill_color "$pct" "$4")" "$BAR_W")" \
    "$B" "$pct" "$R" "$GRAY" "$5" "$R"
}

# ── 0줄: 플러그인 모드 (Ponytail, Caveman) ──
# 플러그인이 남긴 모드 파일을 읽는다. 링크 파일은 거부하고, 내용은 64바이트·[a-z0-9-]만 남긴다.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
read_mode() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 0
  head -c 64 "$1" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-'
}
# $1: 점·바 색 $2: 이름 $3: 표시 단계(빈 값이면 OFF) $4: 단계 번호(0이면 단계 바 생략)
plugin_badge() {
  local color=$1 name=$2 label=$3 lv=$4 i cells=""
  if [ -z "$label" ]; then
    printf '%s●%s %s%s%s %sOFF%s' "$GRAY" "$R" "$B" "$name" "$R" "$GRAY" "$R"
    return
  fi
  printf '%s●%s %s%s%s %sON%s' "$color" "$R" "$B" "$name" "$R" "$color" "$R"
  if [ "$lv" -gt 0 ]; then
    for ((i = 1; i <= 3; i++)); do
      if [ "$i" -le "$lv" ]; then cells+="${color}█"; else cells+="${EMPTY}█"; fi
    done
    printf ' %s%s %s%s%s %s(%d/3)%s' "$cells" "$R" "$B" "$label" "$R" "$GRAY" "$lv" "$R"
  else
    printf ' %s%s%s' "$B" "$label" "$R"
  fi
}

pt_mode=$(read_mode "$CFG/.ponytail-active")
case "$pt_mode" in
  lite) pt_label=LITE; pt_lv=1 ;;
  ''|full) pt_label=FULL; pt_lv=2 ;;
  ultra) pt_label=ULTRA; pt_lv=3 ;;
  *) pt_label=$(printf '%s' "$pt_mode" | tr '[:lower:]' '[:upper:]'); pt_lv=0 ;;
esac
[ -f "$CFG/.ponytail-active" ] || pt_label=""

sid=$(j '.session_id')
case "$sid" in ''|*[!A-Za-z0-9_-]*) sid="" ;; esac
cv_flag="$CFG/.caveman-active"
[ -n "$sid" ] && [ -f "$CFG/.caveman-sessions/$sid.mode" ] && cv_flag="$CFG/.caveman-sessions/$sid.mode"
cv_mode=$(read_mode "$cv_flag")
case "$cv_mode" in
  caveman|lite|full) cv_label=CAVEMAN; cv_lv=1 ;;
  ultracave|ultra) cv_label=ULTRA; cv_lv=2 ;;
  megacave|wenyan|wenyan-*) cv_label=MEGA; cv_lv=3 ;;
  commit|review|compress) cv_label=$(printf '%s' "$cv_mode" | tr '[:lower:]' '[:upper:]'); cv_lv=0 ;;
  *) cv_label="" ;;
esac

# 설치된 플러그인만 표시한다. 둘 다 없으면 이 줄을 생략한다.
plugin_installed() {
  local f="$CFG/plugins/installed_plugins.json"
  [ -f "$f" ] && jq -e --arg p "$1@" '.plugins // {} | keys | any(startswith($p))' "$f" >/dev/null 2>&1
}
badges=()
plugin_installed ponytail && badges+=("$(plugin_badge $'\033[38;5;108m' Ponytail "$pt_label" "${pt_lv:-0}")")
plugin_installed caveman && badges+=("$(plugin_badge $'\033[38;5;172m' Caveman "$cv_label" "${cv_lv:-0}")")
if [ "${#badges[@]}" -gt 0 ]; then
  plugin_line="${badges[0]}"
  [ "${#badges[@]}" -gt 1 ] && plugin_line+=" ${GRAY}|${R} ${badges[1]}"
  printf '%s\n\n' "$plugin_line"
fi

# ── 1줄: 모델과 effort ──
model=$(j '.model.display_name'); model=${model:-Claude}
effort=$(j '.effort.level')
line="${ORANGE}●${R} ${B}Model     ${R}  ${B}${model}${R}"
if [ -n "$effort" ]; then
  case "$effort" in
    low) lv=1 ;; medium) lv=2 ;; high) lv=3 ;; xhigh) lv=4 ;; max) lv=5 ;; *) lv=0 ;;
  esac
  up=$(printf '%s' "$effort" | tr '[:lower:]' '[:upper:]')
  line+="   ${GRAY}Effort${R} $(bar $(( lv * 20 )) "$PURPLE" 5) ${B}${up}${R} ${GRAY}(${lv}/5)${R}"
fi
printf '%s\n' "$line"

# ── 2줄: 컨텍스트 ──
ctx=$(j '.context_window.used_percentage')
size=$(j '.context_window.context_window_size')
used=$(printf '%s' "$input" | jq -r '.context_window.current_usage
  | if . == null then empty else (.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens) end')
if [ -n "$ctx" ]; then
  detail=""
  [ -n "$used" ] && [ -n "$size" ] && detail="$(fmt_tokens "$used") / $(fmt_tokens "$size") 토큰"
  row "$CYAN" "컨텍스트  " "$ctx" "$CYAN" "$detail"
else
  printf '%s●%s %s컨텍스트  %s  %s--%s\n' "$CYAN" "$R" "$B" "$R" "$GRAY" "$R"
fi

# ── 3·4줄: 사용 한도 (구독 계정에서만 값이 온다) ──
five=$(j '.rate_limits.five_hour.used_percentage')
five_reset=$(j '.rate_limits.five_hour.resets_at')
week=$(j '.rate_limits.seven_day.used_percentage')
week_reset=$(j '.rate_limits.seven_day.resets_at')
[ -n "$five" ] && row "$BLUE" "5시간 한도" "$five" "$BLUE" "$([ -n "$five_reset" ] && fmt_reset "$five_reset")"
[ -n "$week" ] && row "$PURPLE" "7일 한도  " "$week" "$PURPLE" "$([ -n "$week_reset" ] && fmt_reset "$week_reset")"
exit 0
