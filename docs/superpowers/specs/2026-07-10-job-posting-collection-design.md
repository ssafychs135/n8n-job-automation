# 채용 공고 수집·요약 워크플로우 (Workflow A) — 설계 문서

- **작성일**: 2026-07-10
- **프로젝트 목적**: n8n 실무 경험 습득 + 취업 준비 자동화 (포트폴리오 겸용)
- **이 문서의 범위**: 3개 워크플로우(A 수집·요약 / B 이메일 확인 / C 알림·스케줄) 중 **첫 번째인 A만** 다룬다. B, C는 각자 별도 스펙으로 이어서 작성한다.

---

## 1. 목표 (What & Why)

IT 채용 사이트(원티드·점프짓 등)에서 지정한 키워드에 맞는 채용 공고를 **정기적으로 수집**하고, 로컬 LLM으로 **요약·핵심 추출**한 뒤, 여러 채널(Markdown / 이메일 / Google Sheets / Notion)로 **문서화**한다.

성공하면 "취업 준비 과정 자체를 자동화한, 매일 실제로 돌아가는 n8n 워크플로우"라는 결과물과 서사를 얻는다.

### 비목표 (Non-goals)
- 대형 사이트(사람인·잡코리아·링크드인) HTML 스크래핑 및 봇 차단 우회 — 안정성·법적 리스크로 제외.
- 지원서 자동 제출 등 쓰기(write) 액션 — 이번 범위 아님.
- B(이메일 확인), C(알림)는 이 문서 밖.

---

## 2. 실행 환경

- **n8n**: 로컬 Docker 셀프호스팅 (`docker compose`). 무료, 파일 저장·스케줄·전체 노드 사용 가능.
- **LLM**: 맥 호스트에서 **LM Studio**로 구동하는 **Gemma 4 E4B-it (MLX, 4bit)**. 비용 0원.
  - MLX는 Docker 안에서 못 돈다(Metal 직접 접근 필요) → **호스트에서 실행**, n8n은 Docker 네트워크에서 `host.docker.internal`로 접속.
  - LM Studio가 OpenAI 호환 로컬 서버(`http://localhost:1234/v1`)를 노출 → n8n의 **OpenAI Chat Model 노드**의 base URL만 로컬로 지정. API 키는 임의 값 통과.
- **하드웨어 전제**: Apple M5 / 32GB 통합 메모리. E4B 4bit(~5GB)는 여유. 필요 시 8bit(~10GB)나 더 큰 모델로 스왑 여지 충분.

### 알려진 한계 (정직하게)
- **맥이 켜져 있을 때만** 스케줄이 돈다. 상시 가동이 필요해지면 워크플로우를 export → VPS로 import(로직 변경 없음).
- **E4B는 소형 모델** → A의 한국어 요약 품질/JSON 형식 안정성이 이 프로젝트의 약한 고리. 스왑 가능한 설계로 완화(아래 4-b).

---

## 3. 아키텍처

### 접근 방식
**단일 워크플로우 + Config 노드 패턴** 채택. 흐름을 한눈에 보며 학습하기 좋다.
- *대안(모듈형 서브워크플로우)*은 재사용성이 좋지만 현 단계엔 과설계(YAGNI). B와 공통 로직이 실제로 생기면 그때 분리한다.

### 시스템 구성도
```
[맥 호스트]
 ├─ LM Studio  → Gemma 4 E4B-it MLX 4bit 로드 → OpenAI 호환 API (localhost:1234/v1)
 └─ [Docker] n8n  → OpenAI Chat Model 노드가 host.docker.internal:1234/v1 를 바라봄
```

### 노드 파이프라인
```
[Schedule Trigger]     매일 아침 9시 (cron)
      ↓
[Config (Set)]         keywords: ["백엔드","Node.js"]  ← 이 노드만 고치면 검색어 변경
      ↓
[Split Out]            키워드 배열을 하나씩 반복
      ↓
[HTTP Request]         원티드/점프짓 JSON 엔드포인트 호출 (키워드별)
      ↓
[정규화 (Set/Code)]     공고 → {회사, 제목, 링크, 경력, 기술스택, 공고ID, 마감일}로 통일
      ↓
[Dedup 필터]           이미 본 공고ID 제외 (4-a 참조) — 상세/AI 호출 전에 필터링
      ↓
[HTTP Request (상세)]   새 공고만 상세 API 호출 → JD 본문 확보 (4-c 참조)
      ↓
[AI 요약 (OpenAI 노드→로컬)]  JD → 3줄 요약 + 핵심 자격요건 추출 (새 공고만)
      ↓
[Fan-out 출력]         ┬→ Markdown 파일  (1순위 구현)
                      ├→ 이메일 (SMTP)
                      ├→ Google Sheets
                      └→ Notion DB
```

---

## 4. 핵심 설계 포인트

### (a) 중복 방지 (Dedup) — 필수
없으면 매일 같은 공고를 다시 요약해 스팸이 되고 LLM 자원도 낭비된다.
- 출력 저장소(Google Sheets 또는 Notion)에 저장된 `공고ID` 목록을 조회 → 새 공고만 통과.
- **AI 요약은 새 공고에만** 실행(필터를 요약 앞에 배치) → 자원 절약.
- 초기 단계(저장소가 아직 없을 때)는 n8n의 워크플로우 static data에 최근 처리한 ID를 저장하는 방식으로 임시 대체 가능.

