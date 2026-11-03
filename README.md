# Linux to Kubernetes

리눅스 커널의 격리 원리(namespace, cgroup, overlayfs)에서 출발해 kubeadm 클러스터와 Istio ambient까지,
"컨테이너는 결국 리눅스 프로세스"라는 사실을 직접 확인하는 실습 과정입니다.

## 과정 지도

| 장 | 주제 |
|---|---|
| [Ch_00_K8s_Kubeadm_Project_Setup](Ch_00_K8s_Kubeadm_Project_Setup) | AWS에 kubeadm 클러스터 구축 (Terraform + userdata) |
| [Ch_01_Linux_Docker_Kubernetes_History](Ch_01_Linux_Docker_Kubernetes_History) | Linux → Docker → Kubernetes 역사, OOM / CPU throttle 실습 |
| [Ch_02_Linux_Kernel_Generals](Ch_02_Linux_Kernel_Generals) | 커널 기초: /proc, syscall trace, 커널 모듈과 파라미터 |
| [Ch_03_Linux_Namespaces](Ch_03_Linux_Namespaces) | Namespaces: hostPID, sidecar, shareProcessNamespace |
| [Ch_04_Linux_cgroup](Ch_04_Linux_cgroup) | cgroup v2와 QoS class (BestEffort / Burstable / Guaranteed) |
| [Ch_05_Linux_overlayFS](Ch_05_Linux_overlayFS) | overlayFS: 이미지 레이어와 ephemeral storage (README 작성 예정) |
| [Ch_06_Network](Ch_06_Network) | 네트워크: Linux 네트워크 기초부터 Service까지 (README 작성 예정) |
| [Ch_07_istio_ambient_service_mesh](Ch_07_istio_ambient_service_mesh) | Istio ambient: ztunnel(L4) / waypoint(L7), mTLS, AuthorizationPolicy (README 작성 예정) |
| [Volume_02](Volume_02) | 2부: 클러스터 구조와 동작 추적 (README 작성 예정) |

## 사전 준비

- AWS 계정, Terraform, kubectl
- 실습 클러스터는 [Ch_00](Ch_00_K8s_Kubeadm_Project_Setup)의 Terraform으로 만듭니다.
- 실습이 끝나면 비용이 계속 나가지 않도록 `terraform destroy`로 정리하세요.

## 검증

push와 PR마다 CI가 다음을 검사합니다.

- Kubernetes 매니페스트: `kubeconform -strict`
- 셸 스크립트: `shellcheck`
- Terraform: `fmt -check`, `validate`
