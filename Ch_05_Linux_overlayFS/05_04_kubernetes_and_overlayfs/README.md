# 05_04: Kubernetes and OverlayFS

## Step-01: Introduction

- 메커니즘이 **실제 쿠버네티스 운영**에 어떻게 적용되는지 다룹니다. 
- 실제 Pod의 OverlayFS mount를 추적하고, 실제 K8s Pod에서 CoW가 일어나는 것을 증명하고, `Evicted` 상태(OOMKilled가 아닌)를 재현하고, `emptyDir + sizeLimit`으로 OverlayFS를 우회합니다.

**이번 Part가 답하는 질문:**

1. **"`kubectl run`을 실행하면 호스트의 OverlayFS에서 정확히 무엇이 일어나나요?"**
2. **"내 Pod가 OOMKilled가 아니라 `Reason: Evicted`로 종료되는 이유는?"**
3. **"I/O 집약적 워크로드에서 CoW 오버헤드를 피하는 방법은?"**

### What You'll Learn

- 컨테이너 시작 4단계 (이미지 레이어 확인 → Active Snapshot 생성 → mount overlay → runc pivot_root)
- 컨테이너 삭제 3단계 (프로세스 종료 → merged unmount → Active Snapshot 삭제)
- Pause 컨테이너와 snapshot 번호 점프 — 번호가 재사용되지 않는 이유
- `ephemeral-storage`의 실체 = upperdir + emptyDir(non-tmpfs) + 컨테이너 로그
- Mi/Gi vs M/G 단위 차이 (약 7%)
- OOM이 아닌 `Evicted` 진단 흐름
- `emptyDir + sizeLimit`으로 OverlayFS CoW 오버헤드를 우회하는 패턴

---

## Step-02: Prerequisites

### 사전 코드 — 필요함

이번 Part는 세 개의 hands-on Lab을 진행합니다. Lab 5·6은 **YAML 매니페스트**를 사용합니다.

| 파일 | 용도 |
|------|------|
| `01_ephemeral-test.yaml` | Lab 5 — ephemeral-storage 100Mi limit + 150MiB 쓰기 → Evicted 재현 |
| `02_data-processing-job.yaml` | Lab 6 — emptyDir + sizeLimit 우회 패턴 |


Lab 4는 `kubectl run my-nginx --image=nginx` 한 줄로 시작하므로 별도 YAML이 필요 없습니다.


### 환경 요구사항

- ✅ Control Plane 노드 SSM 접속 가능
- ✅ Worker Node 1·2 SSM 접속 가능 (Lab 4 호스트 검증용)
- ✅ 클러스터 정상 동작 중 (kubeadm 부트스트랩 완료, Calico CNI Ready)

---

# 🔬 Lab 4 — 실제 K8s 컨테이너 스토리지 추적 (Full Scenario)

이번 챕터에서 가장 중요한 통합 Lab입니다. 실제 Pod를 띄우고, 호스트에서 그 Pod의 OverlayFS mount를 추적하며, 컨테이너 안에서 만든 파일이 호스트의 정확히 어느 폴더에 물리적으로 존재하는지 확인합니다.

> ⚠️ 이 Lab은 **두 노드(CP, Worker)를 오가며** 진행합니다. 각 Step마다 어느 노드에서 실행할지 명시되어 있습니다.

## Step-03: Nginx Pod 생성 (Control Plane에서 실행)


```bash
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - ubuntu
```


```bash
kubectl run my-nginx --image=nginx
```

```bash
kubectl get pod my-nginx -o wide
```


---

## Step-04: 워커 노드 접속 + 컨테이너 ID 확인 (Worker에서 실행)


```bash
aws ssm start-session --target <WK1_INSTANCE_ID> --region ap-northeast-2
sudo su - root
```

```bash
crictl ps | grep my-nginx
```

---

## Step-05: OverlayFS 4영역 mount 정보 추출 (Worker에서 실행)


```bash
mount | grep overlay | grep <CONTAINER_ID_12>
```

---

## Step-06: 컨테이너 내부에서 파일 생성 (Control Plane에서 실행)


```bash
kubectl exec my-nginx -- sh -c 'echo "This is Layer 44!" > /usr/share/nginx/html/magic.txt'
```

```bash
kubectl exec my-nginx -- cat /usr/share/nginx/html/magic.txt
```


---

## Step-07: 호스트에서 물리 파일 확인 (Worker에서 실행)


```bash
cat /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/44/fs/usr/share/nginx/html/magic.txt
```


```bash
ls /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/43/fs/usr/share/nginx/html/ 2>/dev/null
```

---

## Step-08: Pod 재생성 → 번호 점프 확인 (Control Plane에서 실행)


