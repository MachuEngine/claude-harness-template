# 변경 기록

버전 태그는 `vMAJOR.MINOR.PATCH` 형식을 쓴다. copier는 이 태그를 기준으로 `copier update`를 수행한다.

- MAJOR: 프로젝트에서 수동 이전 작업이 필요한 변경 (파일 소유 구분 변경, 질문 항목 삭제 등)
- MINOR: 새 규칙·에이전트·검사 추가
- PATCH: 문구 수정, 버그 수정

## v0.2.0 — 2026-11-10

프로젝트에서 템플릿 소유 파일을 고치면 템플릿 저장소 반영을 알린다 (HIR-0002).

- `.claude/harness/owned-files.txt`: 템플릿 소유 파일 목록을 한 곳에 정의
- `.claude/hooks/template_drift_notice.py`: Edit·Write로 템플릿 소유 파일을 고치면 사용자 알림과 메인 세션 컨텍스트를 남기는 PostToolUse 훅. `.claude/settings.json`에 등록
- `scripts/harness-check.sh`: 마지막 커밋 이후 템플릿 소유 파일이 바뀌었고 `copier update`가 아니면 경고 (검사는 실패시키지 않음)
- `WORKFLOW.md`: 템플릿 반영 알림 설명 추가

갱신 시 참고: `.claude/settings.json`에 `hooks` 항목이 추가된다. 프로젝트에서 이미 `hooks`를 정의했다면 병합 충돌을 확인한다.

## v0.1.0 — 2026-11-10

첫 버전. 첫 적용 프로젝트에서 만든 하네스를 범용 부분과 프로젝트 부분으로 나눠 템플릿으로 옮겼다.

- 메인(Opus)·implementer(Sonnet)·code-reviewer(Sonnet) 역할 분담 (HIR-0001)
- 공통 작업 규칙을 `.claude/harness/WORKFLOW.md`로 분리하고 `CLAUDE.md`에서 `@` import
- code-reviewer Bash 읽기 전용 훅과 테스트 (`ls`·`grep` 허용, 재귀 grep과 비밀정보 경로 차단)
- `.env`·`secrets/`·`*.pem`·`*.key` 읽기 차단 권한 설정, 메인 모델 고정
- `scripts/harness-check.sh`: gitleaks 비밀정보 탐지, 설정·훅 검사, `.env`·`private-docs/` 추적 검사, `copier update` 후 남은 병합 충돌 표시·`.rej` 파일 검사
- CI(gitleaks 설치 후 `scripts/check.sh`), PR 템플릿
