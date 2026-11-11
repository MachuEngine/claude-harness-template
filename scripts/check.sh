#!/usr/bin/env bash
# 하네스 템플릿 저장소의 검사 진입점.
#   1. 템플릿을 기본값으로 렌더링한 프로젝트에서 훅 테스트
#   2. 템플릿을 임시 프로젝트로 렌더링한 뒤 생성된 프로젝트의 검사 실행 (스킬 팩 조합 포함)
#
# 훅 테스트를 template/ 원본이 아니라 렌더링 결과에서 돌리는 이유: 훅이 읽는
# .claude/harness/owned-files.txt가 스킬 팩 선택에 따라 달라지는 copier 템플릿(.jinja)이라
# template/ 안에는 렌더링된 파일이 없다.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

HOOK_WORK="$(mktemp -d)"
trap 'rm -rf "$HOOK_WORK"' EXIT

echo "== 훅 테스트 =="
copier copy --quiet --defaults --vcs-ref=HEAD --data project_name=hooktest \
  "$ROOT" "$HOOK_WORK/project" 2>/dev/null
(cd "$HOOK_WORK/project" && python3 -m unittest discover -s tests/harness -q)

echo
bash tests/test_template.sh
