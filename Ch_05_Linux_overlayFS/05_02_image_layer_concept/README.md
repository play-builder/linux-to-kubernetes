# 05_02: Image Layer Concept

## Step-01: Introduction

이미지 레이어가 무엇인지 정확히 이해하고, 컨테이너 이미지가 왜 단일 파일이 아닌 **레이어들의 조합**으로 설계되었는지를 다룹니다. 그리고 세 가지 설계 원리(`Layer Sharing`, `Build Cache`, `Immutability`)를 직접 손으로 검증합니다.

**이번 Part가 답하는 질문:**

**"컨테이너 이미지는 왜 단일 파일이 아니라 읽기 전용 레이어들이 쌓인 구조일까요?"**

### What You'll Learn

- 컨테이너 이미지 = `여러 레이어의 합` (단일 파일이 아닌 이유)
- Dockerfile 한 줄(`FROM`/`RUN`/`COPY`)이 정확히 한 레이어를 만드는 메커니즘
- 레이어로 분리한 3가지 설계 의도 — `Layer Sharing`, `Build Cache`, `Immutability`
- `docker inspect`로 두 이미지의 레이어 SHA256을 비교하여 공유 사실을 직접 증명
- `docker build`의 `CACHED` 출력으로 캐시 효율 메커니즘을 직접 검증
- 이미지 ID(SHA256)가 콘텐츠 1비트 단위로 무결성을 보장한다는 사실 확인

---

## Step-02: Prerequisites

### 사전 코드 — 필요함
이번 Lab은 Docker 이미지 빌드를 수행하므로 다음 파일들이 사전에 준비되어 있어야 합니다. 깃헙 레포에 이미 포함되어 있으므로 클론만 하면 됩니다.

| 파일 | 역할 |
|------|------|
| `Dockerfile.nginx` | ubuntu:22.04 베이스 + nginx 설치 |
| `Dockerfile.node` | ubuntu:22.04 베이스 + nodejs 설치 + app.js 복사 |
| `app.js` | 캐시 효율 검증용 샘플 코드 |



### 환경 요구사항

- ✅ Control Plane 노드 SSM 접속 가능
- ✅ `docker` 설치되어 있음 (kubeadm 부트스트랩 시 자동 설치됨)
- ✅ `git` 설치되어 있음

---

## Step-03: Control Plane 접속 및 실습 준비

CP에 SSM으로 접속해 ubuntu 사용자로 전환합니다.

```bash
aws ssm start-session --target <CP_INSTANCE_ID> --region ap-northeast-2
sudo su - ubuntu
```

레포지토리를 클론하고 Lab 폴더로 이동합니다.

```bash
git clone https://github.com/play-builder/linux-to-kubernetes.git
cd linux-to-kubernetes/Ch_05_Linux_overlayFS/05_02_image_layer_concept/image-layer-sharing
```

폴더 구성을 확인합니다.

```bash
ls -la
```

각 파일의 내용을 살펴봅니다.

```bash
cat Dockerfile.nginx
```

```bash
cat Dockerfile.node
```

```bash
cat app.js
```

---

## Step-04: Nginx 커스텀 이미지 빌드

ubuntu:22.04를 베이스로 사용하는 Nginx 이미지를 빌드하고 `v1` 태그를 붙입니다.

```bash
sudo docker build -t my-nginx:v1 -f Dockerfile.nginx .
```

빌드된 이미지를 확인합니다.

```bash
sudo docker images | grep my-nginx
```

---

## Step-05: Node.js 커스텀 이미지 빌드

동일하게 ubuntu:22.04를 베이스로 사용하는 Node.js 이미지를 빌드합니다.

```bash
sudo docker build -t my-node:v1 -f Dockerfile.node .
```

```bash
sudo docker images | grep -E "my-nginx|my-node"
```

---

## Step-06: Layer Sharing 증명 — 레이어 해시 비교