```bash
kubectl delete pod my-nginx
```

```bash
kubectl run my-nginx --image=nginx
```

```bash
kubectl wait --for=condition=Ready pod/my-nginx --timeout=60s
```


```bash
kubectl get pod my-nginx -o wide
```

---

## Step-09: 새 컨테이너의 snapshot ID 확인 (Worker에서 실행)

Step-08에서 확인한 워커로 이동합니다 (이전과 다른 워커일 수도 있습니다).


```bash
crictl ps | grep my-nginx
```


```bash
mount | grep overlay | grep <NEW_CID_12>
```


```bash
ls /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/ | sort -n
```


---

## Step-10: Lab 4 Cleanup (Control Plane에서 실행)

```bash
kubectl delete pod my-nginx
```


```bash
ls /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/ | sort -n
```

---

# 🔬 Lab 5 — Pod Eviction 재현 (ephemeral-storage 초과)

`100Mi` limit + `150MiB` 쓰기 → upperdir 초과 → Pod Evicted.

## Step-11: Lab 5 환경 준비 (Control Plane에서 실행)

Lab 4에서 이미 클론했다면 `cd`만 합니다. 아니면 클론부터.

```bash
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - ubuntu
```

```bash
git clone https://github.com/play-builder/linux-to-kubernetes.git
cd linux-to-kubernetes/Ch_05_Linux_overlayFS/05_04_kubernetes_and_overlayfs/lab-manifests
```

---

## Step-12: ephemeral-test 매니페스트 검토

```bash
cat 01_ephemeral-test.yaml
```


---

## Step-13: Pod 배포 및 watch

```bash
kubectl apply -f 01_ephemeral-test.yaml
```

```bash
kubectl get pods -w
```

---

## Step-14: Eviction 원인 확인


```bash
kubectl describe pod ephemeral-test | grep -A5 "Status:"
```


```bash
kubectl describe pod ephemeral-test | grep -A10 "Events:"
```

---

## Step-15: Lab 5 Cleanup

```bash
kubectl delete pod ephemeral-test
```

```bash
kubectl get pods
```

---

# 🔬 Lab 6 — emptyDir + sizeLimit 우회 패턴

임시 파일을 노드 디스크에 직접 쓰면서(CoW 오버헤드 우회) `sizeLimit`으로 노드 보호.

## Step-16: data-processing-job 매니페스트 검토

```bash
cat 02_data-processing-job.yaml
```


---

## Step-17: Job 배포

```bash
kubectl apply -f 02_data-processing-job.yaml
```

---

## Step-18: Job 진행 모니터링

```bash
kubectl get pods -l job-name=data-processor
```


```bash
kubectl logs -f job/data-processor
```

---

## Step-19: 호스트에서 emptyDir 위치 확인 (Worker에서 실행)


```bash
kubectl get pods -l job-name=data-processor -o wide
```


```bash
aws ssm start-session --target <WORKER_INSTANCE_ID> --region ap-northeast-2
sudo su - root
```

```bash
find /var/lib/kubelet/pods -type d -name "workspace" 2>/dev/null
```


```bash
ls -lh /var/lib/kubelet/pods/<POD_UID>/volumes/kubernetes.io~empty-dir/workspace/
```

---

## Step-20: Lab 6 Cleanup (Control Plane에서 실행)

```bash
kubectl delete -f 02_data-processing-job.yaml
```

---

## Step-21: Lab 5 vs Lab 6 비교

| 항목 | Lab 5 (ephemeral-storage 초과) | Lab 6 (emptyDir 우회) |
|------|-----------------------------|---------------------|
| **저장 위치** | OverlayFS upperdir (`/var/lib/containerd/.../snapshots/`) | emptyDir (`/var/lib/kubelet/pods/.../volumes/`) |
| **OverlayFS 경유?** | ✅ 경유 → CoW 발생 | ❌ 우회 → CoW 없음 |
| **ephemeral-storage 합산?** | ✅ 합산됨 | ✅ 합산됨 (`medium: Memory` 제외) |
| **노드 보호** | limit 초과 시 Pod evict | sizeLimit 초과 시 Pod evict |
| **데이터 휘발성** | Pod 삭제 시 함께 사라짐 | Pod 삭제 시 함께 사라짐 |

---


## Summary

- ✅ 실제 Pod을 생성하고 호스트에서 OverlayFS mount 추적
- ✅ 컨테이너 안에서 파일을 만들고 호스트의 정확한 upperdir snapshot 폴더에서 찾아 CoW가 K8s에서 동작함을 증명
- ✅ ephemeral-storage 초과로 Evicted(OOMKilled 아님) 재현
- ✅ emptyDir + sizeLimit 패턴으로 OverlayFS CoW 우회 실증
