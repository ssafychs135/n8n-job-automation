-- 채용 공고 수집 테이블 겸 "작업 큐". Postgres 최초 기동 시 자동 실행된다.
-- 용도: ① 중복 관리(재임포트에도 유지) ② 통계 기초 데이터 ③ DB-as-queue(status로 처리 흐름 관리)
--
-- 흐름:
--   수집기 → 새 공고를 status='pending'으로 INSERT (메타데이터만, LLM 안 부름 → 빠름)
--   워커   → status='pending' 배치로 꺼내 상세조회+요약 → 'done' (연차필터 제외=skipped, 실패=failed)
-- 이 구조로 최초 대량 풀스캔도 재개 가능·레이트리밋되며 처리된다.

-- DB 표시 타임존을 KST로 고정 (TIMESTAMPTZ는 UTC 저장, 표시만 변환됨). 재시작에도 유지.
DO $$ BEGIN EXECUTE format('ALTER DATABASE %I SET timezone TO ''Asia/Seoul''', current_database()); END $$;

CREATE TABLE IF NOT EXISTS jobs (
  id            BIGSERIAL PRIMARY KEY,
  source        TEXT        NOT NULL,          -- 'wanted' | 'jumpit'
  job_id        TEXT        NOT NULL,          -- 사이트별 공고 ID
  company       TEXT,
  title         TEXT,
  url           TEXT,
  min_career    INT,                           -- 최소 요구 경력(년). 무관/미상 = NULL
  max_career    INT,
  tech_stacks   TEXT[],                        -- 통계용 배열 (unnest 로 스택 빈도 집계)
  locations     TEXT,
  summary       TEXT,                          -- AI 요약 (워커가 채움)

  -- === 작업 큐 상태 ===
  status        TEXT        NOT NULL DEFAULT 'pending',  -- pending | done | skipped | failed
  attempts      INT         NOT NULL DEFAULT 0,          -- 처리 시도 횟수(재시도 제한용)

  notified_at   TIMESTAMPTZ,                   -- 메시지 전송 시각 (NULL = 아직 안 보냄)

  closed_at     TIMESTAMPTZ,                   -- 공고 마감일
  collected_at  TIMESTAMPTZ NOT NULL DEFAULT now(),  -- 수집(pending 적재) 시각
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),  -- 마지막 상태 변경 시각

  -- (source, job_id) 조합이 공고 고유키 → 중복 방지 (수집기 재실행/풀스캔에도 안전)
  UNIQUE (source, job_id)
);

-- 워커가 pending을 빠르게 집어오도록 + 통계/조회 성능용 인덱스
CREATE INDEX IF NOT EXISTS idx_jobs_status       ON jobs (status);
CREATE INDEX IF NOT EXISTS idx_jobs_collected_at ON jobs (collected_at);
CREATE INDEX IF NOT EXISTS idx_jobs_source       ON jobs (source);
CREATE INDEX IF NOT EXISTS idx_jobs_notify       ON jobs (status, notified_at);  -- notifier가 미전송 done을 빠르게 집기

-- 참고: 큐/통계 예시 쿼리
--  · 대기 건수:          SELECT status, count(*) FROM jobs GROUP BY status;
--  · 워커 배치 집기:      SELECT * FROM jobs WHERE status='pending' ORDER BY collected_at LIMIT 20;
--  · 기술스택 빈도 TOP:   SELECT s, count(*) FROM jobs, unnest(tech_stacks) s WHERE status='done' GROUP BY s ORDER BY 2 DESC;
--  · 일별 수집량:         SELECT collected_at::date, count(*) FROM jobs GROUP BY 1 ORDER BY 1;

