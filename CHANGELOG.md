# 변경 기록

버전 태그는 `vMAJOR.MINOR.PATCH` 형식을 쓴다. copier는 이 태그를 기준으로 `copier update`를 수행한다.

- MAJOR: 프로젝트에서 수동 이전 작업이 필요한 변경 (파일 소유 구분 변경, 질문 항목 삭제 등)
- MINOR: 새 규칙·에이전트·검사 추가
- PATCH: 문구 수정, 버그 수정

## v0.4.0 — 2026-11-11

스택별 범용 스킬을 스킬 팩으로 묶어 설치할 때 고를 수 있게 한다 (HIR-0004).

- `copier.yml`: 다중 선택 질문 `skill_packs` 추가(기본값 빈 목록). 선택지 `python-backend`, `react-frontend`, `ui-design`
- 스킬 팩
  - `python-backend` → `.claude/skills/backend-python/` (SKILL.md, `reference/` 예시 파일 16개)
  - `react-frontend` → `.claude/skills/frontend-react/` (SKILL.md, `reference/` 예시 파일 13개)
  - `ui-design` → `.claude/skills/frontend-design/`(Anthropic 원본 SKILL.md·LICENSE.txt 그대로, NOTICE.md), `brand-identity/`, `design-review/`
- 고른 팩의 스킬 폴더만 생성하고(폴더 이름 조건식), 그 폴더를 `owned-files.txt`에 템플릿 소유로 추가한다. `owned-files.txt`는 `owned-files.txt.jinja`로 바뀌었다(생성 경로는 같다)
- 프로젝트 보충 규칙 위치 `.claude/project-skills/<스킬>.md`(프로젝트 소유, 템플릿이 만들지 않음). 각 범용 스킬이 첫머리에서 안내한다
- `WORKFLOW.md`: 파일 소유 표에 스킬 팩 폴더와 `.claude/project-skills/` 추가, "스킬 팩" 절 추가
- `CLAUDE.md`(새 프로젝트만): 고른 팩에 맞춰 "먼저 읽을 문서"와 "프로젝트 검토 관점"에 스킬 경로를 넣는다
- 템플릿 테스트: 팩 없음·전체·일부 렌더링의 생성 파일과 `owned-files.txt`, frontend-design 원본 SHA-256, 전체 팩 프로젝트의 검사, `copier update`로 팩 추가·제거
- 템플릿 저장소 `scripts/check.sh`: 훅 테스트를 `template/` 원본이 아니라 기본값으로 렌더링한 프로젝트에서 실행한다(`owned-files.txt`가 렌더링 대상이 됐기 때문)
- `_min_copier_version`을 9.8.0으로 올렸다. 다중 선택 질문에 `--data`로 목록을 넘기는 기능이 9.8.0에 들어왔다

갱신 시 참고: copier 9.8 이상이 필요하다. 기존 프로젝트는 `skill_packs`가 빈 목록으로 들어가며 생성 파일은 바뀌지 않는다(`WORKFLOW.md`, `owned-files.txt` 문구만 바뀐다). 팩을 추가하려면 `copier update --defaults --data 'skill_packs=[...]'`를 실행하고, `CLAUDE.md`에 스킬 경로를 직접 적는다. 이미 같은 이름의 스킬 폴더(예: `.claude/skills/frontend-design/`)가 있으면 copier가 덮어쓸지 묻는다. 프로젝트 전용 내용은 먼저 `.claude/project-skills/`로 옮긴다.

## v0.3.0 — 2026-11-11

code-reviewer가 하위 폴더에서 실행되거나 테스트를 돌려야 할 때 Bash 훅이 정상 명령을 막던 문제를 고친다 (HIR-0003).

- `reviewer_bash_guard.py`: `CLAUDE_PROJECT_DIR` 기준 `scripts/check.sh` 절대 경로 허용
- `git -C <프로젝트 안쪽 폴더> <조회 명령>` 허용, `git check-ignore` 추가
- `pytest`, `uv run pytest`, `python -m pytest`, `uv run ruff check`, `uv run ruff format --check`, `uv run mypy`, `uv run pyright` 허용. `--directory`·`--project`는 프로젝트 안쪽 폴더만 허용
- 도구 옵션은 허용 목록 방식. 목록 밖 옵션, 프로젝트 밖 경로 인자, 셸 확장 문자(`~ * ? [ ] { } !`), `git --no-index`, 중첩 저장소 대상 `git -C`, `uv run python ...`은 차단
- git도 서브커맨드별 허용 옵션 목록으로 제한(약어·묶음 차단). `git grep --open*`·`-O`·`-f`·`--no-exclude-standard`, `git blame --contents`, 절대 경로·`..` 경로 인자 차단
- 비밀정보 경로 검사는 대소문자를 구분하지 않음. 중첩 저장소 검사는 프로젝트 루트 직전까지 모든 상위 폴더 대상이며 `-C` 없는 git은 훅 작업 폴더 기준
- 위치 인자 없는 `pytest`·`ruff` 등은 기준 폴더가 프로젝트 안쪽일 때만 허용. `ruff check`는 `--no-fix`(또는 `--diff`) 필수
- `code-reviewer.md` 도구 제한 안내 갱신, 훅 테스트 추가

갱신 시 참고: 리뷰어가 `ruff check`를 쓰던 프로젝트는 `--no-fix`를 붙여야 한다. pytest는 테스트 코드를 실행하므로 리뷰어가 완전한 읽기 전용이 아니게 된다. 위험은 HIR-0003에 적었다.

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
