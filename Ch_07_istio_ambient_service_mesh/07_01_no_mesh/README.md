# 07_01_no_mesh: 메시 없는 환경의 한계 (Life Without a Mesh)

## Step-01: Introduction

### What You'll Learn

* 메시 없는 순수 K8s에서 두 마이크로서비스 통신의 한계 3가지 직접 재현
* 평문 노출 추적: `tcpdump`로 `?secret=password123`이 네트워크에 그대로 보이는 것 확인
* 호출자 신원 부재 확인: 백엔드가 `누가 호출했는지` 알 수 없는 구조 (`curl -v` 헤더 추적)
* 메트릭 부재 확인: 응답 시간을 운영자가 `curl`로 직접 측정해야 하는 상황
* 다음 Lab(`07_02_ambient`)에서 Istio Ambient가 이 셋을 어떻게 해결하는지 비교할 기준선 확보

---

## Step-02: Prerequisites

### 사전 코드 — 필요함

이번 Part는 하나의 Hands-on Lab 안에서 메시 없는 환경의 세 가지 한계(평문 노출, 신원 부재, 메트릭 부재)를 차례로 추적합니다.

### 환경 요구사항

* ✅ Kubeadm 기반 K8s 클러스터 환경 구축

  참고: [Kubeadm Project Setup](https://github.com/play-builder/linux-to-kubernetes/tree/main/Ch_00_K8s_Kubeadm_Project_Setup)

* ✅ 노드 구성
  * `cp` (Control Plane)
  * `wk1`
  * `wk2`

### 파일 구성

| 파일 | 역할 |
|---|---|
| `no-mesh-api.yaml` | http-echo 백엔드 (Deployment + Service, `wk1` 노드) |
| `no-mesh-client.yaml` | netshoot 클라이언트 (Pod, `wk2` 노드) |
| `measure-latency.sh` | 응답 시간 수동 측정 헬퍼 |

---

# 🔬 Hands-on Lab — 메시 없는 환경의 한계 추적

메시가 없는 순수 쿠버네티스 환경에서 두 마이크로서비스가 통신할 때 드러나는 한계를, 패킷 캡처와 헤더 추적으로 직접 확인합니다.

---

## Step-01: 작업 환경 접속 및 namespace 생성 (cp)

```bash
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - ubuntu

kubectl create namespace no-mesh
kubectl get ns no-mesh --show-labels    # Istio 라벨이 하나도 없는 순수 상태
```

무엇을 봐야 하나

* `no-mesh` namespace에 Istio 관련 라벨이 없음 — `07_02_ambient`에서는 ambient 라벨이 붙음

---

## Step-02: 백엔드와 클라이언트 배포 (cp)

api와 client를 서로 다른 노드에 배치합니다. 트래픽이 노드의 물리 인터페이스를 통과해야 뒤에서 tcpdump로 캡처할 수 있습니다.

```bash
git clone https://github.com/play-builder/linux-to-kubernetes.git
cd linux-to-kubernetes/Ch_07_istio_ambient_service_mesh/07_01_no_mesh

cat no-mesh-api.yaml       # http-echo 백엔드, nodeName: wk1, Service 80 → 8080
cat no-mesh-client.yaml    # netshoot 클라이언트, nodeName: wk2
```

```bash
kubectl apply -n no-mesh -f no-mesh-api.yaml -f no-mesh-client.yaml
kubectl -n no-mesh get pods -o wide    # 노드 배치 확인
kubectl -n no-mesh get svc             # api Service ClusterIP 확인
```

무엇을 봐야 하나

* api=`wk1`, client=`wk2`, 둘 다 `1/1 Running` (사이드카가 없으므로 `1/1`)
* api Service ClusterIP (예: `10.96.123.45`)

---

## Step-03: 정상 동작 — 메시 없이도 통신은 된다 (cp)

```bash
kubectl -n no-mesh exec <POD_NAME> -- \
  curl -s -w "\nHTTP %{http_code}\n" http://api.no-mesh.svc.cluster.local/
```

무엇을 봐야 하나

* `Hello from API` + `HTTP 200` — 통신 자체는 정상. 이어지는 Step에서 보안·관찰성 한계가 드러남

---

## Step-04: [한계 1] 평문 캡처를 위한 wk1 접속 (wk1)

평문 트래픽을 보려면 api 파드가 떠 있는 `wk1`에서 패킷을 떠야 합니다. 별도 터미널을 띄워 접속합니다.

```bash
aws ssm start-session --target <WK1_INSTANCE_ID> --region ap-northeast-2
sudo su - root    # tcpdump는 root 권한 필요
```

무엇을 봐야 하나

* `wk1`은 api 파드가 트래픽을 수신하는 노드

---

## Step-05: [한계 1] tcpdump로 8080 캡처 (wk1)

```bash
tcpdump -i any -A -s 0 'tcp port 8080' -c 20    # -A: 페이로드 ASCII 출력, -c 20: 20개 후 종료
```

무엇을 봐야 하나

* 이 터미널을 띄워둔 채, 다음 Step에서 호출을 보냄

---

## Step-06: [한계 1] 민감 정보 포함 호출 보내기 (cp)

wk1의 tcpdump가 도는 동안, Control Plane에서 민감 정보를 쿼리스트링에 담아 호출합니다. (토큰·비밀번호가 URL에 실리는 상황을 모사)

```bash
kubectl -n no-mesh exec client -- \
  curl -s http://api.no-mesh.svc.cluster.local/?secret=password123
```

무엇을 봐야 하나

* 호출 직후 wk1의 tcpdump 터미널에 패킷이 잡힘

---

## Step-07: [한계 1 결과] 평문 그대로 노출 (wk1)

Step-05의 tcpdump 출력을 확인합니다.

무엇을 봐야 하나

* 캡처된 패킷에 `GET /?secret=password123`이 평문으로 보임 (`User-Agent`·`Host` 헤더도 평문)
* 메시가 없으면 노드 간 트래픽이 암호화되지 않음 → 첫 번째 한계

---

## Step-08: [한계 2] 호출자 신원이 없음 (cp)

```bash
kubectl -n no-mesh exec deploy/client -- \
    sh -c 'curl -sv http://api.no-mesh.svc.cluster.local/ 2>&1' | grep -E "^> |^< "
```

무엇을 봐야 하나

* 요청 헤더(`>`)에 호출자를 식별할 정보가 없음 — `User-Agent: curl/...`이 전부
* 백엔드는 누가 호출했는지·위조 요청인지 알 수 없음 → `order SA만 결제 호출 가능` 같은 정책을 세울 근거가 없음 → 두 번째 한계

---

## Step-09: [한계 3] 응답 시간을 직접 측정 (cp)

메시가 없으면 운영자가 직접 응답 시간을 측정해야 합니다. 헬퍼 스크립트로 수동 측정을 재현합니다.

```bash
bash measure-latency.sh        # 기본 횟수만큼 호출하며 time_total 측정
bash measure-latency.sh 10     # 인자로 호출 횟수 지정
```

무엇을 봐야 하나

* 각 호출의 `time_total`을 `curl`로 직접 측정 — 메트릭을 얻으려고 측정 코드를 짜야 함 → 세 번째 한계
* 메시가 있으면 ztunnel이 이런 메트릭을 자동 수집 (`07_02_ambient`에서 확인)

---

## Step-10: Cleanup (cp)

```bash
kubectl delete namespace no-mesh    # 안의 Deployment·Service·Pod 함께 삭제
kubectl get ns no-mesh
```

무엇을 봐야 하나

* `NotFound` 에러가 나오면 삭제 완료

---

다음: [`07_02_ambient`](../07_02_ambient/) 에서 Istio Ambient를 적용해 같은 시나리오를 재현하고, 이 세 한계가 어떻게 해소되는지 비교합니다.

