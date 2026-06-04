# 07_02_ambient: Istio Ambient 적용 후 재검증 (With Ambient Mesh)

## Step-01: Introduction

### What You'll Learn

* Istio Ambient(`1.30`) 설치: `istioctl` + Gateway API CRD + `profile=ambient` (istiod / ztunnel / istio-cni)
* namespace 라벨 한 줄(`istio.io/dataplane-mode=ambient`)로 메시 등록
* ztunnel 자동 등록 확인: `istioctl ztunnel-config workload`의 `PROTOCOL=HBONE`
* 한계 1 해소 검증: `tcpdump`로 노드 간 트래픽이 `15008`(HBONE) 포트에서 mTLS 암호화됨을 확인
* 한계 2 해소 검증: ztunnel 메트릭의 `source_principal=spiffe://...`로 호출자 신원 자동 부착 확인
* 한계 3 해소 검증: `istio_tcp_connections_opened_total` 카운터로 메트릭 자동 수집 확인
* 애플리케이션 코드를 한 줄도 바꾸지 않고 보안·관찰성이 채워지는 것을 `07_01`과 비교

---

## Step-02: Prerequisites

### 사전 코드 — 필요함

이번 Part는 하나의 Hands-on Lab 안에서 Ambient 설치부터, `07_01`에서 본 세 가지 한계가 메시 적용 후 어떻게 해소되는지를 차례로 재검증합니다.

### 환경 요구사항

