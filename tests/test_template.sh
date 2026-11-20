#!/usr/bin/env bash
# 템플릿 렌더링 테스트: 임시 디렉터리에 새 프로젝트를 만들고 하네스 검사가 통과하는지 확인한다.
#
# 사용법: tests/test_template.sh
# 필요 도구: copier, git, python3

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DEST="$WORK/demo"
FAILED=0

ok()   { printf '  [통과] %s\n' "$1"; }
fail() { printf '  [실패] %s\n' "$1"; FAILED=1; }

echo "== 템플릿 렌더링 =="
copier copy --quiet --defaults --vcs-ref=HEAD \
  --data project_name=demo --data project_summary="테스트용 프로젝트" \
  "$ROOT" "$DEST" 2>/dev/null
ok "copier copy"

cd "$DEST"

for f in CLAUDE.md .copier-answers.yml .claude/settings.json .claude/harness/WORKFLOW.md \
         .claude/agents/implementer.md .claude/agents/code-reviewer.md \
         .claude/hooks/reviewer_bash_guard.py scripts/harness-check.sh scripts/check.sh \
         tests/harness/test_reviewer_bash_guard.py .github/workflows/ci.yml \
         .github/pull_request_template.md .gitignore .env.example; do
  [ -f "$f" ] && ok "$f 생성" || fail "$f 없음"
done

if grep -rn '{{\|{%' --exclude-dir=.git . >/dev/null; then
  fail "렌더링되지 않은 템플릿 문법이 남아 있다: $(grep -rln '{{\|{%' --exclude-dir=.git .)"
else
  ok "템플릿 문법이 모두 렌더링됐다"
fi

grep -q '^@.claude/harness/WORKFLOW.md$' CLAUDE.md && ok "CLAUDE.md가 WORKFLOW.md를 불러온다" || fail "CLAUDE.md에 import 줄이 없다"
grep -q '"model": "claude-opus-5-5"' .claude/settings.json && ok "메인 모델 기본값" || fail "메인 모델 기본값이 다르다"
grep -q '^model: claude-sonnet-5-5$' .claude/agents/implementer.md && ok "implementer 모델 기본값" || fail "implementer 모델 기본값이 다르다"
grep -q '^model: claude-sonnet-5-5$' .claude/agents/code-reviewer.md && ok "code-reviewer 모델 기본값" || fail "code-reviewer 모델 기본값이 다르다"
[ -x scripts/check.sh ] && [ -x scripts/harness-check.sh ] && ok "검사 스크립트 실행 권한" || fail "검사 스크립트에 실행 권한이 없다"
[ ! -e .claude/skills ] && ok "스킬 팩을 고르지 않으면 .claude/skills/를 만들지 않는다" || fail "스킬 팩 없이 .claude/skills/가 생겼다"
grep -q '^\.claude/skills/' .claude/harness/owned-files.txt && fail "스킬 팩 없이 owned-files.txt에 스킬 항목이 있다" || ok "owned-files.txt에 스킬 항목이 없다"
grep -q '^skill_packs: \[\]$' .copier-answers.yml && ok "skill_packs 기본값은 빈 목록" || fail "skill_packs 기본값이 빈 목록이 아니다"

echo
echo "== 상태 표시줄 =="
[ -f .claude/harness/statusline.sh ] && ok ".claude/harness/statusline.sh 생성" || fail "statusline.sh 없음"
python3 -c 'import json,sys; c=json.load(open(".claude/settings.json"))["statusLine"]["command"]; sys.exit(0 if c.endswith("/.claude/harness/statusline.sh") else 1)' \
  && ok "settings.json의 statusLine이 하네스 스크립트를 실행한다" || fail "settings.json에 statusLine 설정이 없다"
