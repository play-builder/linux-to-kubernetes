# 02_network_basics: 네트워크 기초

---

## Step-01: Introduction

### 💡 What You'll Learn

* **CoreDNS 장애 분석 기초:** ClusterIP, UDP, 53번 포트 결합 구조 이해
* **TCP/IP 4계층 및 캡슐화:** Data → Segment → Packet → Frame 흐름과 헤더 구조
* **CIDR 및 서브넷:** `/8`, `/16`, `/24` 구분에 따른 호스트 수용량 계산
* **쿠버네티스 3대 IP:** Node IP, Service IP, Pod IP 차이 및 DNAT 원리
* **서비스 타입 3종 구조:** `LoadBalancer ⊃ NodePort ⊃ ClusterIP` 포함 관계
* **4대 포트 사슬:** `nodePort` → `port` → `targetPort` → `containerPort` 흐름 추적
* **TCP vs UDP 특징:** TCP 핸드셰이크와 UDP 비연결성이 `conntrack` 장애에 미치는 영향
* **L2 vs L3 경로 판별:** 동일 노드와 타 노드 통신 시 **도착지 MAC 주소** 변화 분석

---

## Step-02: Prerequisites

본 과제는 총 18개의 Hands-on Lab 단계로 구성되어 있으며, 실습 진행을 위해 아래의 파일들이 작업 디렉토리(`02_network_basics/`) 내에 반드시 준비되어 있어야 합니다.

### 📄 실습 파일 목록

| 파일명 | 용도 |
| --- | --- |
| **01_clusterip-web.yaml** | **Hands-on Lab 13** — 가상 내부 격리망 서비스 테스트 및 포트 사슬 구조(`port` ↔ `targetPort` ↔ `containerPort`) 검증용 매니페스트 |
| **02_nodeport-web.yaml** | **Hands-on Lab 14** — 모든 노드의 호스트 포트(`30000~32767`)를 열어 외부 인바운드 트래픽 진입 경로를 테스트하기 위한 매니페스트 |
| **03_metallb-config.yaml** | **Hands-on Lab 16** — 로컬 온프레미스 인프라에 외부 가상 IP를 할당하기 위한 `IPAddressPool` 및 `L2Advertisement` 설정 파일 |
| **04_loadbalancer-web.yaml** | **Hands-on Lab 17** — MetalLB로부터 외부 VIP(`EXTERNAL-IP`)를 동적 프로비저닝 받아 단일 진입점 통신을 실측하기 위한 매니페스트 |

> 💡 **참고:** **Hands-on Lab 1~12** 단계는 `kubectl` 기본 명령과 리눅스 커널 분석 도구(`iptables`, `tcpdump`, `nslookup`, `conntrack`)를 활용한 호스트 네트워크 직접 검증으로 진행되므로 별도의 YAML 파일이 요구되지 않습니다.


---

# Hands-on Lab

---

## Step-01: Control Plane 접속 (cp)

```bash
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - ubuntu

```

---

## Step-02: Node IP 확인 (cp)

```bash
kubectl get nodes -o wide

```

---

## Step-03: Pod IP와 변동성 확인 (cp)

```bash
## kube-system 네임스페이스 내 파드별 가상 IP 및 배치 노드 확인
kubectl get pods -n kube-system -o wide

kubectl run iptest --image=nginx
kubectl get pod iptest -o wide

kubectl delete pod iptest
kubectl run iptest --image=nginx
## 파드 재 생성 시 가상 IP 동적 변경(변동성) 확인
kubectl get pod iptest -o wide

```

---

## Step-04: ClusterIP는 가상 주소임을 확인 (cp)

```bash
kubectl get svc -n kube-system kube-dns
kubectl get pod -n kube-system
kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}{"\n"}'

## ClusterIP의 호스트 물리 인터페이스 할당 여부(가상 주소) 검증
ip addr | grep 10.96 || echo "어느 네트워크 인터페이스에도 10.96 주소 없음"

```

---

## Step-05: ClusterIP가 iptables 규칙임을 확인 (wk1)

```bash
aws ssm start-session --target <WK1_INSTANCE_ID> --region ap-northeast-2
sudo su - root

## 서비스 IP(ClusterIP) 가로채기용 iptables 기본 서비스 체인 검색
iptables -t nat -L KUBE-SERVICES -n | grep 10.96.0.10

SVC_CHAIN=$(iptables -t nat -L KUBE-SERVICES -n | grep 10.96.0.10 | grep -oE 'KUBE-SVC-[A-Z0-9]+' | head -1)
echo $SVC_CHAIN
## 서비스 분기 체인 내 실제 엔드포인트 파드 간 확률형 분산(로드밸런싱) 규칙 확인
iptables -t nat -L $SVC_CHAIN -n

```

---

## Step-06: tcpdump 준비 (cp)

`cp`로 돌아옵니다.

```bash
which tcpdump || sudo apt-get install -y tcpdump

```

---

## Step-07: 한 패킷에서 4계층 확인 (cp)

```bash
## 패킷 덤프를 통한 L2(MAC)·L3(IP)·L4(Port) 계층 구조 식별
sudo tcpdump -i ens5 -c 3 -nn -e

```

---

## Step-08: TCP 핸드셰이크 실측 (cp)

```bash
## 통신 전 TCP 3-Way Handshake(SYN, SYN-ACK, ACK) 신호 플래그 변화 분석
sudo tcpdump -i ens5 -c 6 -nn 'tcp port 443 and host 1.1.1.1' & sleep 1; curl -s https://1.1.1.1 > /dev/null; wait

```

---

## Step-09: UDP는 핸드셰이크가 없음을 확인 (cp)

