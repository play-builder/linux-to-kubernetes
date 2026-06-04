#!/usr/bin/env bash
# ============================================================
# Lab 2 — mTLS 및 SPIFFE 신원 자동 검증
# ============================================================
# Ambient 메시 적용 후, 호출이 mTLS로 보호되고 SPIFFE 신원이
# 자동 부착됐는지를 ztunnel 메트릭으로 확인합니다.
#
# ztunnel 컨테이너에는 curl이 없으므로(Rust 경량 바이너리),
# kubectl port-forward로 15020 포트를 로컬에 연결한 뒤 조회합니다.
#
# 사용법 (Control Plane 노드에서):
#   bash verify-mtls.sh
#   NS=ambient-mesh bash verify-mtls.sh
# ============================================================
set -euo pipefail

NS="${NS:-ambient-mesh}"
TARGET="http://api.${NS}.svc.cluster.local/"

echo "[1/3] ztunnel이 워크로드를 HBONE으로 인식했는지 확인"
echo "------------------------------------------------------------"
istioctl ztunnel-config workload | grep -E "${NS}|NAMESPACE" || true
echo ""

echo "[2/3] 호출 5회 발생 (메트릭 생성용)"
echo "------------------------------------------------------------"
for i in 1 2 3 4 5; do
  kubectl -n "${NS}" exec deploy/client -- \
    curl -s -o /dev/null "${TARGET}"
done
echo "    5회 호출 완료"
echo ""

echo "[3/3] ztunnel 메트릭에서 mTLS 및 SPIFFE 신원 확인"
echo "------------------------------------------------------------"
# ztunnel Pod 하나 선택
ZTUNNEL_POD=$(kubectl -n istio-system get pod -l app=ztunnel \
  -o jsonpath='{.items[0].metadata.name}')

# 15020 포트를 로컬로 port-forward (백그라운드) — 스크립트 종료 시 자동 정리
kubectl -n istio-system port-forward "${ZTUNNEL_POD}" 15020:15020 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "${PF_PID}" 2>/dev/null || true' EXIT
sleep 2   # port-forward 연결 대기

echo "[*] istio_tcp_connections_opened_total 메트릭:"
curl -s localhost:15020/metrics | grep istio_tcp_connections_opened
echo ""
echo "[!] 위 출력에서 다음을 확인하세요:"
echo "    - source_principal / destination_principal (spiffe:// 신원)"
echo "    - connection_security_policy=\"mutual_tls\" (mTLS 증명)"

