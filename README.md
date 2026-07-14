# 로컬 LLM 기반 취업 자동화 시스템

> IT 채용 공고를 **수집·요약·의미검색**하고, 지원 결과 메일을 **자동 분류·알림**하며, 채용 시장을 **분석 리포트**로 뽑는 n8n 자동화 파이프라인. **전부 로컬에서, 비용 0원.**

취업 준비의 반복 작업(공고 탐색·정리, 결과 메일 확인)을 자동화하면서 n8n·벡터검색·로컬 LLM을 실무 수준으로 익히기 위한 프로젝트입니다. 클라우드 API 없이 맥에서 도는 로컬 LLM만으로 요약·분류·임베딩·text-to-SQL을 모두 처리합니다.

## 한눈에

- 🔍 **공고 수집·요약** — 원티드·점프잇에서 공고를 수집하고 로컬 LLM이 요약 (375건 적재)
- 🧠 **하이브리드 의미검색** — pgvector + 임베딩으로 "온디바이스 AI 최적화하는 회사" 같은 자연어 검색. gemma가 질문을 구조필터+의미검색어로 분해하는 self-query 리트리버
- 📧 **지원 결과 자동 분류** — 받은 메일을 로컬 LLM이 합격/불합격/면접/기타로 분류해 디스코드 알림 (메일 링크 포함)
- 📊 **시장 분석 리포트** — 기술스택 수요·경력 분포·소스 비교를 자체완결 HTML 대시보드로 생성
- 💸 **비용 0원** — LM Studio로 로컬 LLM 3종(요약·검색·임베딩) 서빙, 클라우드 API 미사용

## 아키텍처

```
┌─ 맥 호스트 (Apple Silicon M5 / 32GB) ──────────────────────────┐
│                                                                │
│  LM Studio  ──OpenAI 호환 API (:1234)──┐                        │
│   ├ kanana-1.5-8b-instruct (요약·메일분류, 비추론)              │
│   ├ google/gemma-4-e4b     (text-to-SQL·질문분해)              │
│   └ text-embedding-kure-v1 (한국어 임베딩, 1024차원)            │
│                                        │                        │
│  ┌─ Docker ─────────────────────────┐  │                        │
│  │  n8n (:5678) ──HTTP─────────────────┘  host.docker.internal  │
│  │   └ 워크플로우 01~08                                          │
│  │  PostgreSQL 16 + pgvector          ← 공고 큐 · 임베딩 · 지원 │
│  └──────────────────────────────────┘                          │
│                                                                │
│  LaunchAgent (RTF→DOCX 변환·디스코드 전송)                      │
└────────────────────────────────────────────────────────────────┘
```

**왜 이 구조인가**
- **LLM은 Docker 밖 호스트에서** — MLX 모델은 Metal 직접 접근이 필요해 컨테이너 안에서 못 돕니다. 호스트 LM Studio로 서빙하고, 컨테이너의 n8n은 `host.docker.internal:1234`로 접속(`docker-compose.yml`의 `extra_hosts`).
- **모델 교체 가능 설계** — OpenAI 호환 엔드포인트라, 로컬→클라우드 스왑 시 URL·키만 바꾸면 워크플로우 로직 무변경.

## 워크플로우

| # | 이름 | 트리거 | 하는 일 |
|---|------|--------|---------|
| **01** | 수집기 (Collector) | 스케줄(매일 9시) | 원티드·점프잇 공고 수집 → 정규화·직군필터 → `status='pending'` 적재 (LLM 미호출, 빠름) |
| **02** | 워커 (Worker) | 스케줄(5분) | pending 배치 → 상세조회 → **Kanana 요약** → `done` (DB-as-queue 소비) |
| **03** | 알림 (Notifier) | 스케줄(1분) | 새 `done` 공고를 디스코드 임베드로 알림 |
| **04** | 하이브리드 검색 | Chat | **gemma가 질문 분해** → 경력·지역·기술 하드필터(SQL) + **KURE 임베딩 벡터 랭킹** → 관련도순. 집계질문은 text-to-SQL |
| **05** | 임베더 (Embedder) | 스케줄(3분) | `done` 공고를 KURE-v1로 임베딩 → `jobs.embedding` (백필+상시) |
| **06** | 의미검색 (Semantic) | Chat | 순수 벡터 검색 (04에 포섭돼 비활성, 참고용) |
| **07** | 메일 확인 (Mail Checker) | IMAP | 받은 메일 → **Kanana 분류**(합격/불합격/면접/기타) → `applications` 기록 → 디스코드 알림(메일 링크) |
| **08** | 시장 리포트 (Market Report) | 수동 | DB 집계 → 순수 CSS 자체완결 HTML 대시보드 생성 |

## 핵심 기술 결정

