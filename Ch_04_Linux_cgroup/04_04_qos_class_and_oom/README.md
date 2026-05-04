# 04-04: QoS Class and OOM Score

## Step-01: Lab 2 — Deploy QoS 3-Class Pods

### Step-01-01: Review YAML Manifests (cp)

```bash
# Enter Control Plane node
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - ubuntu

cat lab-manifests/03_besteffort-pod.yaml
cat lab-manifests/04_burstable-pod.yaml
cat lab-manifests/05_guaranteed-pod.yaml
```

### Step-01-02: Deploy 3 Pods (cp)

```bash
kubectl apply -f lab-manifests/03_besteffort-pod.yaml \
              -f lab-manifests/04_burstable-pod.yaml \
              -f lab-manifests/05_guaranteed-pod.yaml
```

### Step-01-03: Verify Pod Status (cp)

```bash
kubectl get pods -o wide
```

### Step-01-04: Verify QoS Class Assignment (cp)

```bash
kubectl get pod besteffort-pod -o jsonpath='{.status.qosClass}{"\n"}'
kubectl get pod burstable-pod  -o jsonpath='{.status.qosClass}{"\n"}'
kubectl get pod guaranteed-pod -o jsonpath='{.status.qosClass}{"\n"}'
```

---

## Step-02: Extract CID and PID for Kernel Verification (wk1)

```bash
# Enter wk1 worker node
aws ssm start-session --target <WK1_INSTANCE_ID> --region ap-northeast-2
sudo su - root

crictl ps
```

```bash
# By container name (not pod name)
CID=$(crictl ps --name nginx-besteffort -q)
echo $CID

PID=$(crictl inspect $CID | jq .info.pid)
echo $PID
```

---

## Step-03: Lab 3 — Verify oom_score_adj per QoS Class

### Step-03-01: kubelet and containerd Score (cp)

```bash
# Enter Control Plane node
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - ubuntu

cat /proc/$(pgrep -x kubelet)/oom_score_adj
cat /proc/$(pgrep -x containerd)/oom_score_adj
```

### Step-03-02: BestEffort Pod Score (wk1)

```bash
# Enter wk1 worker node
aws ssm start-session --target <WK1_INSTANCE_ID> --region ap-northeast-2
sudo su - root

CID=$(crictl ps --name nginx-besteffort -q)
PID=$(crictl inspect $CID | jq .info.pid)
cat /proc/$PID/oom_score_adj
```

### Step-03-03: Burstable Pod Score (wk1)

```bash
CID=$(crictl ps --name nginx-burstable -q)
PID=$(crictl inspect $CID | jq .info.pid)
cat /proc/$PID/oom_score_adj
```

### Step-03-04: Guaranteed Pod Score (wk2)

```bash
# Enter wk2 worker node
aws ssm start-session --target <WK2_INSTANCE_ID> --region ap-northeast-2
sudo su - root

CID=$(crictl ps --name nginx-guaranteed -q)
PID=$(crictl inspect $CID | jq .info.pid)
cat /proc/$PID/oom_score_adj
```

---

## Step-04: Lab 4 — Verify cgroup Tree and cpu.weight

### Step-04-01: Visualize cgroup Tree (cp)

```bash
# Enter Control Plane node
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - ubuntu

# system.slice vs kubepods.slice — top-level separation
tree -d -L 2 /sys/fs/cgroup/

# Inside kubepods.slice — Guaranteed Pod sits here directly
ls -al /sys/fs/cgroup/kubepods.slice
```

### Step-04-02: cpu.weight on Control Plane (cp)

```bash
cat /sys/fs/cgroup/system.slice/cpu.weight
cat /sys/fs/cgroup/kubepods.slice/cpu.weight
cat /sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/cpu.weight
cat /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/cpu.weight
```

### Step-04-03: cpu.weight on Worker Node (wk1)

```bash
# Enter wk1 worker node
aws ssm start-session --target <WK1_INSTANCE_ID> --region ap-northeast-2
sudo su - root

cat /sys/fs/cgroup/system.slice/cpu.weight
cat /sys/fs/cgroup/kubepods.slice/cpu.weight
cat /sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/cpu.weight
cat /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/cpu.weight
```
### Step-04-04: cpu.request on Control Plane (cp) and Worker Node (wk1)

```bash
kubectl describe node cp
kubectl describe node wk1
```

---

## Step-05: Cleanup (cp)

```bash
# Enter Control Plane node
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - ubuntu

kubectl delete -f lab-manifests/
kubectl get pods
```
