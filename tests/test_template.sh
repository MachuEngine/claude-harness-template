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

echo
if [ "$FAILED" -ne 0 ]; then
  echo "템플릿 테스트 실패"
  exit 1
fi
echo "템플릿 테스트 통과"
