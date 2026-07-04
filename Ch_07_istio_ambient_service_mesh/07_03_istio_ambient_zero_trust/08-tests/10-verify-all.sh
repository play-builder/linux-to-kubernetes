#!/usr/bin/env bash
# 07_03_istio_ambient_zero_trust/08-tests/10-verify-all.sh (PROD 추가)
# 핵심 상태 판정 자동화(5종) — jq 필요, 레포 루트에서 실행
set -u
PASS=0; FAIL=0
check() {  # check <이름> <실측값> <기대값>
  if [ "$2" = "$3" ]; then echo "PASS  $1 ($2)"; PASS=$((PASS+1));
  else echo "FAIL  $1 (got=$2 want=$3)"; FAIL=$((FAIL+1)); fi
}
# 1) 동기화 안 된 프록시 수 = 0
check "proxy-sync" \
  "$(istioctl proxy-status | tail -n +2 | grep -cE 'STALE|NOT SENT')" "0"
# 2) 편입 안 된(HBONE 아닌) shop 워크로드 수 = 0
check "hbone-only" \
  "$(istioctl ztunnel-config workloads --workload-namespace shop -o json \
     | jq '[.[] | select(.protocol != "HBONE")] | length')" "0"
# 3) mTLS 모드 = STRICT + 정책 인벤토리 2개
check "strict-mtls" \
  "$(kubectl get peerauthentication -n shop \
     -o jsonpath='{.items[0].spec.mtls.mode}')" "STRICT"
check "authz-inventory" \
  "$(kubectl get authorizationpolicy -n shop --no-headers | wc -l | tr -d ' ')" "2"
# 4) L7 정책이 Service targetRef로 부착
check "l7-targetref" \
  "$(kubectl get authorizationpolicy api-l7-get-only -n shop \
     -o jsonpath='{.spec.targetRefs[0].kind}')" "Service"
# 5) 외부 진입 체인 200
kubectl apply -f "$(dirname "$0")/06-e2e-test.yaml" >/dev/null
kubectl wait --for=condition=Ready pod/e2e-test -n shop \
  --timeout=30s >/dev/null 2>&1
check "e2e-200" "$(kubectl logs e2e-test -n shop | grep -o 'HTTP 200')" "HTTP 200"
kubectl delete pod e2e-test -n shop >/dev/null
echo "----"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
