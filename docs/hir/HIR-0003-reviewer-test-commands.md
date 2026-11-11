# HIR-0003 — code-reviewer Bash 훅: 하위 폴더 실행과 테스트·정적 검사 허용

- 상태: 실험 중
- 도입일: 2026-11-11 (v0.3.0)
- 도입 근거: 첫 적용 프로젝트에서 같은 유형의 문제가 2회 이상 재현됐다. 훅이 정상적인 검토 작업을 막아 리뷰어가 검사를 건너뛰거나 우회 명령을 시도했다.

## 발견한 문제
1. 세션 작업 폴더가 저장소 하위 폴더일 때 리뷰어가 `scripts/check.sh`를 실행하면 경로를 찾지 못한다. 절대 경로로 쓰면 훅이 허용 목록 밖으로 판단해 막는다.
2. 리뷰어가 `git -C <경로> status`를 쓰면 훅이 `tokens[1]`이 `-C`라서 막는다.
3. 백엔드 구현 단계부터 리뷰어가 테스트·정적 검사를 직접 돌려야 하는데 허용 목록에 없다. HIR-0001의 재검토 트리거("리뷰어가 테스트를 직접 실행해야 할 필요")에 해당한다.

## 개선안
`.claude/hooks/reviewer_bash_guard.py`에 다음을 추가했다. 셸 메타문자 금지, 비밀정보 경로 차단, fail closed 원칙은 그대로다.

| 항목 | 허용 | 조건 |
| --- | --- | --- |
| check.sh 절대 경로 | `<CLAUDE_PROJECT_DIR>/scripts/check.sh`, `bash <같은 경로>` | `os.path.realpath`로 정규화한 경로가 정확히 일치할 때만. 인자 추가는 차단 |
| `git -C <dir>` | `-C` 뒤 폴더에서 기존 허용 서브커맨드 | `<dir>`이 `CLAUDE_PROJECT_DIR` 안쪽일 때만(realpath 비교, 심볼릭 링크 우회 차단). 기존 금지 옵션 검사 적용. `check-ignore` 추가 |
| 테스트 | `pytest`, `python -m pytest`, `python3 -m pytest`, `uv run pytest` | `uv run --directory/--project <dir>` 형태도 `<dir>`이 프로젝트 안쪽일 때만 |
| 정적 검사 | `uv run ruff check`, `uv run ruff format --check`, `uv run mypy`, `uv run pyright` | `--fix`, `--unsafe-fixes`, `--add-noqa`, `--check` 없는 `ruff format` 차단 |

- `uv run` 뒤에는 위 도구만 올 수 있다. `uv run python ...`, `uv run bash ...`, `--with` 같은 다른 uv 옵션은 차단한다.
- 도구 옵션은 차단 목록이 아니라 **허용 목록**으로 제한한다(아래 "허용 목록 방식으로 바꾼 이유" 참고). 도구별 허용 옵션:
  - pytest: `-q -v -vv -x -s -l`(묶음 `-qx`는 각 글자가 `q v x s l`일 때만), `-ra`, `-rA`, `--no-header`, `--collect-only`/`--co`, `--lf`, `--ff`, `--tb=<short|long|line|no|native>`, `--maxfail=<숫자>`, `--durations=<숫자>`, `-k <식>`, `-m <마커식>`(`-k`, `-m`은 각각 한 번만).
  - ruff check: `--statistics`, `--quiet`, `--diff`, `--output-format=<concise|full|json|github>`, `--select=<코드들>`. ruff format: `--check` 또는 `--diff` 필수, `--quiet`. `--`는 차단한다.
  - mypy: `--strict`, `--pretty`, `--show-error-codes`, `--no-error-summary`, `--show-column-numbers`. pyright: `--outputjson`, `--stats`.
  - 위치 인자는 모두 경로여야 하고 `CLAUDE_PROJECT_DIR` 안쪽이어야 한다(realpath 비교, `--directory`가 있으면 그 폴더 기준). pytest는 `경로::테스트이름`도 허용한다. `@파일`, `-`는 차단한다.
  - `python`/`python3` 뒤에는 정확히 `-m pytest`만 허용한다. `uv run`은 `--directory`와 `--project` 중 하나만 허용한다.
