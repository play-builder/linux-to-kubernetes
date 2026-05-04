# Ch_04. Linux cgroup v2

자원 제한(quota)의 정체 — 실제 핀테크 기업의 OOMKilled 추적 사례로 시작해 cgroup v2를 완전 해부한다. K8s YAML의 `requests`/`limits`가 어떻게 커널 인터페이스(`cpu.max`, `memory.max`)로 변환되는지, BestEffort/Burstable/Guaranteed Pod이 OOM 우선순위에 어떤 영향을 미치는지 직접 검증한다.

## Prerequisites

- kubeadm 기반 K8s 클러스터 (`Ch_00` 완료)
- `Ch_03 Linux Namespaces` 학습 권장 (Namespace와 cgroup의 차이 비교용)
- root 권한 (`sudo su - root`)

## Sub-modules

| Module | Topic | 핵심 내용 |
|--------|-------|-----------|
| [04_01](./04_01_enterprise_troubleshooting/) | Enterprise Troubleshooting | Endowus 핀테크 사례 + 챕터 5대 핵심 질문 |
| [04_02](./04_02_cgroup_general/) | cgroup General | `/sys/fs/cgroup`은 실제 파일 + Namespace와의 차이 |
| [04_03](./04_03_resource_controllers/) | Resource Controllers | YAML `limits` → `memory.max`/`cpu.max` 매핑 + OOM 재현 |
| [04_04](./04_04_qos_class_and_oom/) | QoS Class & OOM Score | BestEffort/Burstable/Guaranteed의 `oom_score_adj` 비교 |
