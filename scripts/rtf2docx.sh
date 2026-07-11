#!/bin/bash
# data/output의 .rtf를 macOS textutil로 .docx 변환 (새/변경된 것만).
DIR="/Users/sunny/n8n-pjt/data/output"
for rtf in "$DIR"/*.rtf; do
  [ -e "$rtf" ] || continue
  docx="${rtf%.rtf}.docx"
  if [ ! -f "$docx" ] || [ "$rtf" -nt "$docx" ]; then
    /usr/bin/textutil -convert docx "$rtf" -output "$docx" 2>/dev/null && echo "$(date '+%Y-%m-%d %H:%M:%S') 변환: $(basename "$docx")"
  fi
done
