#!/bin/bash
# ============================================================
# Lab 05: K8s 필수 커널 모듈 로드 검증
# ============================================================
set -e

C_TITLE="\033[1;34m"  C_SEC="\033[1;36m"  C_OK="\033[1;32m"
C_WARN="\033[1;33m"   C_ERR="\033[1;31m"  C_CMD="\033[0;37m"
C_RESET="\033[0m"

echo ""
echo -e "${C_TITLE}═══════════════════════════════════════════════════${C_RESET}"
echo -e "${C_TITLE}  Lab 05: K8s 필수 커널 모듈 로드 검증${C_RESET}"
echo -e "${C_TITLE}═══════════════════════════════════════════════════${C_RESET}"
echo ""
echo -e "${C_WARN}  📘 K8s 노드에 반드시 필요한 두 모듈:${C_RESET}"
echo -e "${C_WARN}     overlay      → 컨테이너 이미지 레이어 합성${C_RESET}"
echo -e "${C_WARN}     br_netfilter → 브릿지 트래픽 iptables 연동${C_RESET}"
echo ""

# ── 1. modprobe로 모듈 로드 ──────────────────────────────────
echo -e "${C_SEC}[1] modprobe로 K8s 필수 모듈 로드${C_RESET}"
echo ""
for mod in overlay br_netfilter; do
    if lsmod | grep -q "^$mod"; then
        echo -e "  ${C_OK}✅ $mod 이미 로드됨${C_RESET}"
    else
        echo -e "  ${C_WARN}→ modprobe $mod 실행${C_RESET}"
        modprobe $mod
        echo -e "  ${C_OK}✅ $mod 로드 완료${C_RESET}"
    fi
done
echo ""

# ── 2. lsmod로 참조 수 및 의존성 확인 ──────────────────────
echo -e "${C_SEC}[2] lsmod 확인 — Module Size, Used by, 의존성${C_RESET}"
echo ""
echo -e "  ${C_WARN}📘 컬럼: Module / Size / Used by (참조 횟수)${C_RESET}"
echo ""
lsmod | head -1
lsmod | grep -E "^(overlay|br_netfilter)"
echo ""
echo -e "  ${C_CMD}Used by 숫자 > 0 → 다른 모듈/프로세스가 사용 중${C_RESET}"
echo ""

# ── 3. 재부팅 후 자동 로드 설정 ──────────────────────────────
echo -e "${C_SEC}[3] /etc/modules-load.d/k8s.conf — 재부팅 후 자동 로드${C_RESET}"
echo ""
if [ -f /etc/modules-load.d/k8s.conf ]; then
    echo -e "  ${C_OK}✅ 설정 파일 존재:${C_RESET}"
    cat /etc/modules-load.d/k8s.conf | sed 's/^/    /'
    echo ""
    echo -e "  ${C_OK}→ 재부팅 후에도 자동 로드됨 ✅${C_RESET}"
else
    echo -e "  ${C_ERR}⚠️ /etc/modules-load.d/k8s.conf 없음 → 재부팅 시 모듈 사라짐${C_RESET}"
fi
echo ""

# ── 4. modinfo로 모듈 상세 정보 ──────────────────────────────
echo -e "${C_SEC}[4] modinfo overlay — 모듈 상세 정보${C_RESET}"
echo ""
modinfo overlay | grep -E "^(filename|description|license|depends)" | head -5
echo ""

echo -e "${C_TITLE}═══════════════════════════════════════════════════${C_RESET}"
echo -e "${C_OK}  Lab 05 완료 ✅${C_RESET}"
echo -e "${C_TITLE}═══════════════════════════════════════════════════${C_RESET}"
