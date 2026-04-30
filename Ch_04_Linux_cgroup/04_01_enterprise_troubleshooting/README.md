# 04-01: Enterprise Troubleshooting

## Step-01: Introduction

Endowus(싱가포르 핀테크 기업)의 6개월간의 OOMKilled 추적 사례를 통해 **우리가 왜 cgroup을 깊이 알아야 하는지** 그 필요성을 확인한다.
* [Endowus Tech Blog: OOMKilled 사례 보기](https://tech.endowus.com/oomkilled/)

이 사례를 바탕으로, 본 챕터에서 답을 찾아갈 5가지 핵심 질문을 제시한다.

---

## Step-02: Five Questions This Chapter Answers

| Q | 핵심 질문 |
|---|---|
| Q1 | Pod는 왜 계속 `OOMKilled` 상태로 재시작하는가? |
| Q2 | `Exit Code 137`은 정확히 어디서 비롯된 숫자인가? |
| Q3 | CPU 사용률이 낮은데도 Pod가 느려지는(Throttling) 이유는 무엇인가? |
| Q4 | 같은 노드에서 메모리 압박(OOM)이 발생하면 어떤 Pod가 먼저 종료되는가? |
| Q5 | K8s의 `requests`와 `limits`는 리눅스 커널 레벨에서 어떻게 변환되는가? |
