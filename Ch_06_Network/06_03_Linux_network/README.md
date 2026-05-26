# 03_linux_network: 리눅스 네트워크 커널 내부

## Step-01: Introduction

### What You'll Learn

* 패킷 처리 경로 추적: `PREROUTING → 라우팅 결정 → INPUT/FORWARD → POSTROUTING`
* ClusterIP 변환 과정 추적: `KUBE-SERVICES → KUBE-SVC → KUBE-SEP → DNAT`
* 커널 내부 상태 추적: `conntrack` 장부와 `FIB Trie` 기반 라우팅
* Calico L3 네트워크 동작 이해: `169.254.1.1`, `proxy_arp`, `veth(cali*)`
* 네트워크 장애 분석: `rp_filter`, 비대칭 경로, UDP 타임아웃

---

## Step-02: Prerequisites

### 사전 코드 — 필요함

이번 Part는 하나의 Hands-on Lab 안에서 여러 네트워크 경로를 추적합니다.

### 환경 요구사항

* ✅ Kubeadm 기반 K8s 클러스터 환경 구축

  참고: [Kubeadm Project Setup](https://github.com/play-builder/linux-to-kubernetes/tree/main/Ch_00_K8s_Kubeadm_Project_Setup)

* ✅ 노드 구성
  * `cp` (Control Plane)
  * `wk1`
  * `wk2`

---

# 🔬 Hands-on Lab — 리눅스 네트워크 커널 내부 추적

이번 챕터에서는 Pod에서 출발한 패킷이 호스트 커널을 통과하며, 라우팅과 ARP를 거쳐 실제 목적지까지 도달하는 과정을 단계별로 추적합니다.

> ⚠️ 이 Lab은 **Control Plane(cp)** 와 **Worker(wk1 / wk2)** 를 오가며 진행합니다.
>
> 각 Step마다 어느 노드에서 실행할지 명시되어 있습니다.

---

## Step-01: [실습 준비] 트래픽 발생용 파드 배포 (cp)

패킷의 여정을 시작할 출발지 파드를 생성합니다.

```bash
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
```

```bash
sudo su - ubuntu
```

```bash
kubectl run probe \
--image=playbuilder/netshoot:latest \
--overrides='{"spec":{"nodeName":"wk1"}}' \
--command -- sleep 600
```

```bash
kubectl wait \
--for=condition=Ready \
pod/probe \
--timeout=60s
```

---

## Step-02: [출발] 파드의 가상 게이트웨이 확인 (cp)

패킷의 첫 번째 목적지를 확인합니다.

```bash
kubectl exec probe -- ip route
```

**확인 포인트**

* 기본 게이트웨이가 `169.254.1.1`인지 확인
* Calico가 파드 내부에 가상 게이트웨이를 주입했는지 확인

---

## Step-03: [연결 고리] veth 매핑, hostNetwork, proxy_arp 확인 (cp & wk1)

### 전체 파드 배치 확인

```bash
kubectl get pods -A -o wide
```

**확인 포인트**

* 어떤 파드가 `wk1` 위에 떠 있는지 확인
* 파드 IP 대역 확인

---

### wk1 노드 접속

```bash
aws ssm start-session \
--target <WK1_INSTANCE_ID> \
--region ap-northeast-2
```

```bash
sudo su - root
```

---

### cali 인터페이스 확인

```bash
ip link show | grep cali
```

**확인 포인트**

* Calico 인터페이스 개수 확인
* 파드 수와 인터페이스 개수 관계 확인

---

### hostNetwork 확인

```bash
kubectl get pod <POD_NAME> \
-n <NAMESPACE> \
-o yaml \
| grep hostNetwork
```

```bash
kubectl get pod probe \
-o yaml \
| grep hostNetwork
```

```bash
kubectl get pod calico-node-<SUFFIX> \
-n calico-system \
-o yaml \
| grep hostNetwork
```

```bash
kubectl get pod kube-proxy-<SUFFIX> \
-n kube-system \
-o yaml \
| grep hostNetwork
```

**확인 포인트**

* 일반 파드와 hostNetwork 파드 차이 확인

---

### proxy_arp 확인

```bash
cat /proc/sys/net/ipv4/conf/<INTERFACE>/proxy_arp
```

```bash
cat /proc/sys/net/ipv4/conf/cali<INTERFACE_SUFFIX>/proxy_arp
```

**확인 포인트**

* proxy_arp 값 확인
* 호스트가 ARP 대리 응답하는 구조 확인

---

## Step-04: [호스트 진입] 커널 Netfilter 훅 통과 (wk1)

패킷이 호스트 커널로 진입하면서 통과하는 체인을 확인합니다.

```bash
iptables -t nat \
-L \
-n \
--line-numbers \
| head -25 \
| column -t
```

```bash
iptables -t nat \
-L PREROUTING \
-n \
--line-numbers \
| column -t
```

```bash
iptables -t filter \
-L FORWARD \
-n \
--line-numbers \
| column -t
```

**확인 포인트**

* `PREROUTING` 체인 확인
* `KUBE-SERVICES` 연결 여부 확인

---

## Step-05: [목적지 변환] KUBE-SERVICES 분기 및 DNAT 대상 검증 (wk1 & cp)

### KUBE-SERVICES 확인

```bash
iptables -t nat \
-L KUBE-SERVICES \
-n \
--line-numbers \
| head -15 \
| column -t
```

---

### DNS Service 규칙 찾기

```bash
iptables -t nat \
-L KUBE-SERVICES \
-n \
| grep '10.96.0.10' \
| grep 'udp dpt:53'
```

---

### SVC 체인 추출

```bash
SVC=$(iptables -t nat -L KUBE-SERVICES -n \
| grep '10.96.0.10' \
| grep 'udp dpt:53' \
| awk '{print $1}')
```

```bash
echo "SVC chain: $SVC"
```

```bash
iptables -t nat \
-L $SVC \
-n \
--line-numbers \
| column -t
```

**확인 포인트**

* DNS Service가 어떤 KUBE-SVC 체인으로 연결되는지 확인

---

### SEP 체인 추출

```bash
SEP=$(iptables -t nat -L $SVC -n \
| grep 'KUBE-SEP' \
| head -1 \
| awk '{print $1}')
```

```bash
echo "SEP chain: $SEP"
```

```bash
iptables -t nat \
-L $SEP \
-n \
--line-numbers \
| column -t
```

**확인 포인트**

* DNAT 대상 Pod IP 확인

---

### 실제 CoreDNS Pod 확인

```bash
kubectl get pods -A -o wide \
| grep dns
```

**확인 포인트**

* DNAT 대상 IP와 실제 CoreDNS IP 비교

---

## Step-06: [상태 기록] Conntrack 장부와 타임아웃 (wk1)

```bash
which conntrack \
|| apt-get install -y conntrack
```

```bash
conntrack -L \
2>/dev/null \
| head -5
```

```bash
conntrack -L -p udp \
2>/dev/null \
| grep 10.96.0.10
```

**확인 포인트**

* NAT 이전/이후 흐름 기록 확인

---

### UDP 타임아웃 확인

```bash
sysctl net.netfilter.nf_conntrack_udp_timeout
```

```bash
sysctl net.netfilter.nf_conntrack_udp_timeout_stream
```

**확인 포인트**

* UDP timeout 확인
* stream timeout 확인

---

## Step-07: [길 찾기] 커널 라우팅 테이블 및 FIB Trie (wk1)

```bash
ip route
```

```bash
ip route get <POD_IP>
```

```bash
ip route get 10.244.242.67
```

**확인 포인트**

* 어느 인터페이스로 나가는지 확인
* next hop 확인

---

### FIB Trie 확인

```bash
cat /proc/net/fib_triestat
```

**확인 포인트**

* Average depth 확인
* Prefix 개수 확인
* 커널 라우팅 탐색 구조 확인

---

## Step-08: [물리 송출 및 궤적 증명] Traceroute (cp & wk1)

### 커널 관점 경로 확인

```bash
ip route get <coreDNS_POD_IP>
```

```bash
ip route get 10.244.242.66
```

```bash
ip neigh show
```

**확인 포인트**

* next hop 확인
* MAC 주소 확인

---

### 실제 패킷 궤적 확인
```bash
kubectl exec <POD_NAME> -- traceroute -n <coreDNS_POD_IP>
```

```bash
kubectl exec probe \
-- traceroute -n 10.244.242.66
```

**확인 포인트**

* 호스트 진입 확인
* 노드 간 이동 확인
* 최종 목적지 도착 확인

---

## Step-09: ARP — IP에서 MAC으로

```bash
kubectl exec probe \
-- ip neigh show
```

**확인 포인트**

* `169.254.1.1` MAC 확인
* ARP cache 상태 확인
* `REACHABLE`
* `STALE`

---

## Step-10: 구조 검증 — L3 Routing 구조 확인 (cp)

```bash
kubectl exec probe -- ip route
```

```bash
kubectl exec probe -- ip neigh show
```

**확인 포인트**

* Overlay 사용 여부 확인
* Direct Routing 구조 확인

---

## Step-11: 보안 검문 — rp_filter 점검 (wk1)

```bash
sysctl \
net.ipv4.conf.cali<INTERFACE_SUFFIX>.rp_filter
```

```bash
nstat -az \
| grep IPReversePathFilter
```

**확인 포인트**

* rp_filter 값 확인
* 드롭 통계 확인

---

## Step-12: Cleanup (cp)

```bash
kubectl delete pod probe \
--ignore-not-found
```

---


