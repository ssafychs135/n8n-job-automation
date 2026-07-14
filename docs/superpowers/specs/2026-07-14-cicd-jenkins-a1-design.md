# CI/CD — A1 자체 호스팅 Jenkins 파이프라인

## 목적
취업 자동화 스택(n8n + Postgres, OCI A1 배포)에 **CI→CD 파이프라인**을 붙인다.
push 시 검증(CI) → 통과하면 A1에 자동 배포(CD). 워크플로우는 **AI가 리포에 JSON으로 작성**하므로
리포가 진실의 원천(GitOps)이며, CD가 A1 prod n8n에 반영한다.

## 전제 / 확정 사항
- 리포: 공개 `github.com/ssafychs135/n8n-job-automation`, 브랜치 `main`.
- **Jenkins는 A1(129.225.153.248)에 Docker로 자체 호스팅.** 배포 대상과 동일 박스 → CD가 **로컬 작업**(SSH·배포키 불필요).
- **진실의 원천 = 리포의 `workflows/*.json`**(AI 작성). 사람은 UI에서 런타임(검색 실행)만 사용, 편집 안 함.
- **자격증명은 git에 없음**(비밀). A1에 이미 설정됨. A1 n8n DB는 맥 n8n DB의 복사본이라 리포 JSON의 자격증명 ID가 A1과 일치 → import 시 자동 연결(ID 매핑 마찰 없음).
- 공개 노출 0 유지: Jenkins UI는 SSH 포트포워드, 트리거는 **SCM 폴링**(인바운드 웹훅 안 씀).

## 아키텍처
```
AI가 workflows/*.json 작성/수정 → git commit/push → main
        │
        ▼  (SCM 폴링 ~3분)
[A1] Jenkins(Docker, docker.sock 마운트)
  ├─ CI: 6검사 병렬 (하나라도 실패 시 배포 중단)
  └─ CD: (통과 시) git pull → compose up → workflow import → restart → 스모크 → Discord 알림
        │
        ▼
[A1] n8n + Postgres + caddy (prod 스택)   ← 코드로만 반영, UI 편집 금지
사용자는 UI에서 "검색 실행"만 (런타임, 무관)
```

## CI 검증 항목 (배포 전 게이트, 병렬)
| 검사 | 도구 | 잡아내는 것 |
|---|---|---|
| workflow-json | `jq` + 구조 체크 | 깨진 JSON, `nodes`/`connections` 누락, 자격증명 참조 이름 오타 |
| shellcheck | `shellcheck` | `scripts/*.sh`(rtf2docx·keepalive) bash 버그 |
| python | `python -m py_compile` (+ruff 선택) | `scripts/*.py` 구문오류 |
| compose-config | `docker compose config` (base + a1 override) | override `!reset`/`!override` 문법·서비스 정의 오류 |
| caddy-validate | `caddy validate` | 프록시 Caddyfile 오류 |
| secret-scan | `gitleaks`(또는 grep 가드) | 공개 리포에 키·토큰 실수 커밋 방지 |

## CD 단계 (main, CI 통과 후 — A1 로컬 실행)
1. **git pull** — `~/n8n-pjt`(git clone) 최신화. `data/`·`.env`는 gitignore라 보존.
2. **인프라 배포** — `deploy/a1/docker-compose.override.yml`·`caddy/Caddyfile`을 제자리에 배치 → `docker compose up -d`. `scripts/`는 pull로 자동 갱신(systemd 유닛은 절대경로 참조라 재설치 불필요).
3. **워크플로우 import** — `workflows/`를 n8n 컨테이너에 read-only 마운트 → `n8n import:workflow --separate --input=/workflows`(ID 기준 upsert) → `docker compose restart n8n`(active 워크플로우 트리거 재등록; 06/08은 JSON에서 inactive라 유지).
4. **스모크 테스트** — n8n `healthz` 200 · LLM 프록시(`host.docker.internal:1234/v1/models`) 200 · DB 카운트(`jobs`>0) 확인.
5. **Discord 알림** — 성공/실패 결과 통보(기존 `DISCORD_WEBHOOK_URL` 재사용).

