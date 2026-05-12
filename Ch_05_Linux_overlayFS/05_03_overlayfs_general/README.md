# 05_03: OverlayFS General

## Step-01: Introduction

이번 Part는 OverlayFS의 세 가지 측면을 **이론과 실습을 짝지어** 다룹니다:

```
4영역 아키텍처       → 🔬 Lab 1 (4영역 직접 만들고 mount)
containerd 파일 경로  → 🔬 Lab 2 (containerd 경로 추적)
Three Operations      → 🔬 Lab 3 (Read/CoW/Whiteout 검증)
```


### What You'll Learn

- OverlayFS 4영역 — `lowerdir`(R/O), `upperdir`(R/W), `workdir`(atomic), `merged`(컨테이너의 /)
- containerd 두 경로 — `/var/lib/containerd` (이미지 저장소) vs `/run/containerd` (마운트 포인트)
- `Committed Snapshot`(이미지 레이어, 공유) vs `Active Snapshot`(컨테이너 변경분, 개별)
- snapshot 폴더가 SHA256이 아닌 숫자 ID로 만들어지는 이유 (mount 4 KB 제약)
- 읽기 / 쓰기(CoW) / 삭제(Whiteout) 세 가지 동작 메커니즘

---

## Step-02: Prerequisites

### 사전 코드 — 만들 필요 없음

이번 Part의 모든 실습은 호스트 시스템의 기본 명령어(`mkdir`, `mount`, `cat`, `ls`, `crictl`, `jq`)로만 진행됩니다.

- ❌ YAML 매니페스트 불필요
- ❌ Dockerfile 불필요
- ❌ 소스 코드 불필요

### 환경 요구사항

- ✅ Control Plane 노드 SSM 접속 가능 (Lab 2용)
- ✅ Worker Node 1번 SSM 접속 가능 + root 권한 (Lab 1·3용)
- ✅ `jq` 설치 (kubeadm 부트스트랩 시 자동 설치됨)

---

# 🔬 Lab 1 — OverlayFS 4개의 영역 직접 만들고 mount하기

## Step-03: Worker Node 1번에 root로 접속


```bash
aws ssm start-session --target <WK1_INSTANCE_ID> --region ap-northeast-2
sudo su - root
```

---

## Step-04: 4개의 영역 폴더 생성


```bash
mkdir -p /tmp/overlay/{lower,upper,work,merged}
```


```bash
ls /tmp/overlay/
```


---

## Step-05: lower에 테스트 파일 추가 (이미지 레이어 시뮬레이션)


```bash
echo "original content" > /tmp/overlay/lower/readme.txt
```

```bash
echo "config=production" > /tmp/overlay/lower/app.conf
```


```bash
find /tmp/overlay/ -type f
```

---

## Step-06: OverlayFS mount 실행

```bash
mount -t overlay overlay \
  -o lowerdir=/tmp/overlay/lower,upperdir=/tmp/overlay/upper,workdir=/tmp/overlay/work \
  /tmp/overlay/merged
```


---

## Step-07: mount 등록 확인

```bash
mount | grep "/tmp/overlay/merged"
```

---

## Step-08: merged 확인 — 4영역이 합성된 결과 검증

```bash
ls /tmp/overlay/merged/
```

```bash
cat /tmp/overlay/merged/readme.txt
```

```bash
cat /tmp/overlay/merged/app.conf
```


---

# 🔬 Lab 2 — containerd 파일 경로 추적

> ⚠️ Lab 2는 `Control Plane 노드`에서 실행합니다 (Lab 1·3과 다른 노드).

## Step-09: Control Plane 노드에 root로 접속

```bash
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - root
```

---

## Step-10: 이미지 저장소 경로 조회

```bash
ls /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/
```

```bash
ls /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/
```

---

## Step-11: 1번 snapshot 폴더 내부 확인

```bash
ls /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/1/
```


```bash
ls /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/1/work/
```

```bash
ls /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/1/fs/
```

---

## Step-12: 1번 snapshot을 사용하는 컨테이너 추적



```bash
mount | grep "snapshots/1/fs"
```


---

## Step-13: 컨테이너 ID로 어느 컨테이너인지 확인

```bash
crictl ps | grep <ID_앞_12자리_1>
```

```bash
crictl ps | grep <ID_앞_12자리_2>
```

```bash
crictl ps | grep <ID_앞_12자리_3>
```

---

## Step-14: 베이스 레이어 SHA256 동일성 검증

```bash
crictl images | grep kube-apiserver
```

```bash
crictl images | grep kube-scheduler
```

```bash
crictl images | grep kube-controller-manager
```

```bash
crictl inspecti <APISERVER_IMAGE_ID> | jq -r '.info.imageSpec.rootfs.diff_ids[0]'
```

```bash
crictl inspecti <SCHEDULER_IMAGE_ID> | jq -r '.info.imageSpec.rootfs.diff_ids[0]'
```

```bash
crictl inspecti <CONTROLLER_IMAGE_ID> | jq -r '.info.imageSpec.rootfs.diff_ids[0]'
```

---

## Step-15: 컨테이너 마운트 포인트 경로 조회


```bash
ls /run/containerd/io.containerd.runtime.v2.task/k8s.io/ | head -3
```

```bash
ls /run/containerd/io.containerd.runtime.v2.task/k8s.io/<CONTAINER_ID>/
```

---

# 🔬 Lab 3 — 세 가지 동작 검증 (Read / CoW / Whiteout)

> ⚠️ Lab 3은 다시 `Worker Node 1번`에서 root 권한으로 진행합니다 (Lab 1과 같은 노드, 같은 환경).

## Step-16: Lab 1 환경이 그대로인지 확인

```bash
mount | grep "/tmp/overlay/merged"
```

---

## Step-17: Read Path 검증
```bash
cat /tmp/overlay/merged/app.conf
```

```bash
ls /tmp/overlay/upper/
```

---

## Step-18: Copy-on-Write 검증

```bash
echo "modified content" > /tmp/overlay/merged/readme.txt
```

```bash
cat /tmp/overlay/upper/readme.txt
```


```bash
cat /tmp/overlay/lower/readme.txt
```


```bash
cat /tmp/overlay/merged/readme.txt
```


---

## Step-19: Whiteout (삭제) 검증


```bash
rm /tmp/overlay/merged/app.conf
```

```bash
ls -al /tmp/overlay/upper/
```

```bash
cat /tmp/overlay/upper/app.conf
```


```bash
cat /tmp/overlay/lower/app.conf
```

```bash
ls /tmp/overlay/merged/
```

---

## Step-20: Clean Up — umount 먼저, 그 다음 rm


```bash
rm -rf /tmp/overlay/
```



```bash
umount /tmp/overlay/merged
```


```bash
rm -rf /tmp/overlay/
```

---

## Summary

- ✅ 4영역을 손으로 만들고 mount해서 `lower` 파일이 `merged`를 통해 노출되는 것 확인
- ✅ containerd가 두 경로(`/var/lib/containerd` vs `/run/containerd`)로 분산 사용하는 것을 라이브 노드에서 추적
- ✅ kube-scheduler/apiserver/controller-manager가 snapshot 1을 동일한 SHA256으로 공유한다는 것 증명
- ✅ 직접 만든 OverlayFS 위에서 Read/CoW/Whiteout 검증
