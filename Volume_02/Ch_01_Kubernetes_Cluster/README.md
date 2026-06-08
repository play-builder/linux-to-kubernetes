
# Ch_01_Kubernetes_Cluster: 클러스터 구조와 동작 추적

## Step-01: Introduction

### What You'll Learn

* 클러스터 해부: `control plane`(apiserver·etcd·controller·scheduler) ↔ 노드(kubelet·kube-proxy·containerd)
* 단일 통신 원칙 추적: 모든 컴포넌트 → `kube-apiserver` 경유 · `etcd` 접근 자격은 apiserver만
* 요청 파이프라인 추적: `인증(401) → 인가/RBAC(403) → Admission → 검증 → etcd`
* 조정 루프·배치 검증: 자가 복구 · `kube-scheduler` nodeName 할당 · `Pending` 사유 분석
* 노드 동작 추적: `kubelet` Lease · `Static Pod`/mirror pod · Pod 생명주기 · `kube-proxy` KUBE 체인 · `CoreDNS`
* 가용성 격리 검증: `kube-apiserver` 정지 시에도 data plane(기실행 파드) 생존

---

## Step-02: Prerequisites

### 사전 코드 — 필요함

이 Lab은 하나의 클러스터에서 `control plane` → 노드 → 격리 검증까지 차례로 추적합니다. 리소스 생성은 모두 yaml 파일로 분리돼 있어 `kubectl apply -f`로 불러옵니다.

### 환경 요구사항

