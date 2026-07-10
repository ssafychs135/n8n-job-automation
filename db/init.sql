-- 채용 공고 수집 기록 테이블. Postgres 최초 기동 시 자동 실행된다.
-- 용도: ① 중복 관리(재임포트에도 유지) ② 통계용 기초 데이터 적재.

CREATE TABLE IF NOT EXISTS jobs (
  id            BIGSERIAL PRIMARY KEY,
  source        TEXT        NOT NULL,          -- 'wanted' | 'jumpit'
  job_id        TEXT        NOT NULL,          -- 사이트별 공고 ID
  company       TEXT,
  title         TEXT,
  url           TEXT,
  min_career    INT,                           -- 최소 요구 경력(년), 무관이면 NULL/0
  max_career    INT,
  tech_stacks   TEXT[],                        -- 통계용 배열 (unnest 로 스택 빈도 집계 가능)
  locations     TEXT,
  summary       TEXT,                          -- AI 요약 본문
  closed_at     TIMESTAMPTZ,                   -- 공고 마감일
  collected_at  TIMESTAMPTZ NOT NULL DEFAULT now(),  -- 수집 시각(통계 트렌드용)
  -- (source, job_id) 조합이 공고의 고유키 → 중복 방지
  UNIQUE (source, job_id)
);

-- 통계·조회 성능용 인덱스
CREATE INDEX IF NOT EXISTS idx_jobs_collected_at ON jobs (collected_at);
CREATE INDEX IF NOT EXISTS idx_jobs_source       ON jobs (source);

-- 참고: 통계 예시 쿼리
--  · 기술스택 빈도 TOP:  SELECT s, count(*) FROM jobs, unnest(tech_stacks) s GROUP BY s ORDER BY 2 DESC;
--  · 일별 수집량:        SELECT collected_at::date, count(*) FROM jobs GROUP BY 1 ORDER BY 1;
--  · 회사별 공고 수:      SELECT company, count(*) FROM jobs GROUP BY 1 ORDER BY 2 DESC;
