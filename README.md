# [Linux to Kubernetes — 리눅스 커널부터 쿠버네티스 운영까지](https://github.com/play-builder/linux-to-kubernetes)

> **"아주 어려운 내용을 아주 쉽게"** — Play Builder Kai의 Kubernetes Internals Mastery 시리즈

쿠버네티스의 모든 동작은 결국 Linux 커널의 기능(`Namespace`, `cgroup`, `overlayfs`, `Netfilter`)으로 환원된다. 이 시리즈는 시니어 엔지니어 수준의 정확성을 유지하면서, 입문자도 따라올 수 있도록 한 줄씩 명령어를 치며 검증하는 실습 자료다.


---

## Course Details (강의 정보)

- **Title:** Linux to Kubernetes — From Kernel to Production
- **Sub Title:** ALL-IN-ONE: Linux Kernel Internals + kubeadm Cluster + Networking + cgroup + Troubleshooting
- **Format:** GitHub 레포 + 강의 스크립트 + Lab 실습 + 판서 (PowerPoint 슬라이드 없음)
- **Total Chapters:** 10+ (지속 업데이트 중)


---

## Cluster Environment (실습 환경)

본 시리즈는 **EKS가 아닌 kubeadm 기반 K8s**를 사용한다. EKS는 control plane을 추상화해 숨기지만, kubeadm은 etcd, apiserver, scheduler, controller-manager의 내부를 그대로 노출하므로 internals 학습에 적합하다.

| Component | Version | Purpose |
|-----------|---------|---------|
| Kubernetes | 1.35 | Container Orchestration |
| Container Runtime | containerd v2.x | CRI Runtime (Docker 아님) |
| CNI Plugin | Calico v3.31.x | Direct Routing (Non-overlay) |
| Cluster Bootstrap | kubeadm | Manual Cluster Setup |
| IaC | Terraform >= 1.14 | AWS Provisioning |
| Cloud | AWS EC2 | Ubuntu 24.04 LTS |
| Nodes | cp + wk1 + wk2 | 1 Control Plane + 2 Workers |


---

## What Makes This Course Unique? (이 시리즈만의 특징)

- ✅ **EKS가 아닌 kubeadm**: Control plane을 직접 운영하여 internals 학습
- ✅ **커널 레벨 검증**: 모든 K8s 동작을 `/proc`, `/sys/fs/cgroup`, `iptables`로 추적
- ✅ **실제 클러스터 출력**: 가상 예시(fabricated example) 절대 금지, 모든 출력은 실제 검증

- ✅ **시험 대비**: CKA / CKAD / CKS 출제 범위 완전 커버 + 커널 이해 기반 합격

---

## Prerequisites (수강 전 준비)

### **필수 조건**
- **AWS 계정**: EC2, VPC, IAM 리소스 생성 권한 (Free Tier 일부 사용)
- **로컬 환경**: AWS CLI, Terraform >= 1.14, kubectl 설치 가능한 OS (Mac/Linux/Windows)
- **터미널 기본기**: `cd`, `ls`, `cat`, `vim` 같은 기본 명령어 사용 가능
- **인터넷 연결**: AWS 콘솔 접근, 패키지 다운로드

### **있으면 좋은 것 (필수 아님)**
- Linux 기본 (프로세스, 파일시스템 개념)
- Docker 사용 경험 (`docker run`, `docker ps` 수준)
- Git 기본 (`clone`, `commit`, `push`)
- 네트워크 기본 (IP, Subnet, Port 개념)

### **필요 없는 것**
- ❌ Kubernetes 사전 지식 (처음부터 가르침)
- ❌ Terraform 사전 지식 (Ch_00에서 자동 프로비저닝)
- ❌ AWS 자격증
- ❌ 프로그래밍 언어 (Go, Java 등)

### **AWS 비용 (참고)**
- Spot Instance 활용으로 비용 최소화 (`t3.small` × 2)
- 챕터별 실습 후 `terraform destroy`로 정리 권장
- **예상 비용:** 전체 시리즈 완주 시 약 $20–$50 (꾸준히 정리 시)



---

## Who Is This For? (수강 대상)

### **딱 맞는 분**
- **K8s 입문자**: "Pod가 왜 죽는지" 근본부터 이해하고 싶은 분
- **CKA / CKAD / CKS 시험 준비생**: 단순 암기가 아닌 이해 기반 합격을 원하는 분
- **K8s 운영 엔지니어**: EKS의 추상화 너머 internals를 보고 싶은 분
- **Linux 시스템 엔지니어**: 컨테이너가 결국 Linux 기능임을 검증하고 싶은 분
- **DevOps 전환 희망자**: 시니어 수준의 디버깅 능력을 갖추고 싶은 분
- **백엔드 개발자**: 자신의 서비스가 어떤 환경에서 동작하는지 알고 싶은 분

### **이런 목표라면**
- ✅ kubeadm으로 K8s 클러스터를 처음부터 구축하고 운영
- ✅ `OOMKilled`, CPU Throttling 같은 증상의 근본 원인 진단
- ✅ Calico, kube-proxy, iptables를 한 줄씩 분석
- ✅ CKA / CKAD / CKS 시험 합격 + 실무 역량 동시 확보
- ✅ EKS의 마법 같은 동작을 직접 분해

---

## GitHub Repositories (관련 레포지토리)

- **Main Repository:** [linux-to-kubernetes](https://github.com/play-builder/linux-to-kubernetes) (이 레포)
- **권장:** 이 레포를 **Fork**하여 자신의 변경사항을 commit하며 학습하세요

---


## Connect with Play Builder (소통)

- **GitHub:** [github.com/play-builder](https://github.com/play-builder)

---


**🚀 Linux 커널부터 Kubernetes Production까지 — 함께 시작합시다!**


