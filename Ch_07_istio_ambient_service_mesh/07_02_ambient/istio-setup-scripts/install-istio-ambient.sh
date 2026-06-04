#!/usr/bin/env bash
# ============================================================
# Istio 1.30 Ambient 설치 스크립트 
# ============================================================
#   1 istioctl 다운로드
#   2 Gateway API CRD 설치 (v1.4.0)
#   3 Istio Ambient 프로필 설치
#   4 설치 검증
#
# 실행 위치: Control Plane(cp) 노드
#   aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
#   sudo su - ubuntu
#   bash install-istio-ambient.sh
#
# 환경변수로 버전 변경 가능:
#   ISTIO_VERSION=1.30.0 GATEWAY_API_VERSION=v1.4.0 bash install-istio-ambient.sh
#
# ⚠️ 사전 조건: cp 노드 메모리가 충분해야 istiod가 정상 기동합니다.
#    (t3.medium 4GiB로는 부족할 수 있음 → t3.large 권장.
#     terraform-spec-upgrade/ 가이드 참고)
# ============================================================
set -euo pipefail

ISTIO_VERSION="${ISTIO_VERSION:-1.30.0}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.4.0}"

log()  { echo -e "\n\033[1;36m[$(date +%H:%M:%S)] $*\033[0m"; }
ok()   { echo -e "\033[1;32m  ✔ $*\033[0m"; }
warn() { echo -e "\033[1;33m  ! $*\033[0m"; }

# ------------------------------------------------------------
# 0. 사전 체크 — kubectl이 클러스터에 연결되는지
# ------------------------------------------------------------
log "0. 사전 체크 — 클러스터 연결 확인"
if ! kubectl get nodes >/dev/null 2>&1; then
  echo "✗ kubectl이 클러스터에 연결되지 않습니다. cp 노드에서 실행 중인지 확인하세요." >&2
  exit 1
fi
ok "클러스터 연결 정상"
kubectl get nodes

# ------------------------------------------------------------
# 3.1 istioctl 다운로드 + 설치
# ------------------------------------------------------------
log "3.1 istioctl ${ISTIO_VERSION} 다운로드"
if command -v istioctl >/dev/null 2>&1 && istioctl version --remote=false 2>/dev/null | grep -q "${ISTIO_VERSION}"; then
  ok "istioctl ${ISTIO_VERSION} 이미 설치됨 — 다운로드 건너뜀"
else
  cd "$HOME"
  if [[ ! -d "istio-${ISTIO_VERSION}" ]]; then
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION="${ISTIO_VERSION}" sh -
  fi
  sudo cp "istio-${ISTIO_VERSION}/bin/istioctl" /usr/local/bin/
  ok "istioctl 설치 완료"
fi
istioctl version --remote=false

# ------------------------------------------------------------
# 3.2 Gateway API CRD 설치 (이미 있으면 스킵)
# ------------------------------------------------------------
log "3.2 Gateway API CRD ${GATEWAY_API_VERSION} 설치"
if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  ok "Gateway API CRD 이미 설치됨 — 건너뜀"
else
  kubectl apply --server-side -f \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
  ok "Gateway API CRD 설치 완료"
fi

# ------------------------------------------------------------
# 3.3 Istio Ambient 프로필 설치
# ------------------------------------------------------------
log "3.3 Istio Ambient 프로필 설치"
if kubectl get ns istio-system >/dev/null 2>&1 && \
   kubectl -n istio-system get deploy istiod >/dev/null 2>&1; then
  warn "istio-system에 istiod가 이미 존재 — 재설치(idempotent) 시도"
fi
istioctl install --set profile=ambient -y
ok "istioctl install 명령 완료"

# ------------------------------------------------------------
# 3.4 설치 검증 — 컴포넌트 Ready 대기
# ------------------------------------------------------------
log "3.4 설치 검증 — istiod / ztunnel / istio-cni Ready 대기"

# istiod Ready 대기 (스펙 부족 시 여기서 실패 → 친절 안내)
if ! kubectl -n istio-system rollout status deploy/istiod --timeout=180s; then
  warn "istiod가 정상 기동하지 못했습니다."
  echo "------------------------------------------------------------"
  echo "원인 진단:"
  kubectl -n istio-system get pods -l app=istiod -o wide || true
  echo ""
  kubectl -n istio-system describe pod -l app=istiod | grep -A10 "Events:" || true
  echo "------------------------------------------------------------"
  echo "Pending / OOMKilled 이면 cp 메모리 부족입니다."
  echo "→ terraform-spec-upgrade/ 가이드로 cp를 t3.large로 올린 뒤 재실행하세요." >&2
  exit 1
fi
ok "istiod Ready"

# ztunnel / istio-cni DaemonSet Ready 대기
kubectl -n istio-system rollout status ds/ztunnel --timeout=120s && ok "ztunnel Ready"
kubectl -n istio-system rollout status ds/istio-cni-node --timeout=120s && ok "istio-cni Ready"

# ------------------------------------------------------------
# 최종 상태 출력
# ------------------------------------------------------------
log "설치 완료 — 컴포넌트 배치 확인"
kubectl get pods -n istio-system -o wide

echo ""
ok "Istio ${ISTIO_VERSION} Ambient 설치가 완료되었습니다."
echo "    다음: 본문 §3.3(07_02 README Step-04)으로 가서"
echo "          kubectl apply -f ../ambient-api.yaml -f ../ambient-client.yaml 로 워크로드를 배포하세요."