- 셸 확장 문자 `* ? [ ] { } !`가 명령에 있거나 토큰이 `~`로 시작하면 차단한다(따옴표 안도 차단). `HEAD~1`처럼 토큰 중간의 `~`는 허용한다.
- git: 모든 인자에 비밀정보 경로 검사를 적용한다(`HEAD:.env` 형태도 잡도록 `:`를 경로 구분으로 추가). `check-ignore`는 파일 내용을 읽지 않으므로 이 검사에서 제외한다. `--no-index`는 저장소 밖 파일을 읽으므로 차단한다. `git -C` 대상이 프로젝트 루트가 아니면서 자체 `.git`(폴더 또는 파일)을 가지면 차단한다(중첩 저장소의 `core.fsmonitor`, textconv 실행 방지).
- `CLAUDE_PROJECT_DIR`가 없으면 폴더를 받는 형태(`git -C`, `--directory`, `--project`, check.sh 절대 경로)는 모두 차단한다.
- 에이전트 정의의 "도구 제한" 안내를 갱신했다. 테스트는 `uv run --directory <폴더> pytest`처럼 폴더를 지정해 쓰라고 안내한다.

## pytest 실행 위험
- pytest는 저장소의 테스트 코드와 `conftest.py`를 실행한다. 이 코드가 파일을 쓰거나 삭제하거나 네트워크에 접근해도 훅은 막지 못한다. 리뷰어는 완전한 읽기 전용이 아니게 된다.
- 리뷰 대상은 implementer가 방금 작성한 코드이므로, 잘못 작성된 테스트가 부작용을 낼 수 있다. 악의적인 코드라기보다 테스트 픽스처 정리 실수 같은 사고를 가정한다.
- 완화책: 쓰기 옵션 차단, 비밀정보 경로 인자 차단, 에이전트 정의에 "의심스러우면 테스트 코드를 먼저 읽는다"고 안내. 비밀정보는 권한 deny 규칙이 Read를 막지만, 테스트 코드가 `.env`를 직접 열면 막을 수 없다.
- 프로젝트가 테스트에서 외부 접근을 막는 구조(합성 데이터, 네트워크 차단 픽스처)를 갖추는 것이 근본 대책이다.

## 허용 목록 방식으로 바꾼 이유
초안은 위험한 옵션을 나열해 막는 차단 목록이었다. 리뷰에서 우회 사례가 계속 나왔고, 옵션 이름이 도구 버전과 약어 규칙에 따라 늘어나므로 차단 목록으로는 끝나지 않는다고 판단했다. 허용한 옵션만 통과시키고 나머지는 모두 막는다.

리뷰에서 나온 우회 사례:
- 셸 확장: `git -C ~ status`, `uv run --directory ~/x pytest`, `pytest {a,b}`. 훅은 문자열을 셸이 확장하기 전에 검사하므로 `~`와 중괄호가 경로 검사를 피한다.
- 경로 인자: pytest·ruff·mypy·pyright의 위치 인자(`/tmp/outside`, `../..`)는 프로젝트 밖을 가리킬 수 있었다.
- 설정·출력 옵션: ruff `--config fix=true`, `--isolated`, `--`로 `--check` 판정 회피, pytest `--log-file`, `--debug`, `-o`, `-c`, `--rootdir`, `--confcutdir`, `--pdbcls`, `--pyargs`, `-qp plugin`(묶음 옵션), mypy `--python-executable`, `--cache-dir`, `--config-file`, `--junit-x`(약어), pyright `--pythonpath`.
- 동시 지정: `--directory a --project b`로 검사 대상과 실행 폴더를 어긋나게 할 수 있었다.
- git: `git grep --no-index K -- .env`, `git diff --no-index /dev/null .env`로 비밀정보 파일을 읽을 수 있었다. 중첩 저장소를 `git -C`로 가리키면 그 저장소의 `core.fsmonitor`나 textconv 설정이 프로그램을 실행할 수 있다.

## 3회차 재검토: git도 허용 목록으로 전환
도구 옵션 9건을 막은 뒤 재검토에서 git이 여전히 차단 목록(`--output`, `--ext-diff`, `--open-files-in-pager`, `-O`, `--no-index`)이라 새 구멍이 나왔다. 일부는 실제로 재현됐다.

재현된 우회:
- `git grep --open=echo -n x -- f`, `git grep --open x`: `--open*`이 `--open-files-in-pager`의 약어라 접두사 차단을 피해 외부 프로그램을 실행한다.
- `git grep -f /etc/hosts`, `git grep --untracked --no-exclude-standard -n KEY`: 프로젝트 밖 파일을 패턴 파일로 읽거나 `.gitignore`된 `.env`까지 검색한다.
- `git blame --contents /etc/hosts -L1,2 CLAUDE.md`: 저장소 밖 파일 내용을 읽는다.
- `git diff /etc/hosts /etc/passwd`: 저장소 안에서도 경로가 밖을 가리키면 `--no-index`처럼 동작한다.
- 대소문자: `.ENV`, `Secrets/x`, `a.PEM`, `HEAD:.Env`가 비밀정보 검사를 피한다.
- 중첩 저장소: `git -C <proj>/nested/sub status`는 대상 폴더 자신에는 `.git`이 없어 통과하지만 상위 `nested/.git`의 설정이 적용된다.
- 인자 없는 도구: 훅 작업 폴더가 프로젝트 밖이면 `pytest`, `ruff check`가 밖의 폴더를 대상으로 실행된다.
- ruff `fix = true`: 설정 파일이 켜 두면 `ruff check`만으로 파일이 고쳐진다.

