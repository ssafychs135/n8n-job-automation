#!/bin/bash
# OCI Always Free 유휴회수 방지. 단일 코어를 짧게(40초) 태워 CPU 95백분위를 20% 위로 올린다.
# nice로 최저 우선순위 → n8n 등 실제 작업엔 항상 양보(체감 영향 없음).
nice -n 15 timeout 40 md5sum /dev/zero >/dev/null 2>&1
exit 0
