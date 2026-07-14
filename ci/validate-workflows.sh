#!/bin/bash
# 워크플로우 JSON 구조 검증: 유효 JSON + name + nodes(배열) + connections(객체).
set -uo pipefail
DIR="${1:-workflows}"
shopt -s nullglob
files=("$DIR"/*.json)
[ ${#files[@]} -eq 0 ] && { echo "검증 실패: $DIR 에 워크플로우 JSON 없음"; exit 1; }
rc=0
for f in "${files[@]}"; do
  errs=()
  jq empty "$f" 2>/dev/null || { echo "FAIL 잘못된 JSON: $f"; rc=1; continue; }
  [ -n "$(jq -r '.name // empty' "$f")" ] || errs+=("name 누락")
  [ "$(jq -r '.nodes | type' "$f")" = "array" ] || errs+=("nodes 배열 아님")
  [ "$(jq -r '.connections | type' "$f")" = "object" ] || errs+=("connections 객체 아님")
  if [ ${#errs[@]} -gt 0 ]; then
    printf 'FAIL %s: %s\n' "$(basename "$f")" "$(IFS=', '; echo "${errs[*]}")"; rc=1
  else
    echo "OK $(basename "$f") ($(jq -r .name "$f"), $(jq '.nodes|length' "$f") nodes)"
  fi
done
exit $rc
