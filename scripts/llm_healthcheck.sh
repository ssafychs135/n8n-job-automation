#!/bin/bash
# A1 LLM 헬스체크: localhost:1234(caddy 프록시 → lm.chs135.com → 맥 LM Studio) 확인.
# 상태 전환(up↔down) 시에만 Discord 경고 → 스팸 방지. 일시적 실패는 1회 재시도로 걸러냄.
ENVF=/home/ubuntu/n8n-pjt/.env
STATE=/home/ubuntu/.llm_health.state
WEBHOOK=$(grep '^DISCORD_WEBHOOK_URL=' "$ENVF" 2>/dev/null | cut -d= -f2-)

check() { curl -s -o /dev/null -w "%{http_code}" --max-time 20 http://localhost:1234/v1/models; }
code=$(check)
[ "$code" != "200" ] && { sleep 5; code=$(check); }   # 일시 실패 재시도

[ "$code" = "200" ] && now=up || now=down
prev=$(cat "$STATE" 2>/dev/null || echo up)

if [ "$now" != "$prev" ]; then
  if [ "$now" = "down" ]; then
    msg="🔴 **LLM 다운** — 맥 LM Studio(lm.chs135.com) 응답 없음(HTTP ${code}). 맥 전원·절전·LM Studio 실행 확인 필요. A1 파이프라인(요약·분류·임베딩·검색) 중단 상태."
  else
    msg="🟢 **LLM 복구** — 맥 LLM 정상 응답."
  fi
  if [ -n "$WEBHOOK" ]; then
    curl -s -m 15 -H "Content-Type: application/json" -H "User-Agent: Mozilla/5.0" \
      -d "{\"content\":\"${msg}\"}" "$WEBHOOK" >/dev/null
  fi
  echo "$now" > "$STATE"
fi
