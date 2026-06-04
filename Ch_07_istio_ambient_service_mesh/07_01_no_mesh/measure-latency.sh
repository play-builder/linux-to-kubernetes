#!/usr/bin/env bash
# ============================================================
#
# 사용법 (Control Plane 노드에서):
#   bash measure-latency.sh
#   bash measure-latency.sh 10        # 10번 호출
#   NS=no-mesh bash measure-latency.sh
# ============================================================
set -euo pipefail

NS="${NS:-no-mesh}"                                   # namespace (기본 no-mesh)
COUNT="${1:-5}"                                       # 호출 횟수 (기본 5)
TARGET="http://api.${NS}.svc.cluster.local/"          # 호출 대상 Service

echo "[*] namespace=${NS}, 호출 ${COUNT}회, 대상=${TARGET}"
echo "------------------------------------------------------------"

for i in $(seq 1 "${COUNT}"); do
  kubectl -n "${NS}" exec deploy/client -- \
    curl -s -w "Request ${i}: %{time_total}s\n" -o /dev/null \
    "${TARGET}"
done

echo "------------------------------------------------------------"
echo "[*] 측정 완료."
echo "[!] 핵심: 이 메트릭을 얻으려고 우리가 직접 curl을 짜야 했습니다."
echo "    메시가 있으면 ztunnel이 이런 메트릭을 자동으로 수집합니다."
