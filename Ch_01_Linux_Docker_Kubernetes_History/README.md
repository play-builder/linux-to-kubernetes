# Ch_01. Linux, Docker, Kubernetes — A Brief History

쿠버네티스가 왜 Linux 위에서만 동작하는지, 왜 Docker가 표준이 되었는지, 그리고 컨테이너 격리·자원 제한이 결국 Linux 커널 기능(Namespace, cgroup)으로 귀결되는 이유를 짧은 데모로 확인한다.

이 챕터의 두 Lab은 이후 챕터(`Ch_02 Kernel`, `Ch_03 Namespace`, `Ch_04 cgroup`)에서 깊이 파헤칠 두 가지 핵심 증상 — `OOMKilled`와 `CPU Throttling` — 을 미리 눈으로 본다.

---

## Step-01: Lab 1 — Reproduce `OOMKilled`

### Step-01-01: Review YAML Manifest (cp)

```bash
cat lab-manifests/01_oom-pod.yaml
```

`stress` 컨테이너가 200MiB 메모리 할당을 시도하지만, `limits.memory: 128Mi`로 제한되어 있다.

### Step-01-02: Deploy OOM-Inducing Pod (cp)

```bash
kubectl apply -f lab-manifests/01_oom-pod.yaml
```

### Step-01-03: Observe Pod Status (cp)

```bash
kubectl get pod oom-pod -w
```

`STATUS` 컬럼이 `Running` → `OOMKilled` → `CrashLoopBackOff`로 전환되는 것을 확인한다. `Ctrl+C`로 watch 종료.

### Step-01-04: Inspect Exit Code 137 (cp)

```bash
kubectl describe pod oom-pod | grep -A5 "Last State"
```

`Reason: OOMKilled`와 `Exit Code: 137` 확인.

### Step-01-05: Cleanup (cp)

```bash
kubectl delete -f lab-manifests/01_oom-pod.yaml
```

---

## Step-02: Lab 2 — Reproduce CPU Throttling

### Step-02-01: Review YAML Manifest (cp)

```bash
cat lab-manifests/02_throttle-pod.yaml
```

`stress --cpu 1`로 1코어를 100% 점유하려 하지만, `limits.cpu: 50m` (= 0.05 코어)로 제한되어 있다.

### Step-02-02: Deploy Throttle Pod (cp)

```bash
kubectl apply -f lab-manifests/02_throttle-pod.yaml
```

### Step-02-03: Verify Pod is Running (Not Killed) (cp)

```bash
kubectl get pod throttle-pod
```

CPU는 메모리와 달리 초과해도 Pod가 종료되지 않는다. 대신 throttle된다.

### Step-02-04: Observe CPU Throttling on Node (wk1)

```bash
POD_UID=$(kubectl get pod throttle-pod -o jsonpath='{.metadata.uid}' | tr '-' '_')
CGROUP_DIR=$(find /sys/fs/cgroup/kubepods.slice -type d -name "*pod${POD_UID}*" | head -1)
cat $CGROUP_DIR/cpu.stat
```

`nr_throttled` 값이 0보다 큰 것을 확인 (throttle 발생 횟수).

### Step-02-05: Cleanup (cp)

```bash
kubectl delete -f lab-manifests/02_throttle-pod.yaml
```

---