두 이미지의 내부 구조를 조회하여 레이어 해시를 비교합니다.

Nginx 이미지의 레이어 해시를 확인합니다.

```bash
sudo docker inspect my-nginx:v1 | grep -A 5 "Layers"
```

Node.js 이미지의 레이어 해시를 확인합니다.

```bash
sudo docker inspect my-node:v1 | grep -A 5 "Layers"
```

---

## Step-07: Build Cache 증명 — 캐시 효율 검증

`app.js`를 수정한 뒤 v2 이미지를 빌드합니다.

현재 app.js 내용을 확인합니다.

```bash
cat app.js
```

코드를 한 줄 추가합니다.

```bash
echo "console.log('Update');" >> app.js
```

수정된 내용을 확인합니다.

```bash
cat app.js
```

v2 이미지를 빌드합니다.

```bash
sudo docker build -t my-node:v2 -f Dockerfile.node .
```

---

## Step-08: Immutability 증명 — 이미지 ID 무결성

이미지의 고유 ID(SHA256)를 확인합니다.

```bash
sudo docker inspect --format='{{.Id}}' my-nginx:v1
```


---

## Step-09: Clean Up

빌드한 이미지를 정리합니다.

```bash
sudo docker rmi my-nginx:v1 my-node:v1 my-node:v2
```

원본 app.js로 복원합니다.

```bash
git checkout app.js
cat app.js
```

---

## Step-10: Production Best Practices

레이어 메커니즘을 이해했으니, 프로덕션에서 어떻게 적용할지 알아봅니다.

### 1. Dockerfile 명령어를 안정 → 변동 순서로 배치

**왜:** 어떤 레이어가 변경되면 그 아래(Dockerfile 기준)의 모든 레이어가 캐시 무효화됩니다.

```dockerfile
# ✅ 좋은 예: 안정적인 레이어가 먼저, 변동성 높은 레이어가 나중
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y nodejs    # 거의 변경 안 됨
COPY package.json /app/                            # 가끔 변경
RUN npm install                                    # package.json 의존
COPY src/ /app/src/                                # 자주 변경
```

```dockerfile
# ❌ 나쁜 예: 변동성 높은 게 먼저 → 매번 캐시 미스
FROM ubuntu:22.04
COPY src/ /app/src/                                # 커밋마다 변경
RUN apt-get update && apt-get install -y nodejs    # 캐시 무효화!
COPY package.json /app/
RUN npm install
```

### 2. Multi-stage 빌드로 이미지 크기 축소

```dockerfile
FROM node:20 AS builder
COPY . /app
WORKDIR /app
RUN npm install && npm run build

FROM node:20-slim   # 더 작은 런타임 이미지
COPY --from=builder /app/dist /app
CMD ["node", "/app/server.js"]
```

**왜:** 빌드 의존성(컴파일러, 개발 라이브러리)은 builder 스테이지에 남고, 최종 이미지에는 런타임 산출물만 포함됩니다.

### 3. 더 작은 베이스 이미지 사용

| 베이스 이미지 | 대략적 크기 | 용도 |
|-------------|----------|------|
| `ubuntu:22.04` | 약 80 MB | 풀 Linux, 스크립팅 필요 시 |
| `debian:slim` | 약 30 MB | 더 작은 Debian 변형 |
| `alpine:3.19` | 약 7 MB | Go/정적 바이너리용 최소 Linux |
| `distroless` | 약 20 MB | shell 없음, 보안 중심 |

**작은 이미지 = 빠른 Pull, 낮은 공격 표면, 짧은 mount 옵션 문자열** (05_01의 4 KB 제약을 떠올려 보세요).

---

## Summary

**세 가지 기둥:**
```
Layer Sharing     → 디스크 효율  (1개 베이스, 여러 앱)
Build Cache       → 속도 효율    (변경된 것만 재빌드)
Immutability      → 보안        (SHA256 검증 기반 공급망)
```
