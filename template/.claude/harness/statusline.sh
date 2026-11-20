#!/bin/bash
# Claude Code 상태 표시줄 (하네스 템플릿 소유, .claude/settings.json의 statusLine이 실행한다)
# 표시 항목: 모델·effort, 컨텍스트 사용률과 토큰 수, 5시간·7일 사용 한도와 초기화까지 남은 시간
# 필요 도구: jq. 사용 한도 값은 구독 계정에서만 들어오며, 값이 없으면 해당 줄을 생략한다.
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