* ✅ Kubeadm 기반 K8s 클러스터 환경 구축

  참고: [Kubeadm Project Setup](https://github.com/play-builder/linux-to-kubernetes/tree/main/Ch_00_K8s_Kubeadm_Project_Setup)

* ✅ 노드 구성
  * `cp` (Control Plane) — istiod가 기동하므로 메모리 여유 필요 (`t3.large` 권장)
  * `wk1`
  * `wk2`

* ✅ `07_01_no_mesh` 완료 권장 — 비교 기준선 확보

### 파일 구성

| 파일 | 역할 |
|---|---|
| `ambient-api.yaml` | http-echo 백엔드 + namespace(ambient 라벨) 포함 — 독립 배포형 |
| `ambient-client.yaml` | netshoot 클라이언트 (Deployment) |
| `verify-mtls.sh` | mTLS + SPIFFE 신원 자동 검증 헬퍼 |
| `../scripts/install-istio-ambient.sh` | Istio 1.30 Ambient 설치 자동화 |

---

# 🔬 Hands-on Lab — Ambient 적용 후 재검증

`07_01`에서 확인한 세 가지 한계가, namespace 라벨 한 줄로 Ambient를 적용한 뒤 같은 시나리오에서 어떻게 해소되는지 재현합니다.

---

## Step-01: 노드 스펙 업그레이드 (로컬)

Ch_00 기본 스펙(cp `t3.medium` 4GiB)으로는 istiod 기동에 메모리가 빠듯합니다. Control Plane(cp)을 `t3.large`(8GiB)로 올립니다.

`Ch_00_K8s_Kubeadm_Project_Setup/terraform.tfvars`를 아래와 같이 수정하거나 생성합니다. (기존 파일이 있다면 `instance_type` 두 줄만 추가/수정)

```hcl
# terraform.tfvars — Istio Ambient 실습용 스펙 업그레이드 버전

aws_region   = "ap-northeast-2"
cluster_name = "kubeadm-lab"

# 본인 공인 IP (curl -s ifconfig.me 로 확인)
my_ip = "0.0.0.0/0"

# ── 스펙 업그레이드 (Istio istiod 수용) ─────────────────────────
control_plane_instance_type = "t3.large"    # 2vCPU/8GiB — istiod(~2Gi) + kubeadm control plane  ★ 필수
worker_instance_type        = "t3.medium"   # 2vCPU/4GiB — ztunnel + 앱 Pod + waypoint 여유

# ── 나머지 기본값 (필요 시만 오버라이드) ────────────────────────
# worker_count       = 2
# ebs_volume_size    = 30
# pod_network_cidr   = "10.244.0.0/16"
# kubernetes_version = "1.35"
# calico_version     = "3.31.4"
```

```bash
cd Ch_00_K8s_Kubeadm_Project_Setup
terraform apply    # instance_type 변경은 인스턴스 교체를 유발
```

무엇을 봐야 하나

* cp만 `t3.large`로 올려도 설치 진행 가능 (istiod가 cp에 기동)
* 워커 업그레이드(`t3.small` → `t3.medium`)는 선택
* `user_data`에 `lifecycle { ignore_changes }`가 걸려 있으면 인스턴스 타입만 바뀌고 부트스트랩은 재실행되지 않음

---

## Step-02: Istio 1.30 Ambient 설치 (cp)

레포에 포함된 설치 스크립트로 일괄 실행합니다.

```bash
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - ubuntu

cd linux-to-kubernetes/Ch_07_Ambient_Service_Mesh/scripts
bash install-istio-ambient.sh    # istioctl 1.30 → Gateway API CRD → profile=ambient → Ready 대기
```

무엇을 봐야 하나

* 스크립트 순서: istioctl 다운로드(`1.30.0`) → Gateway API CRD(`v1.4.0`, `--server-side`) → `istioctl install --set profile=ambient` → 컴포넌트 Ready 대기
* istiod가 `Pending`/`OOMKilled`이면 cp 메모리 부족 → Step-01로 스펙 업그레이드 후 재실행

---

## Step-03: 설치 검증 — 컴포넌트 배치 (cp)

```bash
kubectl get pods -n istio-system -o wide
kubectl -n istio-system get ds ztunnel
```

무엇을 봐야 하나

* istiod(Deployment) 1개
* ztunnel(DaemonSet)·istio-cni-node(DaemonSet) — 노드당 1개 (cp/wk1/wk2)

---

## Step-04: 백엔드와 클라이언트 배포 (cp)

매니페스트 맨 위에 Namespace 블록이 있어 `-n` 없이 그대로 배포하면 namespace 생성 + 메시 등록 + 배포가 한 번에 됩니다.

```bash
cd ../07_02_ambient
cat ambient-api.yaml    # 맨 위 Namespace에 istio.io/dataplane-mode: ambient 라벨

kubectl apply -f ambient-api.yaml -f ambient-client.yaml
kubectl -n ambient-mesh get pods -o wide
```

무엇을 봐야 하나

* api=`wk1`, client=`wk2`, 둘 다 `1/1 Running`
* 사이드카 모드라면 `2/2`였겠지만 Ambient는 `1/1` — 메시 적용이 파드 구조에 드러나지 않음

---

## Step-05: 자동 등록 — ztunnel이 워크로드 인식 (cp)

```bash
istioctl ztunnel-config workload | grep -E "ambient-mesh|NAMESPACE"
```

무엇을 봐야 하나

* `PROTOCOL` 컬럼이 `HBONE` — ztunnel 간 mTLS 터널 프로토콜. 표시되면 해당 워크로드가 자동 mTLS 대상 (Istio 공식 검증 방법)
* `WAYPOINT` 컬럼은 `None` — L7 기능은 별도 Waypoint 필요

---

## Step-06: 정상 동작 — 호출이 여전히 정상 (cp)

```bash
kubectl -n ambient-mesh exec deploy/client -- \
  curl -s -w "\nHTTP %{http_code}\n" http://api.ambient-mesh.svc.cluster.local/
```

무엇을 봐야 하나

* `Hello from API` + `HTTP 200` — 메시 적용 후에도 통신 정상. 앱은 평문 HTTP 그대로, 암호화는 ztunnel이 투명하게 처리

---

## Step-07: [한계 1 재검증] 15008 캡처를 위한 wk1 접속 (wk1)

```bash
aws ssm start-session --target <WK1_INSTANCE_ID> --region ap-northeast-2
sudo su - root
```

무엇을 봐야 하나

* `07_01`에서는 8080을 캡처했지만, 이번엔 ztunnel의 `15008`(HBONE) 포트를 캡처 — Ambient에서 노드 간 트래픽은 15008로 흐름

---

## Step-08: [한계 1 재검증] tcpdump로 15008 캡처 (wk1)

```bash
tcpdump -i any -A -s 0 'tcp port 15008' -c 20    # -c 20: 20개 후 종료
```

무엇을 봐야 하나

* 이 터미널을 띄워둔 채, 다음 Step에서 호출을 보냄

---

## Step-09: [한계 1 재검증] 동일한 민감 정보 호출 (cp)

`07_01`과 완전히 같은 호출을 보냅니다.

```bash
kubectl -n ambient-mesh exec deploy/client -- \
  curl -s http://api.ambient-mesh.svc.cluster.local/?secret=password123
```

무엇을 봐야 하나

* 호출 직후 wk1의 tcpdump에 15008 패킷이 잡힘

---

## Step-10: [한계 1 해소] 평문이 사라지고 암호화됨 (wk1)

Step-08의 tcpdump 출력을 확인합니다.

무엇을 봐야 하나

* `07_01`에서 보이던 `GET /?secret=password123` 평문이 어디에도 없음 — 페이로드가 모두 TLS 1.3 암호화 바이트
* 애플리케이션 코드 변경 0줄 — namespace 라벨 한 줄로 첫 번째 한계(평문 노출) 해소

---

## Step-11: [한계 2·3 재검증] 호출 발생 + ztunnel 메트릭 연결 (cp)

ztunnel은 Rust 경량 바이너리라 컨테이너에 `curl`이 없습니다. `port-forward`로 메트릭 포트(`15020`)를 로컬에 연결해 조회합니다.

```bash
# 메트릭이 생기도록 먼저 호출 발생
kubectl -n ambient-mesh exec deploy/client -- \
  curl -s -o /dev/null http://api.ambient-mesh.svc.cluster.local/
```

```bash
# 터미널 1 — ztunnel 15020 포트를 로컬로 연결 (연결 유지)
kubectl -n istio-system port-forward \
  $(kubectl -n istio-system get pod -l app=ztunnel -o jsonpath='{.items[0].metadata.name}') \
  15020:15020
```

무엇을 봐야 하나

* `Forwarding from 127.0.0.1:15020` 메시지 — 이 터미널은 연결 유지, 조회는 터미널 2에서

---

## Step-12: [한계 2 해소] SPIFFE 신원 자동 부착 (cp)

```bash
# 터미널 2
curl -s localhost:15020/metrics | grep istio_tcp_connections_opened
```

무엇을 봐야 하나

* `source_principal="spiffe://cluster.local/ns/ambient-mesh/sa/default"` — 호출자의 SPIFFE 신원이 자동 부착 (`destination_principal`도 함께)
* `07_01`에서는 호출자 정보가 전혀 없었음 → 두 번째 한계(신원 부재) 해소
* `connection_security_policy="mutual_tls"` — 메트릭 자체가 mTLS를 증명 (tcpdump와 교차 확인)

---

## Step-13: [한계 3 해소] 메트릭 자동 수집 (cp)

```bash
# 호출 5번 발생
for i in 1 2 3 4 5; do
  kubectl -n ambient-mesh exec deploy/client -- \
    curl -s -o /dev/null http://api.ambient-mesh.svc.cluster.local/
done
```

```bash
# 터미널 2 — 같은 조회 재실행
curl -s localhost:15020/metrics | grep istio_tcp_connections_opened
```

무엇을 봐야 하나

* `istio_tcp_connections_opened_total` 카운터가 호출한 만큼 증가 (counter 타입, 누적) → 측정 코드 0줄로 관찰 데이터가 쌓임 → 세 번째 한계(메트릭 부재) 해소
* 단, ztunnel은 L4(TCP) 메트릭만 — HTTP 요청 수·응답 코드·지연시간 같은 L7 지표는 Waypoint 필요

> Step-11 ~ 13은 헬퍼 스크립트 한 번으로도 실행할 수 있습니다.
> ```bash
> bash verify-mtls.sh
> ```

---

## Step-14: Cleanup (cp)

```bash
kubectl delete -f ambient-api.yaml -f ambient-client.yaml    # namespace 라벨도 함께 사라져 메시 등록 해제
kubectl get ns ambient-mesh
```

무엇을 봐야 하나

* Istio 자체를 제거하려면 `istioctl uninstall --purge` (다음 실습을 위해 보통 유지)

---

