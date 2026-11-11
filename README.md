# claude-harness-template

Claude Code로 개발할 때 쓰는 개발 하네스 템플릿이다. [copier](https://copier.readthedocs.io/)로 새 프로젝트에 하네스를 설치하고, 하네스가 개선되면 각 프로젝트에 `copier update`로 반영한다.

## 들어 있는 것

| 구성 | 내용 |
| --- | --- |
| 역할 분담 | 메인 세션(Opus)이 설계·계획·지휘, `implementer`(Sonnet)가 구현, `code-reviewer`(Sonnet)가 읽기 전용 검토 |
| 공통 작업 규칙 | `.claude/harness/WORKFLOW.md`. 프로젝트 `CLAUDE.md`가 `@` import로 불러온다 |
| 템플릿 반영 알림 | 템플릿 소유 파일을 프로젝트에서 고치면 수정 직후 훅 알림, 검사 실행 시 경고 |
| 리뷰어 읽기 전용 훅 | `code-reviewer`의 Bash를 git 조회·`ls`·`grep`·`scripts/check.sh`·테스트와 정적 검사(pytest, ruff, mypy, pyright)로 제한하는 PreToolUse 훅과 테스트 |
| 권한 설정 | `.env`, `secrets/`, `*.pem`, `*.key` 읽기 차단 (`.env.example`은 허용), 메인 모델 고정 |
| 검사 | `scripts/harness-check.sh`(gitleaks 비밀정보 탐지, 설정·훅 검사)와 프로젝트용 `scripts/check.sh` |
| CI·PR | GitHub Actions에서 `scripts/check.sh` 실행, PR 체크리스트 템플릿 |

## 필요 도구

- copier 9 이상: `uv tool install copier` 또는 `pipx install copier`
- git, python3
- gitleaks (로컬에서는 선택, CI에서는 자동 설치): `brew install gitleaks`

## 새 프로젝트에 설치

```bash
copier copy gh:MachuEngine/claude-harness-template my-project
```

질문 항목:

| 항목 | 기본값 | 설명 |
| --- | --- | --- |
| `project_name` | 없음 | `CLAUDE.md` 제목 |
| `project_summary` | 빈 값 | 제품 목표 첫 줄 |
| `main_model` | `claude-opus-5-5` | 메인 세션 모델 |
| `worker_model` | `claude-sonnet-5-5` | 서브에이전트 모델 |
| `gitleaks_version` | `8.18.4` | CI에서 쓸 gitleaks 버전 |

설치 후 `CLAUDE.md`의 프로젝트 섹션을 채우고 `scripts/check.sh`로 확인한다.

이미 파일이 있는 프로젝트에 설치할 때는 겹치는 파일을 copier가 하나씩 물어본다. 기존 `CLAUDE.md`, `scripts/check.sh`, `.env.example`은 덮어쓰지 않는다.

## 하네스 갱신

```bash
git commit -am "작업 내용 정리"   # copier update는 작업 트리가 깨끗해야 한다
copier update
scripts/check.sh
```

`copier update`는 템플릿의 이전 버전과 새 버전의 차이를 프로젝트 파일에 3-way 병합한다. 충돌이 나면 `.rej` 파일이나 충돌 표시가 남으므로 정리한 뒤 커밋한다.

## 파일 소유 구분

| 구분 | 파일 | 수정 위치 |
| --- | --- | --- |
| 템플릿 소유 | `.claude/harness/`, `.claude/agents/`, `.claude/hooks/`, `scripts/harness-check.sh`, `tests/harness/`, `.github/pull_request_template.md` (정확한 목록: `template/.claude/harness/owned-files.txt`) | 이 저장소에서만 고친다 |
| 병합 | `.claude/settings.json`, `.gitignore`, `.github/workflows/ci.yml` | 프로젝트에서 고쳐도 된다. `copier update`가 병합한다 |
| 프로젝트 소유 | `CLAUDE.md`, `scripts/check.sh`, `.env.example` | 프로젝트에서 고친다. 처음 한 번만 생성한다 |
| 관리 파일 | `.copier-answers.yml` | 직접 고치지 않는다 |

## 하네스 개선 절차

프로젝트를 진행하다 하네스 문제를 발견했을 때:

1. **그 프로젝트에만 해당하는 문제**는 프로젝트의 `CLAUDE.md`, `scripts/check.sh`, 병합 파일에서 해결한다.
2. **다른 프로젝트에도 해당하는 문제**는 이 저장소에서 고친다.
   1. 템플릿 파일(`template/`)을 수정한다.
   2. `scripts/check.sh`로 템플릿 테스트를 실행한다.
   3. `docs/hir/`에 HIR을 남기고 `CHANGELOG.md`를 갱신한다.
   4. 커밋하고 버전 태그를 붙인다 (`git tag v0.2.0`). copier는 가장 높은 버전 태그를 기준으로 갱신한다.
   5. push한 뒤 각 프로젝트에서 `copier update`를 실행한다.
3. 프로젝트 안의 템플릿 소유 파일을 급하게 먼저 고쳤다면 같은 작업 안에서 이 저장소에도 반영한다. 반영하지 않으면 다음 `copier update`에서 충돌하거나 변경이 사라진다.

프로젝트에서 템플릿 소유 파일을 고치면 하네스가 알려 준다.
- Claude가 Edit·Write로 고치면 PostToolUse 훅(`template_drift_notice.py`)이 바로 알림을 띄운다.
- 에디터나 Bash로 고친 경우는 `scripts/check.sh`가 경고로 보여 준다.

개선 기준: 같은 유형의 문제가 2회 이상 반복되거나, 보안·데이터 손상 위험이 1회라도 발견되면 검토한다. 도입 후에는 효과를 측정하고, 효과가 없으면 수정하거나 제거한다.

## 이 저장소의 구조

```text
copier.yml            질문 항목과 파일 소유 설정
template/             프로젝트에 설치되는 파일 (.jinja는 렌더링 대상)
tests/test_template.sh  임시 프로젝트를 만들어 렌더링과 검사를 확인
scripts/check.sh      이 저장소의 검사 진입점
docs/hir/             하네스 개선 기록
CHANGELOG.md          버전별 변경 내용
```
