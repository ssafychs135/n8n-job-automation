#!/bin/bash
# 자연어검색용 읽기전용 롤. 비밀번호는 환경변수(JOBS_RO_PASSWORD)에서 주입(하드코딩 금지).
# docker-entrypoint-initdb.d에서 init.sql(테이블 생성) 이후 알파벳순으로 실행됨.
set -e
psql -v ON_ERROR_STOP=1 -v ro_pw="${JOBS_RO_PASSWORD}" \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-'EOSQL'
  DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='jobs_ro') THEN
      CREATE ROLE jobs_ro LOGIN;
    END IF;
  END $$;
  ALTER ROLE jobs_ro WITH PASSWORD :'ro_pw';
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -c "GRANT CONNECT ON DATABASE \"$POSTGRES_DB\" TO jobs_ro;" \
  -c "GRANT USAGE ON SCHEMA public TO jobs_ro;" \
  -c "GRANT SELECT ON jobs TO jobs_ro;"
