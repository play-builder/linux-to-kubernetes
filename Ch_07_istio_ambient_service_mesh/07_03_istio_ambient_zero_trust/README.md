# 07_03 — Istio Ambient Zero-Trust

## Step-01: Introduction

### What You'll Learn

* Istio Ambient(`1.30.0`) **Helm 4단계 운영 설치** — `base` → `istiod` → `istio-cni` → `ztunnel`
* **외부 CA 연동** — cert-manager 2계층 PKI를 `cacerts` Secret으로 istiod에 주입
* namespace 라벨 한 줄로 메시 등록 — **사이드카 없이** L4 mTLS 자동 적용 (`PROTOCOL=HBONE`)
* **Zero-Trust L4** — STRICT mTLS + SPIFFE 신원 기반 인가 (default-deny)
* **Waypoint Proxy로 L7 인가** — HTTP method / path 단위 제어
* 차단 계층 구분 — `200`(허용) / `000`(L4 차단) / `403`(L7 차단)

---

## Step-02: Prerequisites

### 사전 코드 — 필요함

이번 Part는 하나의 Hands-on Lab 안에서 **Ambient 운영 설치 → 외부 CA 연동 → Zero-Trust(L4) → Waypoint(L7)** 까지를 순서대로 진행합니다. 

### 환경 요구사항

