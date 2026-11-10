#!/usr/bin/env bash
# 하네스 템플릿 저장소의 검사 진입점.
#   1. 템플릿 안의 훅 테스트
#   2. 템플릿을 임시 프로젝트로 렌더링한 뒤 생성된 프로젝트의 검사 실행

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== 훅 테스트 =="
python3 -m unittest discover -s template/tests/harness -q

echo
bash tests/test_template.sh
