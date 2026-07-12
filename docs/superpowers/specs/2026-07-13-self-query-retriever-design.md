# 셀프쿼리 리트리버(Self-Query Retriever) — 공고 의미검색 설계

## 배경 / 목적

기존 04-search 워크플로우는 gemma가 자연어를 SQL로 바꾸는 text-to-SQL 방식이며, 본문 검색이 `title/summary ILIKE '%키워드%'`라 글자가 겹쳐야만 매칭된다. 그래서 "프롬프트 엔지니어링"을 검색할 때, JD에는 "LLM 서비스 개발, RAG 파이프라인"이라고만 적혀 있으면 의미상으로는 맞는데도 0건이 나오는 한계가 있었다.

이를 해결하기 위해 **임베딩 기반 의미 검색**을 추가한다. Self-query retriever는 LLM이 질문을 (의미 검색어 + 구조적 필터)로 분해해 벡터스토어에 질의하는 패턴이다. 이 프로젝트는 이미 text-to-SQL로 "구조적 필터" 절반을 갖고 있으므로, 없는 절반인 **벡터(의미) 검색**을 pgvector로 추가하는 것이 핵심이다.

## 임베딩 모델 결정 (2026-07 조사 기반)

- **선정: KURE-v1 (고려대 NLP랩, GGUF 포맷).** 한국어 검색 특화 모델로 다국어/상용 모델을 한국어 벤치마크에서 압도한다. BGE-M3를 한국어로 파인튜닝한 상위호환이며 1024차원이다.
- **후보 비교:**
  - Qwen3-Embedding-0.6B — 다국어 SOTA이고 경량이지만 한국어는 KURE보다 약하다. 또한 MLX 임베딩은 LM Studio 인식 버그가 있어 GGUF를 사용한다.
  - BGE-M3 — 프로덕션 표준이지만 KURE의 베이스 모델이다.
  - 우리 태스크는 100% 한국어 공고 검색이므로 언어 특화 모델이 유리하다.
- **서빙:** 맥 호스트의 LM Studio, OpenAI 호환 `POST /v1/embeddings`. 컨테이너에서는 `host.docker.internal:1234`로 접속한다. GGUF 포맷을 사용해 MLX 임베딩 인식 버그를 회피한다.

## 접근: 단계적(Phase) 하이브리드

### Phase 1 — 순수 의미 검색 (검증용)

기존 04-search는 그대로 두고 06-semantic-search를 새로 만들어 A/B로 품질을 검증한다. 검증 지표: "프롬프트 엔지니어링", "LLM 서비스", "쿠버네티스 인프라" 등으로 키워드검색 vs 의미검색 결과를 비교해 키워드가 놓친 걸 의미검색이 잡는지 확인한다.

### Phase 2 — 하이브리드 self-query (검증 후 04-search 업그레이드)

gemma가 질문을 `JSON {filters:{max_career, tech, location}, semantic_query}`로 분해한다. filters로 WHERE절(하드조건, 파라미터 바인딩)을 구성하고, semantic_query를 KURE로 임베딩해 ORDER BY 벡터거리(소프트)로 정렬한다. 경력/지역 같은 명시적 제약은 반드시 만족(하드)해야 하며, 그 안에서 의미 유사도로 정렬한다. 필터만 / 의미만 / 둘 다인 3가지 경우를 우아하게 처리한다.

## 컴포넌트 설계

### DB (pgvector)

- 이미지: `postgres:16-alpine` → `pgvector/pgvector:pg16` (드롭인 교체, PG16 데이터 호환).
- 마이그레이션(라이브 DB, 373건이 이미 존재하므로 init.sql 재실행이 안 됨 → 수동 적용):
  - `CREATE EXTENSION IF NOT EXISTS vector;`
  - `ALTER TABLE jobs ADD COLUMN IF NOT EXISTS embedding vector(1024);`
  - `CREATE INDEX IF NOT EXISTS idx_jobs_embedding ON jobs USING hnsw (embedding vector_cosine_ops);`
- init.sql에도 동일 내용을 추가한다(신규 셋업 재현성 확보).

### 05-embedder (신규 워크플로우, 스케줄)

DB-as-queue 패턴을 재사용한다.

`SELECT ... WHERE status='done' AND embedding IS NULL LIMIT batchSize` → 임베딩 텍스트(title + summary + tech_stacks) 생성 → LM Studio `/v1/embeddings` 호출 → `UPDATE jobs SET embedding='[...]'::vector WHERE id=...`.

백필(기존 373건)과 상시(새 done)를 한 워크플로우로 처리한다. 워커는 무변경이다. 실패 시 NULL을 유지해 다음 실행에서 재시도한다.

### 06-semantic-search (신규 워크플로우, Chat)

Chat 트리거 → 질문 임베딩(HTTP KURE) → 벡터거리 최근접 검색(읽기전용 롤):

```sql
SELECT company, title, url, min_career, max_career, tech_stacks, summary,
       1 - (embedding <=> $1::vector) AS score
FROM jobs
WHERE status='done' AND embedding IS NOT NULL
ORDER BY embedding <=> $1::vector
LIMIT topK
```

이후 응답 포맷(관련도 score 표시) → 기존 RTF/docx export 재사용. 벡터는 SQL에 float 배열 문자열로 파라미터 바인딩한다(주입 안전, 읽기전용 이중방어).

## 에러 처리

- **임베딩 서버 다운:** 검색 시 임베딩 실패 → 안내 메시지 출력(추후 키워드 폴백 예정).
- **임베딩 안 된 공고:** 의미검색 결과에서 제외하고, 응답에 커버리지를 명시한다.
- **임베딩 실패 공고:** NULL을 유지하고 05-embedder의 다음 실행에서 재시도한다.

## 검증 계획

1. 05-embedder로 373건 전량 백필(embedding IS NULL = 0 확인).
2. 벡터 검색 정상 동작 확인(거리 정렬, score 0~1).
3. 키워드 vs 의미검색 비교표 작성(키워드는 0건인데 의미검색이 관련 공고를 잡는 케이스 입증).

## 향후 (Phase 2 이후)

Workflow B(이메일), 출력 확장(Sheets/Notion). Phase 2 하이브리드는 Phase 1 검증 통과 후 착수한다.