조치:
- git을 서브커맨드별 허용 옵션 목록(`GIT_SPECS`)으로 바꿨다. 옵션은 이름이 정확히 일치할 때만 통과하고 약어, 묶음(`-sb`)은 차단한다. 허용 목록은 `reviewer_bash_guard.py` 상단 주석과 `code-reviewer.md` 도구 제한에 있다.
- 커밋·범위·경로 인자는 `[A-Za-z0-9_./~^-]+`(`..`, `...` 범위 포함)에 `fullmatch`하고, 절대 경로와 `..` 경로 조각은 차단한다. `git show`는 `<커밋>:<경로>`도 허용하며 경로 부분에 같은 검사를 한다.
- `git ls-files --others`는 `--exclude-standard`와 함께일 때만, `git grep`은 `--untracked`와 `--cached`만 허용한다. `--contents`, `--open*`, `-O`, `-f`, `--no-exclude-standard`, `--no-index`는 허용 목록에 없어 차단한다.
- 비밀정보 경로 검사를 `re.IGNORECASE`로 바꿨다.
- 중첩 저장소 검사: `git -C` 대상 폴더부터 프로젝트 루트 직전까지 모든 상위 폴더에 `.git`(폴더·파일)이 있으면 차단한다. `-C`가 없으면 훅 작업 폴더로 같은 검사를 하고, 작업 폴더가 프로젝트 밖이면 차단한다.
- 위치 인자가 없는 도구 명령은 기준 폴더(훅 작업 폴더 또는 `--directory`)가 프로젝트 안쪽이어야 한다.
- `ruff check`는 `--no-fix`(또는 `--diff`)가 없으면 차단하고 메시지로 `--no-fix`를 안내한다. 기존에 `--no-fix` 없이 쓰던 `ruff check` 사용 방식은 바뀐다.
- `CLAUDE_PROJECT_DIR`가 없으면 중첩 저장소 검사와 인자 없는 도구의 기준 폴더 검사는 하지 않는다. 이 변수 없이 `git status`, `uv run pytest`가 동작하던 기존 동작을 유지하기 위해서다.

## 남는 위험
- git의 `diff`, `log -p`, `show`는 기본적으로 textconv를 적용한다. 저장소나 사용자의 git 설정에 `diff.<driver>.textconv`가 있으면 외부 프로그램이 실행될 수 있다. 훅은 git 설정을 읽지 않으므로 막지 못한다(중첩 저장소의 설정은 위 검사로 막는다).
- `git grep --untracked`는 `.gitignore`를 따르는 것이 기본이지만 비밀정보 파일이 `.gitignore`에 없으면 내용이 검색된다. 비밀정보 보호는 `.gitignore`가 아니라 경로 인자 검사와 권한 deny 규칙에 기대며, 검색어가 가리키는 파일을 훅이 알 수는 없다.
- 프로젝트 안에서 밖을 가리키는 심볼릭 링크는 git 경로 인자에서 따로 해석하지 않는다. git이 링크 너머 경로를 거부하는 동작에 기댄다(추정, 미검증).
- 세션 작업 폴더가 프로젝트 안의 `git worktree`(`.git` 파일 보유)이고 `CLAUDE_PROJECT_DIR`가 바깥 저장소이면 git이 중첩 저장소로 판단돼 차단된다. 안전한 쪽 오탐이다.
- `uv run`은 `.venv`를 만들거나 동기화하고, 프로젝트의 로컬 빌드 코드(빌드 백엔드)를 실행하며, 네트워크로 패키지를 받을 수 있다. 훅은 이를 막지 못한다. `uv run` 없이 `pytest`를 직접 쓸 수 있으면 그쪽이 부작용이 적다.
- pytest는 테스트 코드, `conftest.py`, `pytest.ini`/`pyproject.toml`의 설정(`addopts` 포함)을 실행·적용한다. 위 "pytest 실행 위험"과 같은 이유로 막지 못한다.
- ruff·mypy·pyright는 프로젝트의 설정 파일을 읽는다. 설정 파일이 바뀐 변경이면 먼저 설정 파일을 읽는다.