## 선행 조건 (일회성 부트스트랩 — 파이프라인 가동 전)
1. **워크플로우 베이스라인 동기화**: A1의 **현재 라이브 워크플로우를 리포로 재export**(`n8n export:workflow --all`)해 커밋. 리포 JSON이 stale하면 첫 import가 옛 버전으로 되돌리므로, GitOps 시작 전 리포=DB 상태를 맞춘다.
2. **`~/n8n-pjt`를 git clone으로 전환**: 현재 tar로 푼 디렉토리를 git 저장소로 초기화(remote 연결 후 `.env`·`data/` 보존한 채 tracked 파일만 정렬). 이후 CD가 `git pull`로 갱신.
3. **미커밋 산출물 커밋**: 방금 만든 `deploy/a1/`, `scripts/rtf2docx_linux.sh`, `scripts/keepalive.sh`를 커밋(현재 untracked).

## 주요 설계 결정
- **Jenkins in Docker + docker.sock 마운트**: CD가 host의 `docker compose`를 제어. 단일 박스라 수용. Jenkins UI 포트는 127.0.0.1 바인딩, 접근은 SSH 포트포워드(`-L 8080`).
- **재활성화는 restart로**: import가 active 필드는 반영하나 트리거 재등록은 컨테이너 restart가 확실.
- **삭제 reconcile 생략(YAGNI)**: 워크플로우 8개 안정적. 리포에서 지워도 DB에 남는 점만 문서화.
- **트리거 = SCM 폴링(~3분)**: 인바운드 웹훅 불필요(공개 노출 0 유지). GitHub 웹훅은 향후 옵션.
- **파이프라인 정의는 리포의 `Jenkinsfile`**(pipeline as code) — 포트폴리오 어필 포인트.

## 컴포넌트 / 산출물
- `Jenkinsfile` (리포 루트) — pipeline 정의(triggers pollSCM, CI 병렬 stages, CD stages, post Discord).
- `deploy/a1/jenkins-compose.yml` — Jenkins 컨테이너(jenkins/jenkins:lts-jdk17, arm64, docker.sock·데이터 볼륨 마운트, 127.0.0.1:8080).
- `ci/validate-workflows.sh` — 워크플로우 JSON 구조 검증 스크립트(CI에서 호출).
- `deploy/a1/docker-compose.override.yml` — n8n에 `./workflows:/workflows:ro` 마운트 추가(import용).
- (문서) README에 CI/CD 섹션 추가.

## 보안 / 주의
- Jenkins UI 공개 노출 금지(127.0.0.1 + SSH 포워드). 초기 admin 비밀번호는 컨테이너 로그에서 1회 확인.
- `docker.sock` 마운트 = Jenkins가 host root 상당 권한. 단일 테넌트 박스라 허용하되 문서화.
- 자격증명·`.env`는 git 미포함 유지. secret-scan CI로 실수 방지.
- Jenkins 데이터 볼륨은 gitignore(자격증명·잡 히스토리 포함).

## 검증 계획
1. CI 각 검사를 의도적으로 깨서(잘못된 JSON·shell 오류·compose 오타) 배포가 **차단**되는지 확인.
2. 정상 커밋 push → 폴링 감지 → CD 전 단계 통과 → A1 반영 + Discord 성공 알림 확인.
3. 워크플로우 JSON 한 줄 수정(예: 알림 문구) push → import·restart 후 실제 반영 확인.
4. 스모크 테스트가 LLM 프록시·DB까지 커버하는지 확인.

## 범위 밖 (향후)
- GitHub 웹훅 기반 즉시 트리거(현재 폴링).
- 워크플로우 삭제 reconcile(desired-state 완전 강제).
- 멀티환경(dev/prod) 분리 — 현재 단일 prod.
- 롤백 자동화(현재 `git revert` + 재배포 수동).