```bash
## 핸드셰이크 과정 없이 단일 요청/응답 패킷만 즉시 오가는 UDP 특성 실측
sudo tcpdump -i ens5 -c 2 -nn 'udp port 53' &
nslookup google.com
wait

```

---

## Step-10: conntrack에 남는 UDP 흔적 확인 (cp → wk1)

```bash
kubectl run dnsq --image=busybox:1.36 --restart=Never --overrides='{"spec":{"nodeName":"wk1"}}' -- sh -c "nslookup kubernetes.default; sleep 30"

aws ssm start-session --target <WK1_INSTANCE_ID> --region ap-northeast-2
sudo su - root
which conntrack || apt-get install -y conntrack
## conntrack 테이블 내 UDP 세션 만료 타이머 상태 조회
conntrack -L -p udp --dport 53 2>/dev/null | head -5

kubectl delete pod dnsq --ignore-not-found

```

---

## Step-11: 같은 노드 통신과 ARP 캐시 확인 (cp)

```bash
kubectl run l2src --image=playbuilder/netshoot:latest --overrides='{"spec":{"nodeName":"wk1"}}' --command -- sleep 3600
kubectl run l2dst --image=nginx --overrides='{"spec":{"nodeName":"wk1"}}'
kubectl get pod l2src l2dst -o wide

DST_IP=$(kubectl get pod l2dst -o jsonpath='{.status.podIP}')
kubectl exec l2src -- ping -c 2 $DST_IP
## 동일 노드 파드 간 통신 시 이웃 캐시(ARP Table) 내 인접 MAC 주소 기록 확인
kubectl exec l2src -- ip neigh show

```

---

## Step-12: 다른 노드 통신 확인 (cp)

```bash
kubectl run l3dst --image=nginx --overrides='{"spec":{"nodeName":"wk2"}}'
kubectl get pod l2src l3dst -o wide

DST_IP=$(kubectl get pod l3dst -o jsonpath='{.status.podIP}')
kubectl exec l2src -- ping -c 2 $DST_IP
## 타 노드 파드 통신 시 외부 게이트웨이를 타는 L3 라우팅 경로 추적
kubectl exec l2src -- ip route get $DST_IP

```

---

## Step-13: ClusterIP 통신 검증 — Deployment 배포 후 내부 접속 (cp)

```bash
cat 01_clusterip-web.yaml
kubectl apply -f 01_clusterip-web.yaml
kubectl get deploy,svc,pod -l app=clusterip-web -o wide

## 서비스 진입 포트(8080)와 컨테이너 타겟 포트(80) 매핑 구조 확인
kubectl get pod -l app=clusterip-web -o jsonpath='{.items[0].spec.containers[0].ports}{"\n"}'
kubectl get svc clusterip-web -o jsonpath='{.spec.ports}{"\n"}'

kubectl run test-client --image=playbuilder/netshoot:latest --rm -it -- bash

## 가상 도메인 이름을 활용한 내부 ClusterIP 포워딩 연동 테스트
curl -s http://clusterip-web:8080 | head -3
curl -s http://clusterip-web:8080 -o /dev/null -w "%{http_code}\n"
curl -s http://clusterip-web:8080 -o /dev/null -w "%{http_code}\n"
curl -s http://clusterip-web:8080 -o /dev/null -w "%{http_code}\n"
exit

```

---

## Step-14: nodePort 실측 (cp)

```bash
cat 02_nodeport-web.yaml
kubectl apply -f 02_nodeport-web.yaml

## 외부 접근용 노드포트 할당 대역(30000~32767) 활성화 상태 확인
kubectl get deploy,svc -l app=nodeport-web

## 노드 사설 IP와 NodePort 조합을 활용한 호스트 인바운드 외부 통신 실측
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[1].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get svc nodeport-web -o jsonpath='{.spec.ports[0].nodePort}')
curl -s http://$NODE_IP:$NODE_PORT | head -3

```

---

## Step-15: MetalLB 설치 — LoadBalancer 타입 활성화 (cp)

```bash
## 베어메탈/로컬 환경용 가상 로드밸런서(MetalLB) 코어 모듈 배포 및 가동 대기
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s

```

---

## Step-16: IP 주소 풀 설정 (cp)

```bash
cat 03_metallb-config.yaml

## 가상 로드밸런서용 IP 주소 풀 대역 할당 및 L2 광고 설정 적용
kubectl apply -f 03_metallb-config.yaml
kubectl get ipaddresspool -n metallb-system

```

---

## Step-17: LoadBalancer Service 배포 — External IP 할당 확인 (cp)

```bash
cat 04_loadbalancer-web.yaml
kubectl apply -f 04_loadbalancer-web.yaml

## 주소 풀로부터 프로비저닝된 가상 외부 주소(EXTERNAL-IP) 매핑 확인
kubectl get deploy,svc,pod -l app=loadbalancer-web -o wide

LB_IP=$(kubectl get svc loadbalancer-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "External IP: $LB_IP"
curl -s http://$LB_IP | head -3

```

---

## Step-18: Cleanup (cp)

```bash
kubectl delete pod iptest l2src l2dst l3dst dnsq probe test-client --ignore-not-found
kubectl delete -f 01_clusterip-web.yaml --ignore-not-found
kubectl delete -f 02_nodeport-web.yaml --ignore-not-found
kubectl delete -f 04_loadbalancer-web.yaml --ignore-not-found
kubectl get pods

## MetalLB 자원 회수 및 인프라 구성 초기화 복구
kubectl delete -f 03_metallb-config.yaml --ignore-not-found
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml --ignore-not-found

```
