# 04-02: cgroup General

## Step-01: Verify cgroup is a Real File (wk1)

```bash
# Enter wk1 worker node
ssh root@wk1

# Check cgroup v2 root directory
ls /sys/fs/cgroup/ | head -10

# Read kubelet's cgroup files directly
cat /sys/fs/cgroup/system.slice/kubelet.service/memory.max
cat /sys/fs/cgroup/system.slice/kubelet.service/cpu.max
cat /sys/fs/cgroup/system.slice/kubelet.service/memory.current
```

---

## Step-02: Verify Namespace and cgroup are Separate Kernel Interfaces (wk1)

```bash
# Namespace interface
ls /proc/1/ns/

# cgroup interface
ls /sys/fs/cgroup/ | head -10
```

---

## Step-03: Verify CPU vs Memory Files Differ (wk1)

```bash
# List all cpu.* and memory.* files
ls /sys/fs/cgroup/system.slice/kubelet.service/ | grep -E "^(cpu|memory)"

# CPU throttling counters (cpu.stat)
cat /sys/fs/cgroup/system.slice/kubelet.service/cpu.stat

# Memory OOM counters (memory.events)
cat /sys/fs/cgroup/system.slice/kubelet.service/memory.events
```