- **DB-as-queue** — 단일 워크플로우를 수집기/워커로 분리하고 PostgreSQL `status` 컬럼(pending→done)으로 처리 흐름 관리. 최초 대량 풀스캔의 LLM 속도 불일치·재개·레이트리밋을 이 규모에 맞게 정직하게 해결(Kafka/Redis 과설계 회피).
- **비추론 모델 선택** — 요약·분류엔 추론(reasoning) 모델이 부적합. gemma(추론)는 사고흔적 억제 4전 4패 + 요청당 30초대라, 카카오 **Kanana(비추론)**로 교체해 37초→6초.
- **하이브리드 self-query 리트리버** — 키워드 ILIKE의 한계(글자 안 겹치면 못 찾음)를 pgvector로 해소. "필터는 하드(경력·지역), 의미는 소프트(벡터 랭킹)" 원칙. gemma가 질문 넓이를 보고 **관련도 임계값을 동적 결정**.
- **한국어 특화 임베딩** — 다국어 SOTA(Qwen3) 대신 고려대 **KURE-v1**(BGE-M3 한국어 파인튜닝). 100% 한국어 공고 태스크엔 언어특화가 유리.
- **구조화 출력** — LM Studio `json_schema`로 LLM 응답을 스키마 강제. nullable union 미지원 회피 위해 `-1`/`""` 센티넬 사용.
- **보안** — 자연어검색은 읽기전용 롤(`jobs_ro`) + SELECT-only 검증 + 파라미터 바인딩. 비밀은 `.env`(gitignore), 공개 전 git 히스토리 스크럽.

<details>
<summary><b>디버깅에서 배운 것들 (펼치기)</b></summary>

- **타임아웃 43건** — n8n이 수백 요청을 동시4 LLM에 일괄 전송 → 큐 적체 → axios 기본 300초 초과. 근본해결은 비추론 모델 + DB-as-queue.
- **maxPages 폭발** — 페이지 상한 99999 → 70만 건 시도. paginate-until-empty로 교체.
- **Kanana 템플릿 버그** — `Cannot apply filter selectattr to NullValue` → 요청 body에 `tools: []`로 우회.
- **타임존 직렬화** — n8n Postgres가 `::date`를 UTC 타임스탬프(`T00:00Z`)로 직렬화 → SQL에서 `::text` 캐스팅으로 해결.
- **집계 뻥튀기** — Postgres 노드가 입력 아이템 수만큼 쿼리 반복 → `executeOnce=true`로 1회 실행 보장.
- **회사명 추출** — 추상 지시("회사명")로는 `[네이버]`를 못 뽑음 → few-shot 예시(`"[네이버]"→"네이버"`) 추가로 해결.

</details>

## CI/CD (A1 자체호스팅 Jenkins)

리포가 워크플로우의 진실의 원천인 GitOps. `main` push 시 A1의 Jenkins가 폴링→검증→배포.

- **CI**: 워크플로우 JSON 구조 · shellcheck · python 구문 · `docker compose config` · Caddyfile · gitleaks (병렬 게이트)
- **CD**(통과 시, A1 로컬): `git pull` → `docker compose up -d` → `n8n import:workflow` → `restart`(트리거 재등록) → 스모크(n8n·LLM·DB) → Discord 알림
- Jenkins는 docker.sock으로 host 데몬 제어, `/home/ubuntu/n8n-pjt` 동일경로 마운트로 바인드마운트 경로 일치. 파이프라인은 리포 `Jenkinsfile`(pipeline as code), Jenkins 구성은 JCasC.

## 데이터 모델 (PostgreSQL)

- **`jobs`** — 공고 큐 겸 데이터. `status`(pending/done/skipped/failed), `tech_stacks TEXT[]`, `embedding vector(1024)`(HNSW 코사인 인덱스), `min/max_career`, `UNIQUE(source, job_id)`.
- **`applications`** — 지원 결과. `message_id`(UNIQUE, 중복방지), `status`(pass/reject/interview/other), 회사·요약·수신시각.
- **`jobs_ro`** — 자연어검색 전용 읽기전용 롤.

## 셋업

**사전 준비물**
- Docker Desktop (Apple Silicon)
- LM Studio + 모델 3종: `kanana-1.5-8b-instruct-2505-mlx`, `google/gemma-4-e4b`, `text-embedding-kure-v1` (GGUF). LM Studio에서 검색·다운로드 후 Local Server(:1234) 시작, "Serve on Local Network" ON.

**실행**
```bash
cp .env.example .env          # 비밀번호·웹훅 등 채우기
docker compose up -d          # n8n + Postgres(pgvector) 기동
```
1. http://localhost:5678 접속 → 관리자 계정 생성
2. **자격증명 등록**: Postgres(RW: `postgres`/5432/jobs, RO: `jobs_ro`), 메일용 IMAP(`imap.gmail.com`:993, Gmail 앱 비밀번호)
3. `workflows/*.json` 을 n8n에 import → 노드에 자격증명 연결
4. 검색(04)·메일(07) 워크플로우 활성화

**검색·리포트 써보기**
- 04 검색 채팅: "판교 신입 ML 엔지니어", "쿠버네티스 다루는 시니어", "기술스택 TOP10"
- 08 리포트: `Execute workflow` → `data/output/market-report.html` 열기

## 저장소 구조
```
docker-compose.yml           n8n + Postgres(pgvector)
db/init.sql, roles.sh        스키마·인덱스·읽기전용 롤
workflows/01~08.json         워크플로우 정의
scripts/                     임베딩 백필·검증·RTF→DOCX 변환
docs/superpowers/specs/      각 기능 설계 문서
```

## 한계 / 다음

- 맥이 켜져 있을 때만 스케줄 동작(상시 필요 시 VPS로 export/import, 로직 무변경).
- 비공식 API(원티드·점프잇 내부 JSON) 사용 — 사이트 개편 시 정규화 노드 매핑 조정 필요.
- **다음**: 이력서 기반 공고 적합도 스코어링(임베딩 재사용), 지원 추적 루프(jobs↔applications 연결), 08 스케줄 자동화.

---
*하드웨어: Apple M5 / 32GB · 스택: n8n · PostgreSQL+pgvector · LM Studio(Kanana·gemma·KURE) · Docker*
