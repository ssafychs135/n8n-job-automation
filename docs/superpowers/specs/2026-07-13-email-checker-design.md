# 이메일 확인 워크플로우 (Workflow B) — 채용 합격/불합격/면접 분류

## 배경 / 목적
원래 프로젝트 스펙의 Workflow B. 채용 지원 결과 메일(합격/불합격/면접 안내)을 자동으로 읽어 분류하고, DB에 지원 현황을 기록하며 디스코드로 알림한다. 비용 0원(로컬 LLM) 원칙 유지.

## 확정된 결정
- **메일 접근**: IMAP + Gmail 앱 비밀번호 (Google Cloud/OAuth 불필요). n8n Email 트리거(IMAP).
- **대상 범위**: 안 읽은 메일 전부 → 로컬 LLM이 분류(기타는 버림). 키워드 선필터 없음.
- **결과 처리**: `applications` 테이블 기록 + 디스코드 알림.
- **분류 모델**: 로컬 Kanana(비추론, 한국어, 빠름), 구조화 출력(json_schema).

## 아키텍처 — 단일 워크플로우 `07 메일 확인 (Mail Checker)`
메일 결과는 저빈도라 큐 분리 불필요. IMAP 트리거 입구로 한 워크플로우에서 처리.

```
Email 트리거(IMAP, Gmail, 읽음처리 OFF)
  → 준비(Code): message_id·제목·발신·본문 추출 + 중복체크 SQL 생성
  → 중복 체크(Postgres): message_id 이미 있으면 dup=true
  → IF dup=false
      → 분류 준비(Code): LLM 프롬프트 구성
      → LLM 분류(Kanana, json_schema): {status, company, summary}
      → 저장 생성(Code): INSERT SQL (기타는 최소저장)
      → 저장 실행(Postgres, ON CONFLICT DO NOTHING)
      → IF status≠other → 디스코드 알림 → notified_at UPDATE
```

## 분류 (Kanana, json_schema)
```json
{ "status": "pass|reject|interview|other",
  "company": "회사명(모르면 \"\")", "summary": "핵심 한 줄" }
```
- **pass**: 서류/최종 합격 통보
- **interview**: 면접·코딩테스트·과제 등 다음 전형 안내(일정 잡아야 함)
- **reject**: 불합격/탈락
- **other**: 채용 무관, 단순 접수확인, 광고 → 저장은 하되(중복방지용) 알림 안 함

## DB: `applications` 테이블 (신규)
```sql
CREATE TABLE IF NOT EXISTS applications (
  id            BIGSERIAL PRIMARY KEY,
  message_id    TEXT UNIQUE,          -- 이메일 Message-ID (중복 방지 키)
  company       TEXT,
  status        TEXT,                 -- pass|reject|interview|other
  email_subject TEXT,
  email_from    TEXT,
  summary       TEXT,
  received_at   TIMESTAMPTZ,
  notified_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_applications_status ON applications(status);
```
- 라이브 마이그레이션(수동) + init.sql 반영(재현성). jobs_ro에 SELECT 부여(향후 조회용).

## 디스코드 알림 (새 pass/interview/reject만)
`🎉 [회사] 서류 합격` / `📅 [회사] 면접·전형 안내` / `😢 [회사] 불합격` + summary 한 줄.
웹훅 URL은 Config 노드 필드(기존 것 재사용 가능).

## 에러 처리 / 프라이버시
- LLM 실패 → 저장 안 함(message_id 미기록 → 다음 실행 재시도).
- IMAP 끊김 → n8n 트리거 자동 재연결.
- **읽음 상태 안 바꿈**(비침습). 재처리 방지는 DB message_id로.
- message_id 없으면 제목+발신+날짜 해시로 대체 키 생성.
- **로컬 LLM만**(외부 전송 없음). `other` 메일은 message_id·status만 저장(개인메일 제목/본문 미보존).

## 검증 계획
1. 분류 프롬프트를 샘플 메일(합격/불합격/면접 안내/광고)로 사전 검증 — Kanana+json_schema 동작 확인.
2. DB 스키마·UNIQUE 중복방지·ON CONFLICT 검증(psycopg2).
3. IMAP 실연동은 사용자 앱 비밀번호 등록 후 E2E(테스트 메일 1통).

## 사용자 준비물
- Gmail 2단계인증 ON → 앱 비밀번호 발급 → n8n에 IMAP 자격증명(imap.gmail.com:993, SSL, 사용자=메일주소, 비번=앱비번) 등록.
- 디스코드 웹훅 URL(기존 재사용 가능)을 07 Config에 입력.

## 향후
- 04 검색에서 지원현황도 물어보게 확장 가능(applications 테이블 대상).
- 통계(합격률, 전형 단계별 분포) 대시보드.
