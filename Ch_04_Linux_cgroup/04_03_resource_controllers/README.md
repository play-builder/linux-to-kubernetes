# 04-03: Resource Controllers

## Step-01: Verify YAML → cgroup File Mapping

### Step-01-01: Deploy Test Pod (cp)

```bash
kubectl apply -f lab-manifests/01_resource-mapping-pod.yaml
kubectl get pod resource-mapping-pod -o wide
```

### Step-01-02: Get Pod UID for cgroup Lookup (cp)

```bash
POD_UID=$(kubectl get pod resource-mapping-pod -o jsonpath='{.metadata.uid}')
echo $POD_UID
```

### Step-01-03: Find Pod cgroup Directory (wk1)

```bash
# Replace <POD_UID> with the value from Step-01-02
POD_UID_UNDERSCORE="$(echo <POD_UID> | tr '-' '_')"
POD_DIR=$(find /sys/fs/cgroup/kubepods.slice -type d -name "*pod${POD_UID_UNDERSCORE}*" | head -1)
echo $POD_DIR

CONTAINER_DIR=$(find $POD_DIR -type d -name "cri-containerd-*" | head -1)
echo $CONTAINER_DIR
```

### Step-01-04: Read cgroup Files (wk1)

```bash
cat $CONTAINER_DIR/memory.max
cat $CONTAINER_DIR/cpu.max
cat $CONTAINER_DIR/cpu.weight
```

### Step-01-05: Cleanup (cp)

```bash
kubectl delete -f lab-manifests/01_resource-mapping-pod.yaml
```

---

## Step-02: Verify Page-based Memory Allocation (wk1)

```bash
getconf PAGESIZE
echo "512Mi = $((512 * 1024 * 1024)) bytes"
echo "536870912 / 4096 = $((536870912 / 4096)) pages"
```

---

## Step-03: Lab 1 — Reproduce OOM Kill

### Step-03-01: Check dmesg Initial State (wk1)

```bash
dmesg -T | grep -i oom
```

### Step-03-02: Deploy OOM-Inducing Pod (cp)

```bash
cat lab-manifests/02_oom-pod.yaml
kubectl apply -f lab-manifests/02_oom-pod.yaml
```

### Step-03-03: Verify Pod Status (cp)

```bash
kubectl get pod oom-pod
kubectl describe pod oom-pod | grep -A3 "Last State"
```

### Step-03-04: Verify Kernel OOM Log (wk1)

```bash
dmesg -T | grep -i oom
```

### Step-03-05: Cleanup (cp)

```bash
kubectl delete -f lab-manifests/02_oom-pod.yaml
kubectl get pod
```
