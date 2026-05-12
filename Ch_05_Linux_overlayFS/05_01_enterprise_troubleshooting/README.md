# # 05_01: Enterprise Troubleshooting — Netflix Mount Mayhem

## 📌 Step-01: Introduction

> **"OverlayFS가 단순히 이미지 레이어를 합쳐서 보여주는 기술이라면, 왜 Netflix 같은 글로벌 기업의 컨테이너 인프라가 OverlayFS 때문에 마비됐을까요?"**

본 세션에서는 2025년 11월 Netflix 기술 블로그에 공개된 **[Mount Mayhem at Netflix: Scaling Containers on Modern CPUs](https://netflixtechblog.com/mount-mayhem-at-netflix-scaling-containers-on-modern-cpus-f3b09b68beac)** 사례를 분석합니다.

96개의 CPU 코어를 가진 고성능 베어메탈 서버가 단지 '컨테이너를 띄우는 동작'만으로 왜 전체 불능 상태에 빠졌는지, OverlayFS의 `mount` 메커니즘과 리눅스 커널의 VFS(Virtual File System) 구조를 중심으로 그 원인을 추적합니다.

---

## 🔍 핵심 요약: 왜 장애가 발생했는가? (The Causal Chain)

Netflix 사례의 핵심은 "고성능 장비일수록 특정 커널 자원에 대한 경합(Contention)이 심화될 수 있다"는 점입니다. 장애의 인과 사슬은 다음과 같습니다.

1. **복잡한 이미지 구조:** 수십 개의 레이어(50+ `lowerdir`)로 구성된 대규모 컨테이너 이미지 사용.
2. **대규모 스케일링:** 96코어 서버에서 수백 개의 컨테이너를 동시에 시작.
3. **Mount Syscall 폭주:** 각 컨테이너 시작 시 OverlayFS 결합을 위한 `mount` 시스템 콜이 대량 발생.
4. **커널 락 경합:** 커널 내부의 Mount 테이블을 보호하는 락(Lock)에 과부하가 걸리며 CPU 스핀락(Spinlock) 발생.
5. **시스템 마비:** CPU가 실제 작업 대신 락을 획득하기 위해 대기하는 데 모든 자원을 소모하며 서버 전체가 정지(Soft Lockup).



---

## Step-02: 이 사례가 챕터 전체에서 차지하는 위치

이번 Part는 코드 실습 없이 사례 분석만 진행합니다. 하지만 이 사례에서 등장하는 모든 개념(OverlayFS 4영역, mount syscall, lowerdir 개수, snapshot 관리)을 다음 Part들에서 차례로 직접 검증합니다.

| 사례 속 주요 개념 | 연관 학습 Part (Lab) | 검증 내용 |
| --- | --- | --- |
| **50 레이어 이미지 = 50개 lowerdir** | 05_02 (Image Layer Concept) | 이미지 레이어가 실제 OverlayFS 구조로 변환되는 과정 |
| **mount 옵션 4KB 제한** | 05_03 (OverlayFS General) | 레이어가 너무 많을 때 발생하는 시스템적 제약 사항 |
| **mount syscall 발생** | 05_04 (Kubernetes & OverlayFS) | 컨테이너 런타임이 커널에 요청하는 실제 명령 추적 |
| **레이어 공유 메커니즘** | 05_03 (OverlayFS General) | 동일 이미지를 쓰는 컨테이너들이 스토리지를 효율적으로 쓰는 법 |


---

## References

- [Mount Mayhem at Netflix: Scaling Containers on Modern CPUs](https://netflixtechblog.com/) — Netflix Tech Blog, 2025년 11월

- Linux Kernel Documentation: Overlay Filesystem

