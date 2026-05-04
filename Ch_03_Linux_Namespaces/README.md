# Ch_03. Linux Namespaces

컨테이너 격리(isolation)의 정체는 Linux 커널의 Namespace 기능이다. 이 챕터에서는 8가지 Namespace 중 K8s에서 가장 중요한 4가지 — `PID`, `Mount`, `Network`, `UTS` — 를 직접 관찰하고, Pod 내 컨테이너들이 어떤 Namespace를 공유/격리하는지 검증한다.

## Prerequisites

- kubeadm 기반 K8s 클러스터
- root 권한 (`sudo su - root`)
- worker 노드는 `wk1`로 고정 (`nodeName: wk1`)

---

## Step-01: Lab 1 — `hostPID: true` Reveals All Host Processes

### Step-01-01: Review YAML Manifest (cp)

```bash
cat lab-manifests/01_nginx-hostpid.yaml
```

`hostPID: true`로 설정하면 컨테이너가 새 PID Namespace를 만들지 않고 호스트의 PID NS를 그대로 쓴다.

### Step-01-02: Deploy Pod (cp)

```bash
kubectl apply -f lab-manifests/01_nginx-hostpid.yaml
kubectl get pod nginx-hostpid -o wide
```

### Step-01-03: List All Processes Inside Container (cp)

```bash
kubectl exec -it nginx-hostpid -- ps -ef | head -20
```

`kubelet`, `containerd`, `systemd` 등 호스트의 모든 프로세스가 컨테이너 안에서 보인다. 이는 보안 위험이다 (운영 환경에서 사용 금지).

### Step-01-04: Cleanup (cp)

```bash
kubectl delete -f lab-manifests/01_nginx-hostpid.yaml
```

---

## Step-02: Lab 2 — Default Pod Has Its Own PID Namespace

### Step-02-01: Deploy Pod (cp)

```bash
kubectl apply -f lab-manifests/02_nginx-isolated.yaml
kubectl get pod nginx-isolated -o wide
```

### Step-02-02: List Processes Inside Container (cp)

```bash
kubectl exec -it nginx-isolated -- ps -ef
```

`PID 1`이 `nginx`이고 호스트 프로세스는 보이지 않는다. PID Namespace가 격리되었다는 증거.

### Step-02-03: Verify Different PID Namespace from Host (wk1)

```bash
# 컨테이너의 PID 1이 호스트에서는 어떤 PID로 보이는가?
CID=$(crictl ps --name nginx -q | head -1)
PID=$(crictl inspect $CID | jq .info.pid)
echo "Host PID: $PID"
ps -p $PID
```

같은 nginx 프로세스가 컨테이너에서는 `PID 1`, 호스트에서는 `PID NNNN`으로 보인다. 이것이 PID Namespace 격리의 정체다.

### Step-02-04: Compare Namespace Inodes (wk1)

```bash
# 호스트 PID 1의 NS inode
ls -la /proc/1/ns/pid

# 컨테이너 PID 1의 NS inode
ls -la /proc/$PID/ns/pid
```

inode 번호가 다르면 다른 Namespace에 속해 있다는 뜻.

### Step-02-05: Cleanup (cp)

```bash
kubectl delete -f lab-manifests/02_nginx-isolated.yaml
```

---

## Step-03: Lab 3 — Sidecar Pattern (Same Network NS, Different Mount NS)

### Step-03-01: Deploy Multi-container Pod (cp)

```bash
kubectl apply -f lab-manifests/03_nginx-sidecar.yaml
kubectl get pod ns-demo -o wide
```

### Step-03-02: Verify Same Network Namespace (cp)

```bash
# nginx 컨테이너에서 localhost로 접근 가능
kubectl exec -it ns-demo -c nginx -- curl -s http://localhost:80 | head -5

# log-collector 컨테이너에서도 localhost로 nginx 접근 가능
kubectl exec -it ns-demo -c log-collector -- wget -qO- http://localhost:80 | head -5
```

두 컨테이너가 같은 Network Namespace를 공유하므로 `localhost`로 서로 접근 가능하다. Pod의 핵심 동작 원리.

### Step-03-03: Verify Different Mount Namespace (cp)

