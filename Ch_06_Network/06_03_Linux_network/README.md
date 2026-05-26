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
  
* ✅ 노드 구성: `cp` (Control Plane), `wk1`, `wk2`


---

# 🔬 Hands-on Lab — 리눅스 네트워크 커널 내부 추적

이번 챕터에서는 Pod에서 출발한 패킷이 호스트 커널을 통과하며, 라우팅과 ARP를 거쳐 실제 목적지까지 도달하는 과정을 단계별로 추적합니다.

> ⚠️ 이 Lab은 **Control Plane(cp)** 와 **Worker(wk1 / wk2)** 를 오가며 진행합니다.
> 각 Step마다 어느 노드에서 실행할지 명시되어 있습니다.

---

## Step-01: 트래픽 발생용 파드 배포 (cp)

패킷의 여정을 시작할 출발지 파드를 생성합니다.

```bash
kubectl run probe --image=playbuilder/netshoot:latest \
  --overrides='{"spec":{"nodeName":"wk1"}}' \
  --command -- sleep 600
```

```bash
kubectl wait --for=condition=Ready pod/probe --timeout=60s
```

---

## Step-02: 출발 — 파드의 가상 게이트웨이 확인 (cp)

파드 내부 라우팅 테이블을 통해 첫 번째 목적지를 확인합니다.

```bash
kubectl exec probe -- ip route
```

**확인 포인트**

* 기본 게이트웨이가 `169.254.1.1`로 설정되어 있는지 확인합니다.

---

## Step-03: 연결 고리 — veth, hostNetwork, proxy_arp (wk1)

파드와 호스트를 연결하는 구조를 확인합니다.

### 1. cali 인터페이스 확인

```bash
ip link show | grep cali
```

### 2. hostNetwork 확인

```bash
# 일반 파드
kubectl get pod probe -o yaml | grep hostNetwork

# 시스템 파드
kubectl get pod -n calico-system \
-l k8s-app=calico-node \
-o yaml | grep hostNetwork
```

### 3. proxy_arp 확인

```bash
cat /proc/sys/net/ipv4/conf/cali<INTERFACE_SUFFIX>/proxy_arp
```

**확인 포인트**

* Calico 환경에서 파드 인터페이스가 L3 전달을 어떻게 보조하는지 확인합니다.

---

## Step-04: 호스트 진입 — 커널 Netfilter 훅 (wk1)

패킷이 호스트 커널로 진입할 때 통과하는 체인을 확인합니다.

```bash
iptables -t nat -L -n --line-numbers | head -25 | column -t
```

```bash
iptables -t nat -L PREROUTING -n --line-numbers | column -t
```

```bash
iptables -t filter -L FORWARD -n --line-numbers | column -t
```

**확인 포인트**

* `PREROUTING` 체인에서 `KUBE-SERVICES` 연결 여부를 확인합니다.

---

## Step-05: 목적지 변환 — DNAT 체인 추적 (wk1)

ClusterIP가 실제 Pod IP로 변환되는 과정을 추적합니다.

### 1. ClusterIP 규칙 찾기

```bash
iptables -t nat -L KUBE-SERVICES -n | grep <CLUSTER_IP>
```

### 2. KUBE-SVC 체인 확인

```bash
iptables -t nat \
-L KUBE-SVC-<HASH> \
-n \
--line-numbers
```

### 3. Endpoint 확인

```bash
iptables -t nat \
-L KUBE-SEP-<HASH> \
-n \
--line-numbers
```

```bash
kubectl get pods -A -o wide \
| grep <DNS_POD_IP>
```

**확인 포인트**

* 서비스 IP가 실제 엔드포인트로 어떻게 변환되는지 확인합니다.

---

## Step-06: 상태 기록 — conntrack 장부 (wk1)

NAT 변환 상태가 커널 내부에 어떻게 저장되는지 확인합니다.

```bash
which conntrack \
|| apt-get install -y conntrack
```

```bash
conntrack -L -p udp \
2>/dev/null \
| grep <CLUSTER_IP>
```

**확인 포인트**

* NAT 이전/이후 주소 변환 정보가 기록되는지 확인합니다.

---

## Step-07: 길 찾기 — 라우팅 테이블 및 FIB Trie (wk1)

패킷이 어느 인터페이스로 나갈지 확인합니다.

```bash
ip route
```

```bash
ip route get <POD_IP>
```

```bash
cat /proc/net/fib_triestat
```

**확인 포인트**

* 라우팅 결과와 FIB Trie 구조를 함께 확인합니다.

---

## Step-08: 물리 송출 및 경로 추적 — Traceroute (cp)

실제 패킷이 거치는 홉을 확인합니다.

```bash
kubectl exec probe \
-- traceroute -n <POD_IP>
```

**주의**

방화벽 정책에 따라 `* * *` 로 보일 수 있습니다.

필요 시 먼저 통신 여부를 확인합니다.

```bash
kubectl exec probe \
-- ping <POD_IP>
```

---

## Step-09: ARP — IP에서 MAC으로 (wk1)

다음 홉 MAC 주소 확인 과정을 추적합니다.

```bash
ip neigh show
```

**확인 포인트**

* `169.254.1.1`
* 다른 노드 IP
* 로컬 Pod IP

각각 어떤 MAC 주소로 연결되는지 확인합니다.

---

## Step-10: Calico Direct Routing 구조 검증 (cp / wk1)

Calico L3 라우팅 구조를 확인합니다.

```bash
kubectl exec probe -- ip route
```

```bash
kubectl exec probe -- ip neigh show
```

**확인 포인트**

* Overlay 없이 직접 라우팅되는 구조를 확인합니다.

---

## Step-11: rp_filter 점검 (wk1)

비대칭 경로에서 발생할 수 있는 패킷 드롭 여부를 확인합니다.

```bash
sysctl \
net.ipv4.conf.cali<INTERFACE_SUFFIX>.rp_filter
```

```bash
nstat -az \
| grep IPReversePathFilter
```

**참고**

* `1` = Strict Mode
* `2` = Loose Mode

Calico 환경에서는 일반적으로 Loose Mode를 사용합니다.

---

## Step-12: Cleanup (cp)

실습 리소스를 정리합니다.

```bash
kubectl delete pod probe \
--ignore-not-found
```

---
