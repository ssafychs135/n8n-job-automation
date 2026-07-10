#!/usr/bin/env bash
# 원티드/점프잇 비공식 API가 아직 살아있는지 점검하는 스크립트.
# 워크플로우가 갑자기 빈 결과를 내면 여기부터 돌려 엔드포인트/필드 변화를 확인한다.
# 사용법: ./scripts/test-endpoints.sh [키워드]   (기본값: 백엔드)

set -euo pipefail
KW="${1:-백엔드}"
UA='Mozilla/5.0'
echo "🔎 키워드: $KW"
echo

echo "=== 점프잇 목록 ==="
curl -s -m 15 -H "User-Agent: $UA" \
  "https://jumpit-api.saramin.co.kr/api/positions?keyword=${KW}&sort=relation&page=1" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('result',{}); print('  총', r.get('totalCount'), '건, 첫 공고:', (r.get('positions') or [{}])[0].get('title'))"

echo "=== 원티드 검색 ==="
curl -s -m 15 -H "User-Agent: $UA" \
  "https://www.wanted.co.kr/api/chaos/search/v1/results?query=${KW}&country=kr&job_sort=job.latest_order&limit=5" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); p=d.get('positions',{}).get('data',[]); print('  ', len(p), '건, 첫 공고:', (p or [{}])[0].get('position'))"

echo
echo "✅ 둘 다 결과가 나오면 API 정상. 빈 값이면 정규화 노드의 필드 매핑을 점검할 것."