## 대안
| 대안 | 채택하지 않은 이유 |
| --- | --- |
| 리뷰어 Bash 전체 허용 | 읽기 전용 검토라는 역할 분리(HIR-0001)가 무너지고, 리뷰어가 코드를 고치거나 파일을 지울 수 있다 |
| 훅 없이 프롬프트로만 "읽기 전용 명령만 쓰라"고 안내 | 프롬프트는 강제되지 않는다. 훅을 도입한 이유가 이것이다 |
| 테스트 실행을 메인 세션·implementer에만 맡기고 리뷰어는 보고서를 신뢰 | 리뷰어가 구현자 보고를 독립적으로 확인하지 못한다. `scripts/check.sh`만으로 부족한 프로젝트가 있다 |
| 프로젝트별 허용 명령 설정 파일을 두고 훅이 읽기 | 설정 파일이 템플릿 소유 파일과 프로젝트 소유 파일 구분을 복잡하게 만든다. 도구가 늘어나는 것이 확인되면 다시 검토한다 |
| `uv run` 이후 임의 명령 허용 | `uv run python -c ...`로 임의 코드를 실행할 수 있다 |

## 검증
- `template/tests/harness/test_reviewer_bash_guard.py`에 `CLAUDE_PROJECT_DIR`를 쓰는 허용·차단 사례와 없는 경우 검사를 추가했다. 허용 목록 전환 후 리뷰 지적 사례(셸 확장, 경로 인자, 옵션, 중첩 저장소 등)를 모두 차단 사례로 넣었다. 훅은 프로젝트 폴더를 작업 폴더로 실행한다. 임시 프로젝트 폴더를 만들어 프로젝트 밖 경로와 심볼릭 링크 우회를 검증한다.
- 기존 허용·차단 테스트는 `ruff check`에 `--no-fix`가 필수가 된 사례만 기대값을 바꾸고(`--no-fix` 추가) 나머지는 변경 없이 통과한다. 3회차 재현 사례(위)는 모두 차단 사례로, git 허용 사례는 허용 테스트로 추가했다.
- 적용 프로젝트에서 `copier update` 후 하위 폴더 세션의 리뷰어가 `git -C`, check.sh 절대 경로, `uv run --directory <폴더> pytest`를 실행할 수 있는지 확인한다(미확인).

## 알려진 한계
- 허용 도구는 Python 생태계(pytest, ruff, mypy, pyright)뿐이다. 프론트엔드 단계에서 `npm test`, `eslint` 등이 필요하면 별도 HIR로 추가한다.
- 허용 목록이 좁아 `--cov` 같은 플러그인 옵션이나 `-W`, `--ignore` 같은 pytest 옵션은 쓸 수 없다. 필요해지면 별도로 추가한다.
- `git -C`가 아닌 형태(세션 작업 폴더 자체가 중첩 저장소인 경우)는 검사하지 않는다.

## 결과
(운영 후 기록: 훅이 정상 명령을 막은 사례, 테스트 실행 부작용 사례)


## 최종 재검토 이후 보완 (v0.3.0 배포 전)
- **fail closed 보강**: 훅 내부에서 예상하지 못한 예외가 나면 종료 코드 1이 되어 명령이 그대로 실행되던 경로를 막았다. `run()`이 `SystemExit` 외 모든 예외를 차단(종료 코드 2)으로 바꾼다. NUL 문자가 든 명령도 차단한다. 테스트 `FailClosed`.
- **회귀 방지 테스트**: 서브커맨드 앞 전역 옵션(`git -c`, `--git-dir`, `--work-tree`, `-P`, `-C`를 두 번)이 차단됨을 테스트로 고정했다(`GitGlobalOptionsBlocked`).
- **남는 위험 추가**
  - 비밀정보 경로 검사는 명령 인자 문자열만 본다. `.env`나 `secrets/`가 git에 추적되고 있으면 `git diff`, `git log -p`, 경로 없는 `git grep`이 그 내용을 보여 준다. 이 훅은 `.gitignore`와 "비밀 파일을 추적하지 않는다"는 규칙(`scripts/harness-check.sh`가 검사)에 기댄다.
  - 프로젝트 안의 심볼릭 링크가 밖을 가리키면 git 경로 인자 판정에 영향을 줄 수 있다(추정, 미검증).
  - 서브에이전트를 git worktree에서 돌릴 때 `CLAUDE_PROJECT_DIR`가 worktree 자신을 가리키면 정상이다. 바깥 저장소를 가리키고 cwd가 worktree 안이면 중첩 저장소로 보아 git이 차단되므로, 리뷰어는 Read와 `scripts/check.sh`만 쓸 수 있다.