if command -v jq >/dev/null 2>&1; then
  # 개발자 컴퓨터의 플러그인 상태가 결과에 섞이지 않도록 빈 설정 폴더를 쓴다
  export CLAUDE_CONFIG_DIR="$WORK/claude-config"
  mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
  now=$(date +%s)
  full="{\"model\":{\"display_name\":\"Opus 5.5\"},\"effort\":{\"level\":\"high\"},\"context_window\":{\"used_percentage\":42,\"context_window_size\":1000000,\"current_usage\":{\"input_tokens\":2,\"cache_creation_input_tokens\":1000,\"cache_read_input_tokens\":102000}},\"rate_limits\":{\"five_hour\":{\"used_percentage\":63,\"resets_at\":$((now + 7800))},\"seven_day\":{\"used_percentage\":85,\"resets_at\":$((now + 360000))}}}"
  out="$(printf '%s' "$full" | bash .claude/harness/statusline.sh | sed 's/\x1b\[[0-9;]*m//g')"
  if [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 4 ] \
     && echo "$out" | grep -q 'HIGH (3/5)' && echo "$out" | grep -q '103K / 1.0M 토큰' \
     && echo "$out" | grep -q '2시간 10분 후 초기화' && echo "$out" | grep -q '4일 4시간 후 초기화'; then
    ok "전체 입력이면 4줄을 출력한다"
  else
    fail "상태 표시줄 출력이 다르다:"; echo "$out"
  fi
  out="$(printf '%s' '{"model":{"display_name":"Opus 5.5"}}' | bash .claude/harness/statusline.sh | sed 's/\x1b\[[0-9;]*m//g')"
  if [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ] && echo "$out" | grep -q '컨텍스트  *--'; then
    ok "사용 한도 값이 없으면 해당 줄을 생략한다"
  else
    fail "값이 없을 때 출력이 다르다:"; echo "$out"
  fi
  echo '{"plugins":{"ponytail@ponytail":[],"caveman@caveman":[]}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  echo full > "$CLAUDE_CONFIG_DIR/.ponytail-active"
  mkdir -p "$CLAUDE_CONFIG_DIR/.caveman-sessions"
  echo caveman > "$CLAUDE_CONFIG_DIR/.caveman-active"
  echo ultracave > "$CLAUDE_CONFIG_DIR/.caveman-sessions/s1.mode"
  out="$(printf '%s' '{"session_id":"s1","model":{"display_name":"Opus 5.5"}}' | bash .claude/harness/statusline.sh | sed 's/\x1b\[[0-9;]*m//g')"
  if echo "$out" | head -1 | grep -q 'Ponytail ON .* FULL (2/3) | ● Caveman ON .* ULTRA (2/3)'; then
    ok "설치된 플러그인의 모드를 표시한다 (Caveman은 세션별 모드 우선)"
  else
    fail "플러그인 모드 출력이 다르다:"; echo "$out"
  fi
  echo '{"plugins":{"caveman@caveman":[]}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  out="$(printf '%s' '{"model":{"display_name":"Opus 5.5"}}' | bash .claude/harness/statusline.sh | sed 's/\x1b\[[0-9;]*m//g')"
  if ! echo "$out" | grep -q Ponytail && echo "$out" | head -1 | grep -q 'Caveman ON .* CAVEMAN (1/3)'; then
    ok "설치되지 않은 플러그인은 표시하지 않는다"
  else
    fail "설치되지 않은 플러그인이 표시됐다:"; echo "$out"
  fi
  unset CLAUDE_CONFIG_DIR
else
  echo "  [건너뜀] jq가 없어 상태 표시줄 출력 테스트를 건너뛴다"
fi

echo
echo "== 생성된 프로젝트에서 검사 실행 =="
# 이 테스트는 렌더링 결과와 검사 로직을 확인한다. gitleaks 설치 여부와 무관하게 결과가 같도록
# CI 모드를 끈다. GitHub Actions는 CI=true를 설정하므로, 그대로 두면 gitleaks가 없어서 실패하고
# 충돌 검출 테스트도 다른 이유로 실패해 검증이 무의미해진다.
export CI=false
git init -q -b main
if bash scripts/check.sh >"$WORK/check.log" 2>&1; then
  ok "scripts/check.sh 통과"
else
  fail "scripts/check.sh 실패"
  cat "$WORK/check.log"
fi

echo
echo "== 병합 충돌이 남으면 검사가 실패하는지 확인 =="
cp .gitignore "$WORK/gitignore.bak"
printf '<<<<<<< before updating\nfoo/\n=======\nbar/\n>>>>>>> after updating\n' >> .gitignore
if bash scripts/check.sh >/dev/null 2>&1; then
  fail "충돌 표시가 있는데 scripts/check.sh가 통과했다"
else
  ok "충돌 표시를 잡아냈다"
fi
cp "$WORK/gitignore.bak" .gitignore

touch settings.json.rej
if bash scripts/check.sh >/dev/null 2>&1; then
  fail ".rej 파일이 있는데 scripts/check.sh가 통과했다"
else
  ok ".rej 파일을 잡아냈다"
fi
rm settings.json.rej

echo
echo "== 템플릿 소유 파일 변경 경고 확인 =="
git add -A >/dev/null && git -c user.name=t -c user.email=t@t commit -qm init
# 출력은 변수에 먼저 담는다. pipefail 상태에서 `... | grep -q`를 쓰면 grep이 일찍 끝날 때
# 앞 명령이 SIGPIPE로 실패해 결과가 뒤집힌다.
out="$(bash scripts/check.sh 2>&1 || true)"
if echo "$out" | grep -q '템플릿 소유 파일이 마지막 커밋과 같다'; then
  ok "변경이 없으면 경고하지 않는다"
else
  fail "변경이 없는데 경고 문구가 다르다"
fi

echo "# 프로젝트에서 직접 고침" >> .claude/agents/implementer.md
out="$(bash scripts/check.sh 2>&1 || true)"
if echo "$out" | grep -q '템플릿 소유 파일을 프로젝트에서 직접 고쳤다' && echo "$out" | grep -q 'implementer.md'; then
  ok "직접 수정을 경고한다"
else
  fail "직접 수정을 경고하지 않았다"
fi
if bash scripts/check.sh >/dev/null 2>&1; then
  ok "경고는 검사를 실패시키지 않는다"
else
  fail "경고 때문에 검사가 실패했다"
fi

echo "# copier update 흉내" >> .copier-answers.yml
out="$(bash scripts/check.sh 2>&1 || true)"
if echo "$out" | grep -q 'copier update로 바뀐 템플릿 소유 파일이다'; then
  ok ".copier-answers.yml도 바뀌면 copier update로 본다"
else
  fail "copier update 상황을 구분하지 못했다"
fi
git checkout -q -- .

# ── 스킬 팩 ───────────────────────────────────────────
cd "$ROOT"
TEMPLATE_SKILLS="$ROOT/template/.claude/{% if skill_packs %}skills{% endif %}"
UPSTREAM_DIR="$TEMPLATE_SKILLS/{% if 'ui-design' in skill_packs %}frontend-design{% endif %}"

# 팩별 생성 파일. 파일을 추가·삭제하면 이 목록도 고친다.
files_python_backend() {
  local d=.claude/skills/backend-python
  printf '%s\n' "$d/SKILL.md"
  for f in alembic-env.py alembic.ini check-backend.sh ci-backend.yml clock.py compose.yml config.py \
           db-init-roles.sql dev.env ids.py migration-rls-table.py pyproject.toml session.py \
           test-rls-isolation.py tests-conftest.py tests-integration-conftest.py; do
    printf '%s\n' "$d/reference/$f.example"
  done
}
files_react_frontend() {
  local d=.claude/skills/frontend-react
  printf '%s\n' "$d/SKILL.md"
  for f in api-client.ts api-errors.ts check-frontend.sh ci-frontend.yml eslint.config.js package.json \
           prettierignore prettierrc.json subscribe.ts test-setup.ts tsconfig.json useComposer.ts vite.config.ts; do
    printf '%s\n' "$d/reference/$f.example"
  done
}
files_ui_design() {
  printf '%s\n' .claude/skills/frontend-design/SKILL.md .claude/skills/frontend-design/LICENSE.txt \
    .claude/skills/frontend-design/NOTICE.md .claude/skills/brand-identity/SKILL.md \
    .claude/skills/design-review/SKILL.md
}
owned_python_backend() { printf '%s\n' .claude/skills/backend-python/; }
owned_react_frontend() { printf '%s\n' .claude/skills/frontend-react/; }
owned_ui_design() {
  printf '%s\n' .claude/skills/frontend-design/ .claude/skills/brand-identity/ .claude/skills/design-review/
}

# render_with_packs <대상 폴더> <팩...>: 고른 팩으로 렌더링하고 생성 파일·owned-files를 확인한다.
render_with_packs() {
  local dest="$1"; shift
  local packs=("$@") list expected_files expected_owned actual pack fn
  list="[$(IFS=,; echo "${packs[*]}")]"
  echo
  echo "== 스킬 팩 렌더링: $list =="
  copier copy --quiet --defaults --vcs-ref=HEAD \
    --data project_name=demo --data "skill_packs=$list" "$ROOT" "$dest" 2>/dev/null
  expected_files=""; expected_owned=""
  for pack in "${packs[@]}"; do
    fn="${pack//-/_}"
    expected_files+="$("files_$fn")"$'\n'
    expected_owned+="$("owned_$fn")"$'\n'
  done
  expected_files="$(printf '%s' "$expected_files" | sed '/^$/d' | LC_ALL=C sort)"
  expected_owned="$(printf '%s' "$expected_owned" | sed '/^$/d' | LC_ALL=C sort)"

  actual="$(cd "$dest" && find .claude/skills -type f | LC_ALL=C sort)"
  if [ "$actual" = "$expected_files" ]; then
    ok "고른 팩의 스킬 파일만 생성했다 ($(printf '%s\n' "$actual" | wc -l | tr -d ' ')개)"
  else
    fail "생성 파일 목록이 다르다"
    diff <(printf '%s\n' "$expected_files") <(printf '%s\n' "$actual") || true
  fi

  actual="$(grep '^\.claude/skills/' "$dest/.claude/harness/owned-files.txt" | LC_ALL=C sort)"
  if [ "$actual" = "$expected_owned" ]; then
    ok "owned-files.txt에 고른 팩만 템플릿 소유로 들어갔다"
  else
    fail "owned-files.txt 스킬 항목이 다르다"
    diff <(printf '%s\n' "$expected_owned") <(printf '%s\n' "$actual") || true
  fi

  if grep -rn '{{\|{%' "$dest" >/dev/null; then
    fail "렌더링되지 않은 템플릿 문법이 남아 있다: $(grep -rln '{{\|{%' "$dest")"
  else
    ok "템플릿 문법이 모두 렌더링됐다"
  fi

  # 각 SKILL.md의 name이 폴더 이름과 같아야 Claude Code가 스킬을 올바른 이름으로 읽는다.
  local skill name
  for skill in "$dest"/.claude/skills/*/SKILL.md; do
    name="$(sed -n 's/^name: //p' "$skill" | head -1)"
    if [ "$name" = "$(basename "$(dirname "$skill")")" ]; then
      ok "$(basename "$(dirname "$skill")") SKILL.md name이 폴더 이름과 같다"
    else
      fail "$skill 의 name($name)이 폴더 이름과 다르다"
    fi
  done
}

# 원본 frontend-design 파일이 Anthropic 원본(anthropics/skills 41bbe19)과 바이트 단위로 같은지 확인한다.
# 원본을 갱신하면 NOTICE.md의 커밋과 아래 SHA-256을 함께 바꾼다.
UPSTREAM_SKILL_SHA256=d91970639e9f5c37682ac7ab60094d35f1c7c1f38d731bd56396563aee10c1d3
UPSTREAM_LICENSE_SHA256=0d542e0c8804e39aa7f37eb00da5a762149dc682d7829451287e11b938e94594
sha256() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
check_upstream_files() {
  local dest="$1" f expected
  for f in SKILL.md LICENSE.txt; do
    if [ "$f" = SKILL.md ]; then expected="$UPSTREAM_SKILL_SHA256"; else expected="$UPSTREAM_LICENSE_SHA256"; fi
    if [ "$(sha256 "$UPSTREAM_DIR/$f")" = "$expected" ]; then
      ok "템플릿의 frontend-design/$f 가 원본과 같다 (SHA-256)"
    else
      fail "템플릿의 frontend-design/$f 가 원본과 다르다"
    fi
    if cmp -s "$UPSTREAM_DIR/$f" "$dest/.claude/skills/frontend-design/$f"; then
      ok "생성된 frontend-design/$f 가 템플릿 파일과 바이트 단위로 같다"
    else
      fail "생성된 frontend-design/$f 가 템플릿 파일과 다르다"
    fi
  done
  # 선택: 원본 사본이 있는 폴더를 주면 직접 비교한다 (예: 다른 프로젝트에 받아 둔 원본).
  if [ -n "${UPSTREAM_FRONTEND_DESIGN_DIR:-}" ]; then
    for f in SKILL.md LICENSE.txt; do
      if cmp -s "$UPSTREAM_FRONTEND_DESIGN_DIR/$f" "$dest/.claude/skills/frontend-design/$f"; then
        ok "생성된 frontend-design/$f 가 UPSTREAM_FRONTEND_DESIGN_DIR 원본과 같다"
      else
        fail "생성된 frontend-design/$f 가 UPSTREAM_FRONTEND_DESIGN_DIR 원본과 다르다"
      fi
    done
  fi
}

ALL="$WORK/all-packs"
render_with_packs "$ALL" python-backend react-frontend ui-design
check_upstream_files "$ALL"
grep -q 'design-review/SKILL.md`를 Read로' "$ALL/CLAUDE.md" && ok "CLAUDE.md 검토 관점에 design-review가 들어갔다" \
  || fail "CLAUDE.md 검토 관점에 design-review가 없다"
grep -q '^이 프로젝트에 설치한 스킬 팩: python-backend, react-frontend, ui-design$' "$ALL/.claude/harness/WORKFLOW.md" \
  && ok "WORKFLOW.md에 설치한 스킬 팩이 적혔다" || fail "WORKFLOW.md에 설치한 스킬 팩 목록이 없다"
for skill in backend-python frontend-react brand-identity design-review; do
  grep -q "\.claude/project-skills/$skill\.md" "$ALL/.claude/skills/$skill/SKILL.md" \
    && ok "$skill 이 프로젝트 보충 규칙 위치를 안내한다" || fail "$skill 에 프로젝트 보충 규칙 안내가 없다"
done

echo
echo "== 전체 팩 프로젝트에서 검사 실행 =="
cd "$ALL"
git init -q -b main
if bash scripts/check.sh >"$WORK/check-all.log" 2>&1; then
  ok "scripts/check.sh 통과 (커밋 전)"
else
  fail "scripts/check.sh 실패 (커밋 전)"; cat "$WORK/check-all.log"
fi
git add -A >/dev/null && git -c user.name=t -c user.email=t@t commit -qm init
if bash scripts/check.sh >"$WORK/check-all.log" 2>&1; then
  ok "scripts/check.sh 통과 (커밋 후, gitleaks가 있으면 비밀정보 탐지 포함)"
else
  fail "scripts/check.sh 실패 (커밋 후)"; cat "$WORK/check-all.log"
fi
echo "# 프로젝트에서 직접 고침" >> .claude/skills/design-review/SKILL.md
out="$(bash scripts/check.sh 2>&1 || true)"
if echo "$out" | grep -q '템플릿 소유 파일을 프로젝트에서 직접 고쳤다' && echo "$out" | grep -q 'design-review/SKILL.md'; then
  ok "스킬 팩 파일 직접 수정을 경고한다"
else
  fail "스킬 팩 파일 직접 수정을 경고하지 않았다"
fi
git checkout -q -- .
mkdir -p .claude/project-skills && echo "# 보충" > .claude/project-skills/design-review.md
out="$(bash scripts/check.sh 2>&1 || true)"
if echo "$out" | grep -q '템플릿 소유 파일이 마지막 커밋과 같다'; then
  ok "프로젝트 보충 규칙(.claude/project-skills/)은 템플릿 소유가 아니다"
else
  fail "프로젝트 보충 규칙 추가를 템플릿 소유 파일 변경으로 봤다"
fi
rm -r .claude/project-skills
cd "$ROOT"

render_with_packs "$WORK/backend-only" python-backend
render_with_packs "$WORK/ui-only" ui-design
check_upstream_files "$WORK/ui-only"
grep -q 'backend-python' "$WORK/ui-only/CLAUDE.md" && fail "ui-design만 골랐는데 CLAUDE.md에 backend-python이 있다" \
  || ok "CLAUDE.md에 고르지 않은 팩이 없다"

echo
echo "== 기존 프로젝트에 copier update로 팩 추가·제거 =="
# copier update는 프로젝트의 _commit이 템플릿 저장소에 있어야 한다. 작업 트리 변경이 있는 템플릿에서는
# 임시 커밋이 생기므로, 템플릿을 복사해 현재 상태를 커밋한 저장소로 확인한다.
TPL="$WORK/template-repo"
cp -R "$ROOT" "$TPL"
git -C "$TPL" add -A
git -C "$TPL" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "test snapshot"
UP="$WORK/update-demo"
copier copy --quiet --defaults --vcs-ref=HEAD --data project_name=demo "$TPL" "$UP" 2>/dev/null
cd "$UP"
git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init
copier update --quiet --defaults --vcs-ref=HEAD --data 'skill_packs=[react-frontend]' >/dev/null 2>&1
actual="$(find .claude/skills -type f 2>/dev/null | LC_ALL=C sort)"
if [ "$actual" = "$(files_react_frontend | LC_ALL=C sort)" ] && grep -q '^\.claude/skills/frontend-react/$' .claude/harness/owned-files.txt; then
  ok "copier update --data skill_packs=... 로 팩을 추가한다"
else
  fail "copier update로 팩을 추가하지 못했다"
fi
git add -A && git -c user.name=t -c user.email=t@t commit -qm packs
copier update --quiet --defaults --vcs-ref=HEAD --data 'skill_packs=[]' >/dev/null 2>&1
if [ -z "$(find .claude/skills -type f 2>/dev/null)" ] && ! grep -q '^\.claude/skills/' .claude/harness/owned-files.txt; then
  ok "copier update --data skill_packs=[] 로 팩을 제거한다"
else
  fail "copier update로 팩을 제거하지 못했다"
fi
cd "$ROOT"

echo
if [ "$FAILED" -ne 0 ]; then
  echo "템플릿 테스트 실패"
  exit 1
fi
echo "템플릿 테스트 통과"