* ✅ Kubeadm 기반 K8s 클러스터 환경 구축
  참고: [Kubeadm Project Setup](https://github.com/play-builder/linux-to-kubernetes/tree/main/Ch_00_K8s_Kubeadm_Project_Setup)
* ✅ 노드 구성

  | 노드 | 역할 | 인스턴스 타입 | 스펙 |
  |---|---|---|---|
  | `cp` | Control Plane | `t3.large` | 2 vCPU / 8 GiB — istiod 수용 ★ 필수 |
  | `wk1` | Worker | `m4.xlarge` | 4 vCPU / 16 GiB |
  | `wk2` | Worker | `m4.xlarge` | 4 vCPU / 16 GiB |

* ⚠️ **On-Demand 인스턴스로 기동** — Spot을 쓰면 실습 도중 AWS 회수로 환경이 파괴됩니다
* ⚠️ 실습 종료 후 **반드시 `terraform destroy`** — 비용이 계속 증가합니다

---

## Step-02: 노드 상태 및 스펙 확인 (cp)

```bash
# 클러스터 노드 전체 상태 및 역할 조회
kubectl get nodes -o wide
```

```bash
# 노드별 CPU/메모리 용량 및 EC2 인스턴스 타입 동시 조회
kubectl get nodes -o custom-columns='NODE:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type'
```

```bash
# 워커 노드의 실제 할당 가능 자원 조회
kubectl describe node wk1 | grep -A6 "Allocatable:"
```


---

## Step-03: 시스템 컴포넌트 정상 여부 확인

```bash
# kube-system 네임스페이스의 전체 시스템 Pod 상태 조회
kubectl get pods -n kube-system -o wide
```

```bash
# calico-system 네임스페이스의 Calico 컴포넌트 전체 확인
kubectl get pods -n calico-system -o wide
```

```bash
# kube-dns(CoreDNS) 서비스의 ClusterIP 확인
kubectl get svc -n kube-system kube-dns
```

```bash
# 분산 합의용 Lease 객체 조회를 통한 현재 활성 리더 식별
kubectl get lease -n kube-system kube-controller-manager -o jsonpath='{.spec.holderIdentity}{"\n"}'
```


---

## Step-04: 클라이언트 도구 설치 (helm / istioctl)

```bash
# helm v3.21.0 설치
curl -fsSL -o /tmp/helm.tar.gz https://get.helm.sh/helm-v3.21.0-linux-amd64.tar.gz
tar -xzf /tmp/helm.tar.gz -C /tmp && sudo install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm

# 설치 즉시 확인
helm version --short
```

```bash
# istioctl 1.30.0 설치
curl -fsSL -o /tmp/istio.tar.gz https://github.com/istio/istio/releases/download/1.30.0/istio-1.30.0-linux-amd64.tar.gz
tar -xzf /tmp/istio.tar.gz -C /tmp && sudo install -m 0755 /tmp/istio-1.30.0/bin/istioctl /usr/local/bin/istioctl

# 설치 즉시 확인 (--remote=false: 클러스터 조회 없이 로컬 버전만)
istioctl version --remote=false
```

```bash
# kubectl / helm / istioctl 버전 일괄 확인
kubectl version --client -o yaml | grep gitVersion
helm version --short
istioctl version --remote=false
```


---

## Step-05: 레포 clone

```bash
# 레포 clone 후 기준 디렉터리로 이동 (이미 clone했다면 cd만)
git clone https://github.com/play-builder/linux-to-kubernetes.git
cd linux-to-kubernetes/Ch_07_istio_ambient_service_mesh
```


---

## Step-06: 네임스페이스 생성 (shop + PSS restricted)

```bash
bat 07_03_istio_ambient_zero_trust/01-app/01-namespace.yaml
```

```bash
# 네임스페이스 적용
kubectl apply -f 07_03_istio_ambient_zero_trust/01-app/01-namespace.yaml
```

```bash
# PSS 라벨 확인
kubectl get ns shop -o json | jq '.metadata.labels'
```


---

## Step-07: MSA 애플리케이션 배포 (frontend / api)

```bash
bat 07_03_istio_ambient_zero_trust/01-app/02-frontend.yaml
```

```bash
bat 07_03_istio_ambient_zero_trust/01-app/03-api.yaml
```

```bash
# 01-app 폴더 전체 적용 (namespace → frontend → api 순)
kubectl apply -f 07_03_istio_ambient_zero_trust/01-app/
```

```bash
# Pod 상태 + 배치 노드 확인
kubectl get pods -n shop -o wide
```

```bash
# PodDisruptionBudget 상태 확인
kubectl get pdb -n shop
```


---

## Step-08: 메시 적용 전 통신 확인 (기준선)

```bash
bat 07_03_istio_ambient_zero_trust/08-tests/00-nettest.yaml
```

```bash
# 테스트 Pod 배포 → 결과 확인 → 정리
kubectl apply -f 07_03_istio_ambient_zero_trust/08-tests/00-nettest.yaml
kubectl wait --for=condition=Ready pod/nettest -n shop --timeout=30s || true
kubectl logs nettest -n shop
```

```bash
kubectl delete pod nettest -n shop
```


---

## Step-09: CNI Chaining 설치 전 스냅샷 (baseline)

```bash
# 현재 노드의 CNI 설정 디렉토리 확인 (Calico가 깔려 있어야 함)
# Tigera Operator로 설치된 경우 Calico는 calico-system 네임스페이스에 위치
kubectl get pods -n calico-system -l k8s-app=calico-node -o wide
```

```bash
# 설치 전 baseline ① — plugin 체인에 어떤 plugin이 몇 개 있는지 (type만 간단히)
sudo cat /etc/cni/net.d/10-calico.conflist | jq '{name, cniVersion, plugins: [.plugins[].type]}'
```

```bash
# 설치 전 baseline ② — calico plugin 내부 필드까지 전체 확인
sudo cat /etc/cni/net.d/10-calico.conflist | jq '.plugins[0] | {type, ipam, k8s_api_root: .kubernetes.k8s_api_root, policy: .policy.type, log_file_path}'
```


---

## Step-10: Helm 저장소 등록 + values 확인

```bash
# Istio 공식 Helm 저장소 등록 및 갱신
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update istio
```

```bash
# values 파일 4개 존재 확인
ls -la 07_03_istio_ambient_zero_trust/02-helm-values/
```


---

## Step-11: Helm ① base 설치 (CRD)

```bash
bat 07_03_istio_ambient_zero_trust/02-helm-values/base-values.yaml
```

```bash
# istio-system 네임스페이스 생성 후 base 설치
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
helm install istio-base istio/base \
  -n istio-system \
  --version 1.30.0 \
  -f 07_03_istio_ambient_zero_trust/02-helm-values/base-values.yaml \
  --wait
```

```bash
# base가 등록한 Istio 자체 CRD 개수 확인 (*.istio.io 도메인)
kubectl get crd | grep "istio.io" | wc -l
```


---

## Step-12: Gateway API CRD 설치

```bash
# Gateway API CRD 설치 (없을 때만 — 멱등). ambient waypoint는 experimental 채널 사용
GATEWAY_API_VERSION=v1.5.1
kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 ||   kubectl apply --server-side -f   "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml"
```

```bash
# Istio CRD와 Gateway API CRD를 각각 확인
echo "[Istio CRD]";       kubectl get crd | grep "istio.io" | wc -l
echo "[Gateway API CRD]"; kubectl get crd | grep "gateway.networking.k8s.io" | wc -l
```


---

## Step-13: Helm ② istiod 설치 (Control Plane + HA)

```bash
# istiod values 확인 (HA 관련 핵심 설정)
grep -A2 "autoscale\|cpu:\|podAntiAffinity\|replicaCount" 07_03_istio_ambient_zero_trust/02-helm-values/istiod-values.yaml | head -25
```

```bash
# meshConfig의 extensionProviders 정의 확인
grep -A9 "extensionProviders" 07_03_istio_ambient_zero_trust/02-helm-values/istiod-values.yaml
```

```bash
# istiod 컨트롤 플레인 설치
helm install istiod istio/istiod \
  -n istio-system \
  --version 1.30.0 \
  -f 07_03_istio_ambient_zero_trust/02-helm-values/istiod-values.yaml \
  --wait
```

```bash
# istiod Pod 배치 + HPA + PDB 동시 확인
kubectl get pods -n istio-system -l app=istiod -o wide
kubectl get hpa,pdb -n istio-system
```


---

## Step-14: Helm ③ istio-cni 설치 (Node Traffic Redirect)

```bash
# cni values 확인 (로그 키와 ambient 활성화)
bat 07_03_istio_ambient_zero_trust/02-helm-values/cni-values.yaml | grep -A2 "logging\|ambient"
```

```bash
# istio-cni 설치
helm install istio-cni istio/cni \
  -n istio-system \
  --version 1.30.0 \
  -f 07_03_istio_ambient_zero_trust/02-helm-values/cni-values.yaml \
  --wait
```

```bash
# cni DaemonSet이 모든 노드에 배치됐는지 확인
kubectl get daemonset istio-cni-node -n istio-system
```


---

## Step-15: CNI Chaining 설치 후 변화 확인

```bash
# 설치 후 conflist 원본 전체 확인 (root 권한 필요 — sudo 없으면 Permission denied)
sudo bat /etc/cni/net.d/10-calico.conflist
```

```bash
# plugin 체인 구성만 추출 (baseline: calico, portmap 2개였음)
sudo cat /etc/cni/net.d/10-calico.conflist | jq '[.plugins[].type]'

# 새로 추가된 istio-cni 항목만 추출
sudo cat /etc/cni/net.d/10-calico.conflist | jq '.plugins[] | select(.type=="istio-cni")'
```


---

## Step-16: Helm ④ ztunnel 설치 (Data Plane)

```bash
# ztunnel values 확인 (자원 설정 — CPU limit 없음에 주목)
bat 07_03_istio_ambient_zero_trust/02-helm-values/ztunnel-values.yaml | grep -A6 "resources\|env\|logLevel"
```

```bash
# ztunnel 설치
helm install ztunnel istio/ztunnel \
  -n istio-system \
  --version 1.30.0 \
  -f 07_03_istio_ambient_zero_trust/02-helm-values/ztunnel-values.yaml \
  --wait
```

```bash
# ztunnel DaemonSet이 모든 노드에 배치됐는지 확인
kubectl get daemonset ztunnel -n istio-system -o wide
```

```bash
# 4개 차트 설치 상태 + 컨트롤↔데이터 플레인 동기화 확인
helm ls -n istio-system
istioctl version
```


---

## Step-17: cert-manager 설치

```bash
# cert-manager 설치 (OCI 차트, CRD 포함) — 공식 문서 권장 방식
helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  -n cert-manager --create-namespace \
  --version v1.20.2 \
  --set crds.enabled=true \
  --wait
```

```bash
# cert-manager 핵심 3개 Pod 정상 기동 확인
kubectl get pods -n cert-manager
```


---

## Step-18: PKI 체인 발급 (Root → Intermediate)

```bash
bat 07_03_istio_ambient_zero_trust/03-pki/01-cert-manager-pki.yaml
```

```bash
# PKI 체인 발급
kubectl apply -f 07_03_istio_ambient_zero_trust/03-pki/01-cert-manager-pki.yaml
```

```bash
# Intermediate CA가 Ready 상태가 될 때까지 대기 후 확인
kubectl wait --for=condition=Ready certificate/istio-intermediate-ca \
  -n istio-system --timeout=120s
kubectl get certificate istio-intermediate-ca -n istio-system
```


---

## Step-19: Secret → istiod 형식 4개 파일 변환

```bash
# 원본 Secret 존재 및 키 개수 확인
kubectl get secret istio-intermediate-ca-secret -n istio-system
```

```bash
kubectl get secret istio-intermediate-ca-secret -n istio-system -o json
```

```bash
# 안전한 임시 디렉토리 생성
TMPDIR=$(mktemp -d)
echo "임시 디렉토리: $TMPDIR"
```

**① `tls.crt` → `ca-cert.pem` (Intermediate CA 인증서)**

```bash
# Secret 안의 tls.crt 필드를 base64 인코딩 상태 그대로 조회
kubectl get secret istio-intermediate-ca-secret -n istio-system \
  -o jsonpath='{.data.tls\.crt}'
```

```bash
# base64 디코딩하여 PEM 형식 인증서로 변환
kubectl get secret istio-intermediate-ca-secret -n istio-system \
  -o jsonpath='{.data.tls\.crt}' | base64 -d
```

```bash
# 디코딩 결과를 openssl로 해석 — Subject / Issuer / 유효기간 확인
kubectl get secret istio-intermediate-ca-secret -n istio-system \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -subject -issuer -dates
```

```bash
# 디코딩 결과를 istiod가 요구하는 이름(ca-cert.pem)으로 저장
kubectl get secret istio-intermediate-ca-secret -n istio-system \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TMPDIR/ca-cert.pem"
echo "ca-cert.pem 저장 완료"
```

```bash
# 저장된 파일 내용 확인
bat "$TMPDIR/ca-cert.pem"
```

**② `tls.key` → `ca-key.pem` (Intermediate CA 개인키)**

```bash
# Secret 안의 tls.key 필드를 base64 인코딩 상태 그대로 조회
kubectl get secret istio-intermediate-ca-secret -n istio-system \
  -o jsonpath='{.data.tls\.key}'
```

```bash
# 디코딩 결과를 istiod가 요구하는 이름(ca-key.pem)으로 저장 (화면 출력 안 함)
kubectl get secret istio-intermediate-ca-secret -n istio-system \
  -o jsonpath='{.data.tls\.key}' | base64 -d > "$TMPDIR/ca-key.pem"
echo "ca-key.pem 저장 완료"
```

```bash
# 개인키 전체 확인 (실습 후 클러스터째 폐기 전제 — 운영에서는 head -1로 헤더만)
bat "$TMPDIR/ca-key.pem"
```

**③ `ca.crt` → `root-cert.pem` (Root CA 인증서)**

```bash
# Secret 안의 ca.crt 필드를 base64 인코딩 상태 그대로 조회
kubectl get secret istio-intermediate-ca-secret -n istio-system \
  -o jsonpath='{.data.ca\.crt}'
```

```bash
# 디코딩 결과를 istiod가 요구하는 이름(root-cert.pem)으로 저장
kubectl get secret istio-intermediate-ca-secret -n istio-system \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > "$TMPDIR/root-cert.pem"
echo "root-cert.pem 저장 완료"
```

```bash
# 저장된 Root CA 파일 내용 확인 (subject / issuer / 유효기간 같이 확인)
openssl x509 -in "$TMPDIR/root-cert.pem" -noout -subject -issuer -dates
```

**④ `cert-chain.pem` 생성 (단일 Intermediate 특수 케이스)**

```bash
# cert-chain.pem = ca-cert.pem 복사 (단일 Intermediate 구조)
cp "$TMPDIR/ca-cert.pem" "$TMPDIR/cert-chain.pem"
echo "cert-chain.pem 생성 완료"
```

```bash
# 4개 파일이 모두 준비됐는지 확인
ls -1 "$TMPDIR"
```


---

## Step-20: cacerts Secret 생성 및 istiod CA 교체

```bash
# 4개 파일로 cacerts Secret 생성
kubectl create secret generic cacerts -n istio-system \
  --from-file=ca-cert.pem="$TMPDIR/ca-cert.pem" \
  --from-file=ca-key.pem="$TMPDIR/ca-key.pem" \
  --from-file=root-cert.pem="$TMPDIR/root-cert.pem" \
  --from-file=cert-chain.pem="$TMPDIR/cert-chain.pem"
```

```bash
# 생성된 cacerts의 4개 키 확인
kubectl get secret cacerts -n istio-system -o jsonpath='{.data}' | jq 'keys'
```

```bash
# 임시 파일 정리
rm -rf "$TMPDIR"
```

```bash
# istiod에 cacerts 볼륨 + 마운트가 있는지 확인 (chart 기본 포함)
kubectl get deploy istiod -n istio-system -o json \
  | jq '.spec.template.spec.volumes[] | select(.name=="cacerts")'
```

```bash
# istiod 재시작 (cacerts 로드)
kubectl rollout restart deployment/istiod -n istio-system
kubectl rollout status deployment/istiod -n istio-system --timeout=120s
```

```bash
# cacerts Secret 존재 + 키 4개 포함 여부 확인
kubectl get secret cacerts -n istio-system
```


---

## Step-21: ambient 라벨 부착 (메시 등록)

```bash
istioctl ztunnel-config workload --workload-namespace shop
```

```bash
# shop 네임스페이스를 ambient mesh에 편입 (--overwrite로 재실행해도 안전)
kubectl label namespace shop istio.io/dataplane-mode=ambient --overwrite
```

```bash
# 이미 떠 있던 워크로드를 ambient 경로로 확실히 편입 (TCP → HBONE)
kubectl rollout restart deployment/frontend deployment/api -n shop
kubectl rollout status deployment/frontend -n shop --timeout=120s
kubectl rollout status deployment/api -n shop --timeout=120s
```

```bash
# ztunnel이 shop 워크로드를 인식하는지 확인
# 주의: -n/--namespace 가 아니라 --workload-namespace 사용
istioctl ztunnel-config workload --workload-namespace shop
```


---

## Step-22: mTLS 자동 적용 확인

```bash
bat 07_03_istio_ambient_zero_trust/08-tests/01-mtls-test.yaml
```

```bash
# 1. 검증 Pod 배포
kubectl apply -f 07_03_istio_ambient_zero_trust/08-tests/01-mtls-test.yaml

# 2. Pod 실행 완료(Succeeded) 상태까지 대기 (최대 60초)
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
  pod/mtls-test -n shop --timeout=60s

# 3. 실행 로그 확인 (200 OK 여부)
kubectl logs mtls-test -n shop
```

```bash
# 4. 검증용 Pod 정리
kubectl delete pod mtls-test -n shop
```


---

## Step-23: ztunnel 메트릭으로 mTLS 검증

```bash
# (시도) ztunnel 컨테이너 안에서 직접 메트릭 조회 — 실패 원인을 확인하기 위한 단계
ZTUNNEL=$(kubectl get pod -n istio-system -l app=ztunnel -o jsonpath='{.items[0].metadata.name}')
kubectl exec $ZTUNNEL -n istio-system -- \
  curl -s localhost:15020/stats/prometheus | grep 'istio_tcp_connections_opened_total' | grep 'mutual_tls' | head -2
```

```bash
bat 07_03_istio_ambient_zero_trust/08-tests/08-traffic-gen.yaml
```

```bash
kubectl apply -f 07_03_istio_ambient_zero_trust/08-tests/08-traffic-gen.yaml
kubectl wait --for=condition=Ready pod/traffic-gen -n shop --timeout=30s
sleep 5
```

```bash
FRONTEND_NODE=$(kubectl get pod -n shop -l app=frontend -o jsonpath='{.items[0].spec.nodeName}')
ZTUNNEL=$(kubectl get pod -n istio-system -l app=ztunnel \
  --field-selector spec.nodeName=$FRONTEND_NODE \
  -o jsonpath='{.items[0].metadata.name}')
echo "frontend 노드: $FRONTEND_NODE / 대상 ztunnel: $ZTUNNEL"
```

```bash
# 1) 백그라운드 port-forward 실행
kubectl -n istio-system port-forward $ZTUNNEL 15020:15020 >/dev/null 2>&1 &
PF_PID=$!

# 2) port-forward 포트가 준비될 때까지 헬스체크 대기 (최대 10초)
for i in $(seq 1 10); do curl -s localhost:15020/stats/prometheus >/dev/null 2>&1 && break; sleep 1; done

# 3) mTLS 연결 메트릭 조회 (connection_security_policy 라벨 추출)
curl -s localhost:15020/stats/prometheus | grep 'istio_tcp_connections_opened_total' | grep 'mutual_tls' | head -2
```

```bash
kill $PF_PID
kubectl delete pod traffic-gen -n shop
```


---

## Step-24: STRICT mTLS 강제

```bash
bat 07_03_istio_ambient_zero_trust/04-security/01-peer-authentication.yaml
```

```bash
kubectl apply -f 07_03_istio_ambient_zero_trust/04-security/01-peer-authentication.yaml
```


---

## Step-25: L4 인가 정책 적용 (default-deny flip)

```bash
bat 07_03_istio_ambient_zero_trust/04-security/02-authorization-policy.yaml
```

```bash
# L4 ALLOW 정책 적용 (api 워크로드 → default-deny flip)
kubectl apply -f 07_03_istio_ambient_zero_trust/04-security/02-authorization-policy.yaml
```


---

## Step-26: Zero-Trust 검증 — 허용 / 거부

**① 허용된 경로 — frontend → api (`200` 기대)**

```bash
bat 07_03_istio_ambient_zero_trust/08-tests/02-authz-allow.yaml
```

```bash
# frontend 신원으로 api 호출 → 200 기대
kubectl apply -f 07_03_istio_ambient_zero_trust/08-tests/02-authz-allow.yaml
kubectl wait --for=condition=Ready pod/authz-allow -n shop --timeout=30s || true
```

```bash
kubectl logs authz-allow -n shop
kubectl delete pod authz-allow -n shop
```

**② 거부된 경로 — 다른 신원의 직접 호출 (`000` 기대)**

```bash
bat 07_03_istio_ambient_zero_trust/08-tests/03-authz-deny.yaml
```

```bash
# default 신원으로 api 직접 호출 → 000(연결 거부) 기대
kubectl apply -f 07_03_istio_ambient_zero_trust/08-tests/03-authz-deny.yaml
kubectl wait --for=condition=Ready pod/authz-deny -n shop --timeout=30s || true
sleep 8
```

```bash
kubectl logs authz-deny -n shop
```

```bash
kubectl delete pod authz-deny -n shop
```


---

## Step-27: Waypoint Proxy 배포 (L7 진입점)

```bash
# Gateway API CRD 존재 확인 — 없으면 설치 (앞서 설치했다면 통과)
GATEWAY_API_VERSION=v1.5.1
kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 && echo "Gateway API CRD 준비됨 ✅" ||   kubectl apply --server-side -f   "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml"
```

```bash
bat 07_03_istio_ambient_zero_trust/05-waypoint-l7/01-api-waypoint.yaml
```

```bash
# waypoint 배포
kubectl apply -f 07_03_istio_ambient_zero_trust/05-waypoint-l7/01-api-waypoint.yaml
```

```bash
# waypoint가 Programmed 상태가 될 때까지 대기 후 확인
kubectl wait --for=condition=Programmed gateway/api-waypoint -n shop --timeout=120s
istioctl waypoint status --namespace shop
```


---

## Step-28: 서비스를 Waypoint에 연결

```bash
# api 서비스를 waypoint 사용하도록 라벨 부착
kubectl label service api -n shop istio.io/use-waypoint=api-waypoint
```

```bash
# 라벨 부착 위치 확인
kubectl get svc api -n shop --show-labels
```

```bash
# api 서비스가 waypoint를 사용하는지 확인 (--service-namespace 주의)
istioctl ztunnel-config service --service-namespace shop | grep api
```

```bash
# 워크로드 테이블 확인 (Pod 쪽 WAYPOINT는 None이 정상)
istioctl ztunnel-config workload --workload-namespace shop
```


---

## Step-29: ztunnel L4 정책 갱신 (Waypoint 신원 허용)

```bash
# 앞서 만든 L4 정책이 허용 중인 신원 확인
kubectl get authorizationpolicy allow-frontend-to-api -n shop -o yaml | grep -A3 principals
```

```bash
# waypoint가 사용하는 ServiceAccount 확인
kubectl get deploy api-waypoint -n shop -o jsonpath='{.spec.template.spec.serviceAccountName}{"\n"}'
```

```bash
# 수정된 L4 정책 적용
kubectl apply -f 07_03_istio_ambient_zero_trust/04-security/02-authorization-policy.yaml
```


---

## Step-30: L7 인가 정책 적용

```bash
bat 07_03_istio_ambient_zero_trust/05-waypoint-l7/02-api-l7-authz.yaml
```

```bash
# L7 정책 적용
kubectl apply -f 07_03_istio_ambient_zero_trust/05-waypoint-l7/02-api-l7-authz.yaml
```


---

## Step-31: L7 정책 검증 — 허용 / 거부

**① 허용된 경로 (`200` 기대)**

```bash
bat 07_03_istio_ambient_zero_trust/08-tests/04-l7-allow.yaml
```

```bash
kubectl apply -f 07_03_istio_ambient_zero_trust/08-tests/04-l7-allow.yaml
kubectl wait --for=condition=Ready pod/l7-allow -n shop --timeout=30s || true
```

```bash
kubectl logs l7-allow -n shop
kubectl delete pod l7-allow -n shop
```

**② 거부된 경로 — 정책에 없는 경로 (`403` 기대)**

```bash
bat 07_03_istio_ambient_zero_trust/08-tests/05-l7-deny.yaml
```

```bash
# GET /orders (미허용 경로) → 403 기대
kubectl apply -f 07_03_istio_ambient_zero_trust/08-tests/05-l7-deny.yaml
kubectl wait --for=condition=Ready pod/l7-deny -n shop --timeout=30s || true
```

```bash
kubectl logs l7-deny -n shop
kubectl delete pod l7-deny -n shop
```


---

## Step-32: 정리 (Cleanup)

```bash
# 실습 리소스 삭제
kubectl delete namespace shop
helm uninstall ztunnel istio-cni istiod istio-base -n istio-system
helm uninstall cert-manager -n cert-manager
kubectl delete namespace istio-system cert-manager
```

```bash
# AWS 인프라 삭제 (Ch_00 디렉터리에서)
cd Ch_00_K8s_Kubeadm_Project_Setup
terraform destroy --auto-approve
```