* ✅ Kubeadm 기반 K8s 클러스터 (`v1.35.5`)
  참고: [Kubeadm Project Setup](https://github.com/play-builder/linux-to-kubernetes/tree/main/Ch_00_K8s_Kubeadm_Project_Setup)
* ✅ 노드 구성
  * `cp`
  * `wk1` 
  * `wk2`
* ✅ 실습 매니페스트 
  * `rbac-sa.yaml` · `rbac-role-binding.yaml` 
  * `recon-test.yaml` · `sched-test.yaml` · `pending-test.yaml` 
  * `flow-test.yaml` 
  * `static-web.yaml` 
  * `lifecycle-demo.yaml` 
  * `dns-test.yaml`
  * `survive-test.yaml` 

---

# 🔬 Hands-on Lab — 클러스터 구조와 동작 추적

`control plane` 4종과 노드 컴포넌트가 `kube-apiserver`를 축으로 어떻게 맞물리는지, 그리고 control/data plane이 어떻게 분리되는지를 단계별로 추적합니다.

---

## Step-01: [접속] cp 노드 진입 (cp)

```bash
aws ssm start-session \
--target <CP_INSTANCE_ID> \
--region ap-northeast-2
```

```bash
sudo su - ubuntu
```

```bash
cd linux-to-kubernetes/Volume_02/Ch_01_Kubernetes_Cluster
```

---

## Step-02: [구조 조회] 클러스터 컴포넌트 확인 (cp)

```bash
kubectl get nodes -o wide
```

```bash
kubectl get pods -n kube-system -o wide \
| grep -E "apiserver|etcd|scheduler|controller"
```

```bash
ls /etc/kubernetes/manifests/
```

```bash
kubectl get ds,deploy -n kube-system
```

```bash
systemctl is-active kubelet
```

**확인 포인트**

* `ROLES` 열로 control-plane / 워커 구분
* control plane 4종이 파드(Static Pod)로 보임 — `EKS`에선 안 보임
* `manifests/`의 yaml 4개 = Static Pod 정의 (etcd 미등록)
* 애드온(`calico-node`·`kube-proxy`·`coredns`)은 일반 리소스
* `kubelet`은 파드가 아닌 `systemd` 서비스

---

## Step-03: [단일 접근] etcd 접근 자격 검증 (cp root)

```bash
sudo su - root
```

```bash
ss -tlnp | grep 2379
```

```bash
ls /etc/kubernetes/pki/ | grep etcd
```

```bash
grep etcd /etc/kubernetes/manifests/kube-apiserver.yaml
```

```bash
grep -i etcd /etc/kubernetes/manifests/kube-scheduler.yaml
```

```bash
grep kubeconfig /etc/kubernetes/manifests/kube-scheduler.yaml
```

**확인 포인트**

* `etcd` 리스닝 = 2379(클라이언트) / 2380(피어)
* `apiserver-etcd-client.crt/key` = apiserver 전용 etcd 클라이언트 인증서
* `kube-apiserver`만 `--etcd-*` 플래그 보유
* `kube-scheduler`엔 etcd 설정 없음 → `kubeconfig`로 apiserver만 바라봄

---

## Step-04: [요청 파이프라인] RBAC — 401 vs 403 (cp)

```bash
exit
```

```bash
sudo ss -tlnp | grep 6443
```

```bash
kubectl config view --minify | grep server
```

### 권한 없는 SA 생성 → 403 재현

```bash
kubectl apply -f rbac-sa.yaml
```

```bash
kubectl get pods \
--as=system:serviceaccount:default:limited-sa
```

### 최소 권한 부여 → 허용

```bash
kubectl apply -f rbac-role-binding.yaml
```

```bash
kubectl auth can-i list pods \
--as=system:serviceaccount:default:limited-sa
```

**확인 포인트**

* 권한 없는 SA 요청 → `Forbidden` = 403 (인증은 통과, 인가에서 차단)
* 401(자격) vs 403(권한)의 차이
* `Role`+`RoleBinding` 부여 후 같은 질의가 `yes`로 바뀜

### 정리

```bash
kubectl delete -f rbac-role-binding.yaml
kubectl delete -f rbac-sa.yaml
```

---

## Step-05: [상태 저장] etcd 데이터 · 백업 (cp root)

```bash
sudo su - root
```

```bash
export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key
```

```bash
etcdctl get /registry/pods --prefix --keys-only \
| head -10
```

```bash
etcdctl snapshot save /tmp/etcd-backup.db
```

```bash
etcdctl snapshot status /tmp/etcd-backup.db \
--write-out=table
```

**확인 포인트**

* 모든 객체가 `/registry/` 아래 key로 저장됨
* `apiserver-etcd-client`와 동일 자격으로 etcd 접근
* `snapshot save` = 운영 필수 백업, `status`로 무결성 확인

---

## Step-06: [조정·배치] 자가 복구 · 노드 배치 · Pending (cp)

```bash
exit
```

### 조정 루프 — 자가 복구

```bash
kubectl apply -f recon-test.yaml
```

```bash
kubectl delete pod \
$(kubectl get pod -l app=recon-test -o name | head -1)
```

```bash
kubectl get pods -l app=recon-test
```

### 배치 결정 — nodeName 할당

```bash
kubectl apply -f sched-test.yaml
```

```bash
kubectl get pod sched-test -o wide
```

### Pending 재현

```bash
kubectl apply -f pending-test.yaml
```

```bash
kubectl get pod pending-test
```

```bash
kubectl describe pod pending-test \
| grep -A3 Events
```

**확인 포인트**

* 삭제한 자리에 새 파드 생성 = `kube-controller-manager` 자가 복구
* `sched-test`의 `NODE` 열 = `kube-scheduler`가 고른 노드
* `Pending` 사유 = `Events`의 `FailedScheduling` 한 줄

### 정리

```bash
kubectl delete -f recon-test.yaml
kubectl delete -f sched-test.yaml
kubectl delete -f pending-test.yaml
```

---

## Step-07: [전체 경로] 생성 흐름 이벤트 추적 (cp)

```bash
kubectl get events -A -w &
```

```bash
kubectl apply -f flow-test.yaml
```

```bash
kubectl get deploy,rs,pod -l app=flow-test
```

**확인 포인트**

* 이벤트 발신자 순서: `deployment-controller` → `replicaset-controller` → `default-scheduler` → `kubelet`
* 계층 생성: `Deployment` → `ReplicaSet` → `Pod`

### 정리

```bash
kubectl delete -f flow-test.yaml
kill %1
```

---

## Step-08: [노드 에이전트] kubelet 상태 · Lease (wk1 root & cp)

### [wk1 root] 접속

```bash
aws ssm start-session \
--target <WK1_INSTANCE_ID> \
--region ap-northeast-2
```

```bash
sudo su - root
```

```bash
systemctl is-active kubelet
```

```bash
grep server /etc/kubernetes/kubelet.conf
```

### [cp]

```bash
kubectl get lease -n kube-node-lease
```

**확인 포인트**

* `kubelet` = `systemd` 서비스, 연결 대상은 cp의 apiserver(6443)뿐
* `kube-node-lease`의 `Lease` = `kubelet` 생존 신호(~10초) → `NotReady` 진단 1순위

---

## Step-09: [파일 파드] Static Pod · mirror pod (wk1 root & cp)

### [wk1 root] 감시 폴더에 배치

```bash
sudo cp static-web.yaml \
/etc/kubernetes/manifests/static-web.yaml
```

### [cp] mirror pod 확인

```bash
kubectl get pod static-web-wk1
```

```bash
kubectl delete pod static-web-wk1
```

```bash
kubectl get pod static-web-wk1
```

### [wk1 root] 진짜 제거 = 파일 삭제

```bash
sudo rm /etc/kubernetes/manifests/static-web.yaml
```

**확인 포인트**

* 명령 없이 `kubelet`이 파일만 보고 파드 생성 (scheduler 안 거침)
* `static-web-wk1`(이름 끝 노드명) = mirror pod → `kubectl delete` 해도 되살아남
* 파일을 지워야 비로소 내려감

---

## Step-10: [생명주기] 기동 순서 · 우아한 종료 (cp)

```bash
kubectl apply -f lifecycle-demo.yaml
```

```bash
kubectl get pod lifecycle-demo -w
```

```bash
time kubectl delete pod lifecycle-demo
```

**확인 포인트**

* `Init:0/1 → PodInitializing → Running` = init이 기동 순서 보장
* 삭제가 즉시 안 끝남 = `preStop` + `SIGTERM` 정리(grace 내 종료)

---

## Step-11: [Service 규칙] kube-proxy 체인 (wk1 root)

```bash
sudo iptables -t nat -L KUBE-SERVICES -n \
| head -5
```

**확인 포인트**

* 각 `ClusterIP` → `KUBE-SVC` 체인으로 분기하는 규칙 존재
* `kube-proxy`는 규칙만 설치 · 실제 변환은 커널 `netfilter`

---

## Step-12: [이름 해석] CoreDNS (cp)

```bash
kubectl apply -f dns-test.yaml
```

```bash
kubectl exec dns-test -- cat /etc/resolv.conf
```

```bash
kubectl exec dns-test -- nslookup kubernetes.default
```

**확인 포인트**

* `nameserver 10.96.0.10` · `search ...` · `options ndots:5`
* 짧은 이름 → `search` 확장 → `kubernetes.default.svc.cluster.local`(`10.96.0.1`)

### 정리

```bash
kubectl delete -f dns-test.yaml
```

---

## Step-13: [격리 검증] apiserver 정지 → 워크로드 생존 (cp & wk1 root)

> ⚠️ 학습 전용. Static Pod manifest를 잠깐 옮겨 control plane을 멈추는 실험으로, 프로덕션 금지.

### [cp] 테스트 파드 생성

```bash
kubectl apply -f survive-test.yaml
```

```bash
kubectl wait \
--for=condition=Ready \
pod/survive-test \
--timeout=60s
```

```bash
kubectl get pod survive-test -o wide
```

### [cp] apiserver 정지

```bash
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/
```

```bash
kubectl get pods
```

### [wk1 root] 파드 생존 확인

```bash
sudo crictl ps | grep survive
```

### [cp] 복구 = manifest 원위치

```bash
sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/
```

```bash
kubectl get pod survive-test
```

**확인 포인트**

* apiserver 정지 ~30초 후 `kubectl` 연결 거부 = 변경 통로 닫힘
* 그 동안에도 `survive-test`는 `Running` = control/data plane 독립
* manifest 원위치 ~30초 후 apiserver 자동 복구

---

## Step-14: Cleanup (cp)

```bash
kubectl delete -f survive-test.yaml --ignore-not-found
```


