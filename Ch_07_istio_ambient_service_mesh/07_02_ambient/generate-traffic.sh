#!/usr/bin/env bash
# ============================================================
# Lab 2 — 메트릭 생성용 호출 발생 (Generate Traffic)
# ============================================================
# ztunnel이 수집하는 메트릭(istio_tcp_connections_opened_total 등)을
# 채우려면 실제 트래픽이 필요합니다.
# 이 스크립트는 client → api 호출을 지정 횟수만큼 보내
# 메트릭 카운터를 올리는 용도입니다. (응답 본문은 버립니다)
#
# 사용법 (Control Plane 노드에서):
#   bash generate-traffic.sh           # 기본 5회
#   bash generate-traffic.sh 10        # 10회
#   NS=ambient-mesh bash generate-traffic.sh
# ============================================================
set -euo pipefail
NS="${NS:-ambient-mesh}"                              # namespace (기본 ambient-mesh)
COUNT="${1:-5}"                                       # 호출 횟수 (기본 5)
TARGET="http://api.${NS}.svc.cluster.local/"          # 호출 대상 Service

echo "[*] namespace=${NS}, 호출 ${COUNT}회, 대상=${TARGET}"
echo "------------------------------------------------------------"
for i in $(seq 1 "${COUNT}"); do
  kubectl -n "${NS}" exec deploy/client -- \
    curl -s -o /dev/null "${TARGET}"
  echo "    호출 ${i}/${COUNT} 완료"
done
echo "------------------------------------------------------------"
echo "[*] ${COUNT}회 호출 완료 — ztunnel 메트릭 카운터가 그만큼 증가합니다."
echo "[!] 메트릭 확인: bash verify-mtls.sh (또는 port-forward 후 /metrics 조회)"