```bash
# log-collector가 만든 /tmp/app.log
kubectl exec -it ns-demo -c log-collector -- ls -la /tmp/app.log

# nginx 컨테이너에서는 /tmp/app.log 없음
kubectl exec -it ns-demo -c nginx -- ls -la /tmp/app.log || echo "→ Not Found (Mount NS 격리됨)"
```

Mount Namespace는 격리되어 있어서 `/tmp/app.log`가 한쪽에만 존재한다. 파일 공유는 `volumeMounts`로 명시해야 한다.

### Step-03-04: Verify Namespace Inodes (wk1)

```bash
NGINX_CID=$(crictl ps --name nginx -q | head -1)
NGINX_PID=$(crictl inspect $NGINX_CID | jq .info.pid)

LOG_CID=$(crictl ps --name log-collector -q | head -1)
LOG_PID=$(crictl inspect $LOG_CID | jq .info.pid)

echo "=== nginx NS ==="
ls -la /proc/$NGINX_PID/ns/

echo "=== log-collector NS ==="
ls -la /proc/$LOG_PID/ns/
```

`net` inode는 같음 (Network NS 공유), `mnt`/`pid` inode는 다름 (Mount/PID NS 격리).

### Step-03-05: Cleanup (cp)

```bash
kubectl delete -f lab-manifests/03_nginx-sidecar.yaml
```

---

## Step-04: Lab 4 — Mount Namespace via MySQL

### Step-04-01: Deploy MySQL Pod (cp)

```bash
kubectl apply -f lab-manifests/04_mysql-same.yaml
kubectl get pod mysql-same -o wide
sleep 30  # MySQL 시작 대기
```

### Step-04-02: Inspect Container's Mount Namespace (wk1)

```bash
CID=$(crictl ps --name mysql -q | head -1)
PID=$(crictl inspect $CID | jq .info.pid)

# 컨테이너 안에서 본 마운트
nsenter -t $PID -m cat /proc/mounts | head -10

# 호스트에서 본 마운트 (전혀 다름)
cat /proc/mounts | head -10
```

MySQL 컨테이너의 `/var/lib/mysql`은 호스트의 다른 위치(overlayfs upper layer)에 매핑되어 있다.

### Step-04-03: Cleanup (cp)

```bash
kubectl delete -f lab-manifests/04_mysql-same.yaml
```

---

## Step-05: Lab 5 — `shareProcessNamespace: true`

### Step-05-01: Deploy Pod with Shared PID NS (cp)

```bash
kubectl apply -f lab-manifests/05_shared-process-ns.yaml
kubectl get pod ns-demo-shared -o wide
```

### Step-05-02: Verify Both Containers See Each Other's Processes (cp)

```bash
# log-collector에서 nginx 프로세스가 보임
kubectl exec -it ns-demo-shared -c log-collector -- ps -ef
```

`shareProcessNamespace: true`로 같은 Pod 내 컨테이너끼리 PID NS를 공유. log-collector가 nginx 프로세스를 직접 볼 수 있다.

### Step-05-03: Verify Same PID NS Inode (wk1)

```bash
NGINX_CID=$(crictl ps --name nginx -q | head -1)
NGINX_PID=$(crictl inspect $NGINX_CID | jq .info.pid)

LOG_CID=$(crictl ps --name log-collector -q | head -1)
LOG_PID=$(crictl inspect $LOG_CID | jq .info.pid)

ls -la /proc/$NGINX_PID/ns/pid
ls -la /proc/$LOG_PID/ns/pid
```

이번에는 `pid` inode도 같다 (PID NS도 공유).

### Step-05-04: Cleanup (cp)

```bash
kubectl delete -f lab-manifests/05_shared-process-ns.yaml
```

---

## Namespace 종류와 Pod의 공유 정책

| Namespace | 격리 대상 | Pod 내 컨테이너 간 |
|-----------|-----------|--------------------|
| `pid` | 프로세스 ID | 격리 (단, `shareProcessNamespace: true`로 공유 가능) |
| `net` | 네트워크 스택 | 공유 (localhost 통신 가능) |
| `mnt` | 마운트 포인트 | 격리 (volumeMounts로 명시 공유) |
| `uts` | 호스트명 | 공유 |
| `ipc` | SystemV IPC, POSIX 메시지 큐 | 공유 |
| `user` | UID/GID 매핑 | 공유 (보통) |
| `cgroup` | cgroup 루트 | 공유 |
| `time` | 시스템 시계 | 공유 |

---

