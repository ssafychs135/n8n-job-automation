# 채용 공고 수집·요약 자동화 (n8n 학습 프로젝트)

취업 준비 과정을 자동화하면서 **n8n을 실무 수준으로 배우기 위한** 학습용 프로젝트입니다.
IT 채용 사이트(점프잇·원티드)에서 키워드에 맞는 공고를 정기적으로 수집하고,
맥에서 로컬로 돌아가는 LLM으로 요약한 뒤 Markdown 문서로 정리합니다.

## 1. 프로젝트 소개

**무엇을 / 왜**

- **무엇을**: 지정한 키워드(예: `백엔드`, `Node.js`)로 채용 공고를 매일 자동 수집 → 로컬 LLM으로 3줄 요약 + 핵심 자격요건 추출 → Markdown 파일로 저장.
- **왜**: 매일 손으로 채용 사이트를 뒤지는 반복 작업을 없애고, 그 과정에서 n8n의 핵심 개념(트리거·HTTP 요청·데이터 정규화·중복 제거·LLM 연동·파일 출력)을 실제로 굴러가는 워크플로우로 익히기 위해서입니다. 면접에서 "매일 실제로 돌아가는 자동화를 만들었다"고 말할 수 있는 결과물이 됩니다.

**현재 범위와 계획**

이 프로젝트는 3개의 워크플로우로 계획되어 있습니다.

- **Workflow A — 채용 공고 수집·요약** ← **현재 구현된 범위 (이 저장소)**
- Workflow B — 이메일 확인·분류 (이후 계획)
- Workflow C — 메신저 알림·통합 스케줄 (이후 계획)

지금 동작하는 것은 **A 하나**이며, B와 C는 아직 만들어지지 않았습니다.

## 2. 아키텍처

핵심: **LLM은 Docker 밖 맥 호스트에서 돌고, n8n(Docker)은 `host.docker.internal:1234`로 접속**합니다.

```
[맥 호스트 (Apple Silicon M5 / 32GB)]
 │
 ├─ LM Studio
 │    └─ kanana-1.5-8b-instruct-2505-mlx (MLX 4bit) 로드
 │       → OpenAI 호환 로컬 서버 노출 (포트 1234)
 │
 └─ [Docker Desktop]
      └─ n8n 컨테이너 (포트 5678)
           │  AI 요약 노드가 아래 주소로 HTTP 호출
           └─→ http://host.docker.internal:1234/v1/chat/completions
                        (= 맥 호스트의 LM Studio)
```

**왜 `localhost`가 아니라 `host.docker.internal`인가?**
n8n은 Docker 컨테이너 안에서 실행됩니다. 컨테이너 입장에서 `localhost`는 "컨테이너 자기 자신"을 가리키므로, 호스트(맥)에서 도는 LM Studio에 닿지 못합니다. `host.docker.internal`은 컨테이너에서 "맥 호스트"를 가리키는 특별한 이름입니다. (`docker-compose.yml`의 `extra_hosts` 설정으로 활성화됨)

> LLM(MLX)은 Metal에 직접 접근해야 해서 Docker 안에서 돌릴 수 없습니다. 그래서 호스트에서 LM Studio로 실행하고, n8n만 컨테이너에 둡니다.

## 3. 사전 준비물

- **Docker Desktop** (Apple Silicon 지원). n8n 컨테이너를 실행합니다.
- **LM Studio**. 맥 호스트에서 로컬 LLM을 실행합니다.
- **모델: `kanana-1.5-8b-instruct-2505-mlx` (MLX 4bit)** — LM Studio 안에서 검색해 다운로드합니다. 4bit는 약 5GB로 32GB 메모리에 여유롭습니다.
- LM Studio에서 **"Local Server"(Developer/Server 탭)를 켜서 포트 `1234`로 OpenAI 호환 API를 노출**해야 합니다. n8n은 이 서버에 접속합니다.

## 4. 셋업 순서

**a. 환경변수 파일 준비**

```bash
cp .env.example .env
```

(기본값 그대로도 로컬에서 동작합니다. 타임존은 `Asia/Seoul`로 설정되어 있습니다.)

**b. LM Studio 실행 → 모델 로드 → Local Server 시작**

1. LM Studio를 실행하고 `kanana-1.5-8b-instruct-2505-mlx` (MLX 4bit)를 다운로드·로드합니다.
2. Local Server를 **포트 1234**로 시작합니다.
3. 로드된 모델 이름이 워크플로우의 AI 노드가 쓰는 이름(`kanana-1.5-8b-instruct-2505-mlx`)과 일치하는지 확인합니다.

**c. n8n 컨테이너 실행**

```bash
docker compose up -d
```

**d. n8n 접속 및 초기 계정 생성**

브라우저에서 http://localhost:5678 접속 → 최초 1회 관리자 계정을 생성합니다.

**e. 워크플로우 import**

n8n UI에서 **Import from File**을 선택해 `workflows/job-collection.json`을 불러옵니다.
(순수 HTTP 노드로 LLM을 호출하므로 별도 자격증명 설정 없이 import 직후 동작합니다.)

**f. 수동 실행으로 테스트**

워크플로우 화면에서 **Execute Workflow**로 한 번 돌린 뒤, 결과 파일을 확인합니다.

```bash
cat data/output/jobs-summary.md
```

(컨테이너의 `/data/output`이 호스트의 `./data/output`에 매핑되어 있어 바로 열립니다.)

## 5. 워크플로우 노드 흐름

