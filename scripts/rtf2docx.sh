#!/bin/bash
# data/output의 .rtf → textutil로 .docx 변환 후, docx를 디스코드로 전송.
# launchd 최소 PATH 대비 절대경로 사용.
DIR="/Users/sunny/n8n-pjt/data/output"
ENVF="/Users/sunny/n8n-pjt/.env"
WEBHOOK=$(/usr/bin/grep -E '^DISCORD_WEBHOOK_URL=' "$ENVF" 2>/dev/null | /usr/bin/cut -d= -f2-)
MIME="application/vnd.openxmlformats-officedocument.wordprocessingml.document"
now() { /bin/date '+%Y-%m-%d %H:%M:%S'; }
for rtf in "$DIR"/*.rtf; do
  [ -e "$rtf" ] || continue
  docx="${rtf%.rtf}.docx"
  if [ ! -f "$docx" ] || [ "$rtf" -nt "$docx" ]; then
    /usr/bin/textutil -convert docx "$rtf" -output "$docx" 2>/dev/null || { echo "$(now) 변환실패: $(/usr/bin/basename "$rtf")"; continue; }
    echo "$(now) 변환: $(/usr/bin/basename "$docx")"
    if [ -n "$WEBHOOK" ]; then
      code=$(/usr/bin/curl -s -m 25 -o /dev/null -w "%{http_code}" -X POST "$WEBHOOK" -H "User-Agent: Mozilla/5.0" \
        -F "payload_json={\"content\":\"📎 검색 결과: $(/usr/bin/basename "$docx")\"}" \
        -F "files[0]=@${docx};type=${MIME}")
      echo "$(now) 디스코드 전송 HTTP=$code: $(/usr/bin/basename "$docx")"
    else
      echo "$(now) 웹후크 없음 — 전송 스킵"
    fi
  fi
done
