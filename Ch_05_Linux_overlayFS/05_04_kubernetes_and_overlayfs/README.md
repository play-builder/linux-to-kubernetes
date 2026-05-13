# 05_04: Kubernetes and OverlayFS

## Step-01: Introduction

### What You'll Learn

* 컨테이너 시작 4단계 (이미지 레이어 확인 → Active Snapshot 생성 → mount overlay → runc pivot_root)
* 컨테이너 삭제 3단계 (프로세스 종료 → merged unmount → Active Snapshot 삭제)
* Pause 컨테이너와 snapshot 번호 점프 — 번호가 재사용되지 않는 이유
* `ephemeral-storage`의 실체 = upperdir + emptyDir(non-tmpfs) + 컨테이너 로그
* Mi/Gi vs M/G 단위 차이 (약 7%)
* OOM이 아닌 `Evicted` 진단 흐름
* `emptyDir + sizeLimit`으로 OverlayFS CoW 오버헤드를 우회하는 패턴

---

## Step-02: Prerequisites

### 사전 코드 — 필요함

이번 Part는 세 개의 hands-on Lab을 진행합니다. Hands-on Lab 2·3은 **YAML 매니페스트**를 사용합니다.

| 파일 | 용도 |
| --- | --- |
| `01_ephemeral-test.yaml` | Hands-on Lab 2 — ephemeral-storage 100Mi limit + 150MiB 쓰기 → Evicted 재현 |
| `02_data-processing-job.yaml` | Hands-on Lab 3 — emptyDir + sizeLimit 우회 패턴 |

Hands-on Lab 1은 `kubectl run my-nginx --image=nginx` 한 줄로 시작하므로 별도 YAML이 필요 없습니다.

### 환경 요구사항

* ✅ Control Plane 노드 SSM 접속 가능
* ✅ Worker Node 1·2 SSM 접속 가능 (Hands-on Lab 1 호스트 검증용)
* ✅ 클러스터 정상 동작 중 (kubeadm 부트스트랩 완료, Calico CNI Ready)

---

# 🔬 Hands-on Lab 1 — 실제 K8s 컨테이너 스토리지 추적 (Full Scenario)

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

Step-03에서 확인한 NODE 컬럼의 워커(`wk1` 또는 `wk2`)에 접속합니다.

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

* `<UPPER>` = `upperdir=.../snapshots/<NUM>/fs` 의 NUM (이 컨테이너 전용 R/W 영역)
* `<L_TOP>` = `lowerdir=.../snapshots/<NUM>/fs:...` 의 첫 번째 NUM (이미지 최상위 레이어)

---

## Step-06: 컨테이너 내부에서 파일 생성 (Control Plane에서 실행)

```bash
kubectl exec my-nginx -- sh -c 'echo "Written by my-nginx container" > /usr/share/nginx/html/magic.txt'

```

```bash
kubectl exec my-nginx -- cat /usr/share/nginx/html/magic.txt

```

---

## Step-07: 호스트에서 물리 파일 확인 (Worker에서 실행)

`<UPPER>`를 Step-05에서 추출한 본인 환경의 upperdir 번호로 치환합니다.

```bash
cat /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/<UPPER>/fs/usr/share/nginx/html/magic.txt

```

`<L_TOP>`을 Step-05에서 추출한 본인 환경의 lowerdir 최상위 번호로 치환합니다.

```bash
ls /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/<L_TOP>/fs/usr/share/nginx/html/ 2>/dev/null

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

## Step-10: Hands-on Lab 1 Cleanup (Control Plane에서 실행)

```bash
kubectl delete pod my-nginx

```

```bash
ls /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/ | sort -n

```

---

# 🔬 Hands-on Lab 2 — Pod Eviction 재현 (ephemeral-storage 초과)

`100Mi` limit + `150MiB` 쓰기 → upperdir 초과 → Pod Evicted.

## Step-11: Hands-on Lab 2 환경 준비 (Control Plane에서 실행)

Hands-on Lab 1에서 이미 클론했다면 `cd`만 합니다. 아니면 클론부터.

```bash
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - ubuntu

```

```bash
git clone https://github.com/play-builder/linux-to-kubernetes.git
cd linux-to-kubernetes/Ch_05_Linux_overlayFS/05_04_kubernetes_and_overlayfs

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
kubectl describe pod ephemeral-evict-test | grep -A5 "Status:"

```

```bash
kubectl describe pod ephemeral-evict-test | grep -A10 "Events:"

```

---

## Step-15: Hands-on Lab 2 Cleanup

```bash
kubectl delete pod ephemeral-evict-test

```

```bash
kubectl get pods

```

---

# 🔬 Hands-on Lab 3 — emptyDir + sizeLimit 우회 패턴

임시 파일을 노드 디스크에 직접 쓰면서(CoW 오버헤드 우회) `sizeLimit`으로 노드 보호.

## Step-16: data-processing-job 매니페스트 검토

```bash
cat 02_data-processing-job.yaml

```

---

## Step-17: Pod 배포

```bash
kubectl apply -f 02_data-processing-job.yaml

```

---

## Step-18: Pod 진행 모니터링

```bash
kubectl get pod emptydir-bypass-test

```

```bash
kubectl logs -f emptydir-bypass-test

```

---

## Step-19: 호스트에서 emptyDir 위치 확인 (Worker에서 실행)

```bash
kubectl get pod emptydir-bypass-test -o wide

```

```bash
aws ssm start-session --target <WORKER_INSTANCE_ID> --region ap-northeast-2
sudo su - root

```

```bash
find /var/lib/kubelet/pods -type d -name "scratch-space" 2>/dev/null

```

```bash
ls -lh /var/lib/kubelet/pods/<POD_UID>/volumes/kubernetes.io~empty-dir/scratch-space/

```

---

## Step-20: Hands-on Lab 3 Cleanup (Control Plane에서 실행)

```bash
kubectl delete -f 02_data-processing-job.yaml

```