### (b) 모델 교체 가능 설계 (Swappable Model)
n8n AI 노드는 Chat Model만 갈아끼우면 로직은 그대로다.
- 시작: Gemma 4 E4B MLX **4bit** (0원, 빠름).
- 요약 품질이 아쉬우면 LM Studio에서 **8bit → 더 큰 MLX 모델**로 교체, 워크플로우 무변경.
- 최후 수단: OpenAI 호환 노드의 base URL을 클라우드로 바꿔 Claude/OpenAI로 전환 가능.

### (c) 데이터 소스 (원티드/점프잇) — 실측 검증됨 (2026-07-10)

SPA가 호출하는 내부 JSON API를 그대로 사용(HTML 파싱 아님). 아래 엔드포인트는 실제 호출로 200 응답을 확인함. **인증 불필요**, `User-Agent` 헤더만 필요.

**2단계 수집:** ① 목록 API로 키워드에 맞는 공고 리스트(ID) 확보 → ② Dedup으로 새 공고만 추린 뒤 상세 API로 JD 본문 확보 → 요약. 목록만으론 자격요건 본문이 없어 요약이 부실해짐.

| | 원티드 | 점프잇 |
|---|---|---|
| 목록(검색) | `GET www.wanted.co.kr/api/chaos/search/v1/results?query={kw}&country=kr&job_sort=job.latest_order&limit=20` → `positions.data[]` | `GET jumpit-api.saramin.co.kr/api/positions?keyword={kw}&sort=relation&page=1` → `result.positions[]` |
| 상세(JD) | `GET www.wanted.co.kr/api/chaos/jobs/v4/{id}/details?country=kr` → `data.job.detail` | `GET jumpit-api.saramin.co.kr/api/position/{id}` → `result.{responsibility, qualifications, preferredRequirements}` |
| 공고 링크 | `www.wanted.co.kr/wd/{id}` | `jumpit.saramin.co.kr/position/{id}` |

**정규화 공통 스키마:** `{source, jobId, company, title, url, minCareer, maxCareer, techStacks[], locations[], closedAt}`

**주의점:**
- 비공식 엔드포인트 → 사이트 개편 시 깨질 수 있음. URL·필드매핑을 HTTP노드 1개 + 정규화노드 1개에 격리해 수정 지점 최소화.
- 점프잇 `title`/`jobCategory`에 `<span>` 하이라이트 태그가 섞여 옴 → 정규화에서 제거.
- 원티드 `is_outlink=true` 공고는 외부 채용시스템 연결로 상세 본문이 제한적 → 목록 필드로만 요약하거나 스킵.
- 페이지네이션: 원티드 `limit/offset`, 점프잇 `page`. 초기엔 첫 페이지(최근순)만.
- 매너: 상세는 공고당 1요청. Dedup 뒤라 새 공고에만 호출되지만, 노드 사이 짧은 delay로 과호출 방지.

---

## 5. 빌드 순서 (한 번에 다 켜지 않기)

각 단계는 이전 단계가 "돌아가는 것"으로 검증된 뒤 진행한다.

1. `docker compose`로 n8n 기동 + LM Studio에서 Gemma 4 E4B 4bit 로드·서버 켜기 → **연결 확인**(n8n에서 로컬 LLM에 "hello" 요청 성공).
2. Schedule → Config → HTTP → 정규화까지 → **수동 실행으로 정규화된 공고 JSON 확인**.
3. **Markdown 출력** 붙이기 → 1차 "돌아가는 것" 완성. 🎉
4. AI 요약 노드 삽입 → 요약이 붙는지 확인.
5. **Dedup** 추가 → 두 번 실행해도 중복 없음 확인.
6. 이메일 → Google Sheets → Notion 순으로 출력 확장(각 인증 설정은 하나씩).
7. 마지막에 Schedule 활성화.

---

## 6. 성공 기준 (검증 가능)

- [ ] n8n(Docker)이 호스트 LM Studio의 로컬 LLM에 요청해 응답을 받는다.
- [ ] 수동 실행 시 키워드에 맞는 공고가 정규화된 형태의 JSON으로 나온다.
- [ ] 각 새 공고에 3줄 AI 요약 + 핵심 자격요건이 붙는다.
- [ ] 두 번 실행해도 같은 공고가 중복 저장되지 않는다(Dedup 동작).
- [ ] 최소 1개 출력(Markdown)에 결과가 실제로 쌓인다.
- [ ] Schedule로 자동 실행된 흔적이 n8n Executions 로그에 남는다.

---

## 7. 열린 항목 / 이후 스펙으로 넘길 것

- 스케줄 주기: 기본 매일 09:00. 운영하며 조정.
- 출력 확장 우선순위: Markdown → 이메일 → Sheets → Notion (설정 난이도 순).
- 원티드/점프짓 외 추가 IT 소스 편입은 정규화 노드 확장으로 대응.
- **B(이메일 확인·분류)**, **C(메신저 알림·통합 스케줄)** 는 각각 별도 설계 문서로 이어서 작성.
