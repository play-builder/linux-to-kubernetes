# Ch_02. Linux Kernel Generals

K8s의 모든 컴포넌트(`kubelet`, `containerd`, `runc`, `kube-proxy`, CNI)는 Linux Kernel 위에서 동작한다. 이 챕터에서는 커널의 핵심 구조 — `/proc` 가상 파일시스템, System Call, Core vs Module — 를 이해하고, K8s 노드의 필수 커널 설정(모듈 2개 + 파라미터 3개)을 직접 검증한다.

## Prerequisites

- kubeadm 기반 K8s 클러스터 (Control Plane 노드)
- root 권한 (`sudo su - root`)
- 모든 Lab은 `cp` 노드에서 실행

---

## Step-01: Lab 1 — `/proc` is Not on Disk

### Step-01-01: Review Lab Script (cp)

```bash
cat lab-scripts/01_proc_is_not_on_disk.sh
```

### Step-01-02: Run Lab 1 (cp)

```bash
chmod +x lab-scripts/01_proc_is_not_on_disk.sh
bash lab-scripts/01_proc_is_not_on_disk.sh
```

### Step-01-03: Verify Output

이 스크립트가 증명하는 것:
- `ls -altr /proc | head -15` → 파일 크기가 전부 `0`
- `du -sh /etc` vs `du -sh /proc` → `/proc`는 0 Byte (디스크 점유 없음)
- `cat /proc/uptime`을 1초 간격으로 두 번 → 값이 다름 (실시간 렌더링)

`/proc`는 디스크 파일이 아니라 커널이 RAM 상태를 텍스트로 렌더링한 가상 파일시스템임을 확인한다.

---

## Step-02: Lab 2 — CPU and Memory Info from `/proc`

### Step-02-01: Run Lab 2 (cp)

```bash
chmod +x lab-scripts/02_cpu_mem_info.sh
bash lab-scripts/02_cpu_mem_info.sh
```

### Step-02-02: Verify Mapping to `kubectl describe node` (cp)

```bash
kubectl describe node cp | grep -A6 "Capacity:"
```

이 스크립트가 증명하는 것:
- `/proc/cpuinfo`의 `processor` 카운트 = `kubectl describe node`의 `cpu: N`
- `/proc/cpuinfo`의 `flags`에 `hypervisor` 존재 → EC2 같은 VM 위에서 동작 중
- `/proc/meminfo`의 `SwapTotal: 0` → K8s 필수 조건 충족
- `MemAvailable` = kubelet의 eviction 판단 기준

---

## Step-03: Lab 3 — Trace System Calls with `strace`

### Step-03-01: Run Lab 3 (cp)

```bash
chmod +x lab-scripts/03_trace_syscalls.sh
bash lab-scripts/03_trace_syscalls.sh
```

### Step-03-02: Manual Trace (cp)

```bash
strace cat /proc/cpuinfo 2>&1 | grep -E "^(openat|read|write)" | head -6
```

핵심 syscall 3개:
- `openat("/proc/cpuinfo")` → 파일 디스크립터 반환
- `read(fd, buf, size)` → 커널이 RAM 상태를 텍스트로 렌더링하여 buf에 채움
- `write(1, buf, size)` → 화면(stdout, fd=1)에 출력

`User Space (cat) → syscall → Kernel (VFS) → 화면`의 흐름이 모든 Linux 동작의 기본 패턴이다.

---

## Step-04: Lab 4 — Core vs Module

### Step-04-01: Run Lab 4 (cp)

```bash
chmod +x lab-scripts/04_core_vs_module.sh
bash lab-scripts/04_core_vs_module.sh
```

### Step-04-02: Manual Verification (cp)

```bash
# Core (lsmod에 안 나타남)
lsmod | grep cgroup
mount | grep cgroup

# Module (lsmod에 나타남)
lsmod | grep overlay
```

| 구분 | lsmod 출력 | 예시 |
|------|------------|------|
| Core | ✕ | `cgroup`, Namespace, Scheduler |
| Module | ⭕ | `overlay`, `br_netfilter` |

`cgroup`은 Core이지만 `cgroup2` 타입 마운트로 파일시스템에 노출된다 (K8s 1.35는 cgroup v2 필수).

---

## Step-05: Lab 5 — Load K8s Required Kernel Modules

### Step-05-01: Run Lab 5 (cp)

```bash
chmod +x lab-scripts/05_load_k8s_modules.sh
bash lab-scripts/05_load_k8s_modules.sh
```

### Step-05-02: Verify Persistent Configuration (cp)

```bash
cat /etc/modules-load.d/k8s.conf
```

K8s 노드에 반드시 필요한 두 모듈:

| 모듈 | 역할 | 누락 시 증상 |
|------|------|--------------|
| `overlay` | 컨테이너 이미지 레이어 합성 | `CreateContainerError` |
| `br_netfilter` | 브릿지 트래픽을 iptables로 라우팅 | Service 통신 불가 |

`/etc/modules-load.d/k8s.conf`에 등록해야 재부팅 후에도 자동 로드된다.

---

## Step-06: Lab 6 — Verify K8s Required Kernel Parameters

### Step-06-01: Run Lab 6 (cp)

```bash
chmod +x lab-scripts/06_check_kernel_params.sh
bash lab-scripts/06_check_kernel_params.sh
```

### Step-06-02: Manual Verification (cp)

```bash
cat /proc/sys/net/ipv4/ip_forward
cat /proc/sys/net/bridge/bridge-nf-call-iptables
cat /proc/sys/net/bridge/bridge-nf-call-ip6tables
```

5가지 필수 조건:

| 항목 | 값 | 역할 |
|------|------|------|
| `overlay` 모듈 | loaded | 이미지 레이어 |
| `br_netfilter` 모듈 | loaded | 브릿지 → iptables |
| `ip_forward` | `1` | Pod 간 크로스 노드 라우팅 |
| `bridge-nf-call-iptables` | `1` | Service DNAT (IPv4) |
| `bridge-nf-call-ip6tables` | `1` | Service DNAT (IPv6) |

하나라도 누락되면 Pod 통신, Service DNAT, 크로스 노드 라우팅에서 치명적 장애가 발생한다.

---
