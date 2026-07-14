#!/bin/bash
# (A1/Linux) data/output의 .rtf → libreoffice headless로 .docx 변환 후 디스코드 전송.
# data/output은 n8n(uid 1000) 소유라 읽기만 하고, DOCX는 ubuntu 소유 OUT에 생성한다.
SRC="/home/ubuntu/n8n-pjt/data/output"
OUT="/home/ubuntu/rtf-docx"
ENVF="/home/ubuntu/n8n-pjt/.env"
WEBHOOK=$(grep -E '^DISCORD_WEBHOOK_URL=' "$ENVF" 2>/dev/null | cut -d= -f2-)
MIME="application/vnd.openxmlformats-officedocument.wordprocessingml.document"
now() { date '+%Y-%m-%d %H:%M:%S'; }
mkdir -p "$OUT"

shopt -s nullglob
for rtf in "$SRC"/*.rtf; do
  base=$(basename "${rtf%.rtf}")
  docx="$OUT/$base.docx"
  # 이미 변환됐고 RTF가 더 최신이 아니면 스킵(중복 전송 방지).
  [ -f "$docx" ] && [ ! "$rtf" -nt "$docx" ] && continue
  if ! soffice --headless --convert-to docx --outdir "$OUT" "$rtf" >/dev/null 2>&1; then
    echo "$(now) 변환실패: $base.rtf"; continue
  fi
  echo "$(now) 변환: $base.docx"
  if [ -n "$WEBHOOK" ]; then
    code=$(curl -s -m 25 -o /dev/null -w "%{http_code}" -X POST "$WEBHOOK" -H "User-Agent: Mozilla/5.0" \
      -F "payload_json={\"content\":\"📎 검색 결과: $base.docx\"}" \
      -F "files[0]=@${docx};type=${MIME}")
    echo "$(now) 디스코드 전송 HTTP=$code: $base.docx"
  else
    echo "$(now) 웹후크 없음 — 전송 스킵"
  fi
done