`workflows/job-collection.json`의 실제 노드 순서입니다.

| # | 노드 이름 | 하는 일 |
|---|-----------|---------|
| 1 | **매일 09시 트리거** | Schedule Trigger. 매일 오전 9시(cron `0 9 * * *`)에 워크플로우 시작. |
| 2 | **설정 (Config)** | `keywords` 배열을 정의(기본 `["백엔드", "Node.js"]`). 검색어를 바꾸는 유일한 지점. |
| 3 | **키워드 분리 (Split Out)** | 키워드 배열을 한 건씩 나눠 키워드별로 뒤 단계를 반복. |
| 4 | **점프잇 목록** | 점프잇 검색 API 호출 → 키워드에 맞는 공고 목록 수집. |
| 5 | **원티드 목록** | 원티드 검색 API 호출 → 키워드에 맞는 공고 목록 수집. (4와 병렬) |
| 6 | **목록 병합 (Merge)** | 두 소스(점프잇/원티드)의 목록 응답을 하나로 합침(append). |
| 7 | **정규화 (Normalize)** | 서로 다른 응답을 공통 스키마 `{source, jobId, company, title, url, minCareer, maxCareer, techStacks[], locations[], closedAt}`로 통일. 점프잇 `title`의 `<span>` 태그도 제거. |
| 8 | **중복 제거 (Dedup)** | 워크플로우 static data에 처리한 공고ID를 기억해 새 공고만 통과. 상세/AI 호출 **앞에** 두어 자원 절약. |
| 9 | **상세 조회 (Detail)** | 새 공고만 상세 API 호출. 소스에 따라 점프잇/원티드 URL을 분기해 JD 본문(주요업무·자격요건·우대사항) 확보. |
| 10 | **AI 입력 준비** | 상세 응답을 소스별로 파싱하고 메타데이터와 합쳐 LLM 프롬프트 문자열 구성(건별 처리). |
| 11 | **AI 요약 (LM Studio)** | `host.docker.internal:1234`의 로컬 LLM에 HTTP POST → 3줄 요약 + 핵심 자격요건 생성. |
| 12 | **Markdown 생성** | 요약 결과와 공고 메타데이터를 하나의 Markdown 문서로 조립 → 파일용 바이너리로 변환. |
| 13 | **파일 저장** | `/data/output/jobs-summary.md`로 저장(호스트 `./data/output/`에 매핑됨). |

> 흐름 요약: 스케줄 → 설정 → 키워드 분리 → 목록 조회(점프잇/원티드) → 병합 → 정규화 → 중복 제거 → 상세 조회 → AI 요약 → Markdown 생성 → 파일 저장

## 6. 커스터마이징

- **검색어 변경**: **설정 (Config)** 노드의 `keywords` 배열만 고치면 됩니다.
  예: `["백엔드", "Node.js", "파이썬"]`. 다른 노드는 건드릴 필요 없습니다.
- **모델 교체**: LM Studio에서 더 좋은 모델(4bit → 8bit, 또는 더 큰 MLX 모델)을 로드하고, **AI 요약 (LM Studio)** 노드의 `model` 값을 그 이름으로 바꾸면 됩니다. 클라우드로 옮기려면 같은 노드의 URL을 OpenAI/Claude 등 OpenAI 호환 엔드포인트로 바꾸고 API 키만 추가하면 됩니다(워크플로우 로직 무변경).

## 7. 알려진 한계 / 주의점

- **맥이 켜져 있을 때만 스케줄이 돕니다.** 상시 가동이 필요해지면 워크플로우를 export → VPS로 import(로직 변경 없음).
- **비공식 API입니다.** 점프잇/원티드가 SPA 내부적으로 쓰는 JSON 엔드포인트를 그대로 호출하므로, 사이트가 개편되면 깨질 수 있습니다. 그때는 **정규화 (Normalize)** 노드(및 해당 HTTP 노드)의 필드 매핑을 실제 응답에 맞춰 수정하면 됩니다.
- **원티드의 경력·기술스택은 목록이 아니라 상세 응답에 있을 수 있어**, 목록 단계에서는 비어 있을 수 있습니다. 상세 조회 단계에서 채워집니다.
- **data/n8n 볼륨 권한**: 맥 Docker Desktop은 보통 자동으로 처리하지만, 간혹 n8n 컨테이너(node/uid 1000)가 `./data/n8n`에 쓰지 못하는 경우가 있습니다. 그럴 땐 해당 폴더 권한을 조정하세요.
  ```bash
  sudo chown -R 1000:1000 ./data/n8n
  ```
- **이 워크플로우는 STARTER입니다.** 첫 import 후 반드시 **수동 실행으로 실제 API 응답을 보고** 노드 파라미터(특히 정규화·상세 조회의 API 필드 매핑)를 검증·조정하세요. 특히 원티드 상세 응답의 필드명은 실측 후 조정이 필요할 수 있습니다.

## 8. 다음 단계

- **Workflow B — 이메일 확인·분류**: 지원 관련 메일을 읽어 분류.
- **Workflow C — 알림·통합 스케줄**: 메신저 알림 및 A/B를 묶는 통합 스케줄.
- **출력 확장**: 현재는 Markdown 파일 하나이지만, 이후 이메일(SMTP) / Google Sheets / Notion으로 출력 채널을 넓힐 계획입니다. 중복 제거도 static data 임시 방식에서 저장소(Sheets/Notion) 기반으로 고도화할 수 있습니다.
