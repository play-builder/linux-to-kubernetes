# 1단계: 빌드 스테이지 (Node 22 LTS 기반)
FROM node:22-slim AS builder
WORKDIR /app
# corepack 활성화 및 pnpm 버전 고정 (재현성 — latest 금지)
RUN corepack enable && corepack prepare pnpm@11.9.0 --activate
# package.json과 pnpm-lock.yaml(있을 경우) 복사
COPY package.json pnpm-lock.yaml* ./
# pnpm으로 프로덕션 의존성만 설치
RUN pnpm install --prod
# 의존성이 0개라도 COPY 에러가 나지 않도록 빈 폴더 보장
RUN mkdir -p /app/node_modules

# 2단계: distroless 런타임 (Node 22 호환 버전으로 일치)
FROM gcr.io/distroless/nodejs22-debian12
WORKDIR /app
# builder에서 보장된 node_modules 폴더 복사
COPY --from=builder /app/node_modules ./node_modules
COPY app.js ./
USER nonroot:nonroot
EXPOSE 8080
CMD ["app.js"]
