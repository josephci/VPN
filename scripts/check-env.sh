#!/usr/bin/env bash
#
# check-env.sh — 部署前後嘅環境自檢
#
#   bash scripts/check-env.sh            喺伺服器上行（自檢）
#   bash scripts/check-env.sh 1.2.3.4    喺客戶端行（由外面探測伺服器）
#
set -uo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'
pass() { echo "${GRN} ✔${RST} $*"; }
fail() { echo "${RED} ✘${RST} $*"; }
warn() { echo "${YEL} ⚠${RST} $*"; }
head_() { echo; echo "${BLD}${CYA}── $* ${RST}"; }

REMOTE="${1:-}"

# ══════════════════════════════════════════════ 客戶端模式：由外面探測
if [[ -n "$REMOTE" ]]; then
  echo "${BLD}由外部探測 ${REMOTE}${RST}"
  echo "（喺澳門／香港行呢個，唔好喺伺服器自己身上行）"

  head_ "TCP 443 — VLESS-REALITY"
  if command -v nc >/dev/null && nc -z -w5 "$REMOTE" 443 2>/dev/null; then
    pass "443/tcp 通"
  elif timeout 5 bash -c "echo >/dev/tcp/$REMOTE/443" 2>/dev/null; then
    pass "443/tcp 通"
  else
    fail "443/tcp 唔通"
    echo "    → 查 Oracle VCN Security List 有冇加 TCP 443 ingress"
    echo "    → 查伺服器：sudo ss -tlnp | grep 443"
    echo "    → 查伺服器：sudo iptables -L INPUT -n --line-numbers | head"
  fi

  head_ "TLS 握手 — REALITY 偽裝檢查"
  if command -v openssl >/dev/null; then
    cn=$(timeout 8 openssl s_client -connect "${REMOTE}:443" \
          -servername www.apple.com </dev/null 2>/dev/null \
          | openssl x509 -noout -subject 2>/dev/null || true)
    if [[ -n "$cn" ]]; then
      pass "握手成功，憑證主體：${cn#subject=}"
      echo "    （見到偽裝目標嘅憑證就啱曬 — 呢個就係 REALITY 借憑證嘅效果）"
    else
      fail "TLS 握手失敗 — 端口通但 sing-box 可能未行"
    fi
  else
    warn "冇 openssl，跳過"
  fi

  head_ "UDP 8443 — Hysteria2"
  warn "UDP 冇得簡單探測，直接用客戶端試連最準"

  head_ "延遲"
  if command -v ping >/dev/null; then
    ping -c 4 -W 2 "$REMOTE" 2>/dev/null | tail -2 || warn "ICMP 俾人擋咗（正常，Oracle 預設封 ping）"
  fi
  echo
  exit 0
fi

# ══════════════════════════════════════════════ 伺服器模式：自檢
echo "${BLD}伺服器自檢${RST}"

IS_ROOT=0
[[ $EUID -eq 0 ]] && IS_ROOT=1
if [[ $IS_ROOT -eq 0 ]]; then
  echo
  echo "${YEL}${BLD} ⚠ 冇 root 權限 —— config 同防火牆呢兩項檢查會跳過。${RST}"
  echo "${YEL}   （config.json 係 600 root-only、iptables 亦要 root，唔加 sudo 會report假失敗）${RST}"
  echo "${YEL}   完整檢查請行：${CYA}sudo bash $0${RST}"
fi

head_ "系統"
echo "  $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -s)"
echo "  架構：$(uname -m)    核心：$(uname -r)"
echo "  記憶體：$(free -h 2>/dev/null | awk '/^Mem:/{print $2" 總共，"$7" 可用"}')"

head_ "公網 IP"
v4=$(curl -4fsSL --max-time 8 https://api.ipify.org 2>/dev/null || true)
v6=$(curl -6fsSL --max-time 8 https://api64.ipify.org 2>/dev/null || true)
[[ -n "$v4" ]] && pass "IPv4：$v4" || fail "冇 IPv4 出口"
[[ -n "$v6" ]] && pass "IPv6：$v6" || warn "冇 IPv6（唔影響）"

head_ "sing-box"
if command -v sing-box >/dev/null || [[ -x /usr/local/bin/sing-box ]]; then
  sb=$(command -v sing-box || echo /usr/local/bin/sing-box)
  pass "$($sb version | head -1)"
  if [[ ! -f /etc/sing-box/config.json ]]; then
    warn "未有 config.json — 行 deploy.sh"
  elif [[ ! -r /etc/sing-box/config.json ]]; then
    warn "config.json 讀唔到（600 root-only）— 跳過驗證，請用 sudo 重跑"
  else
    err=$($sb check -c /etc/sing-box/config.json 2>&1) \
      && pass "config.json 驗證通過" \
      || { fail "config.json 驗證失敗"; echo "    $err"; }
  fi
  if systemctl is-active --quiet sing-box 2>/dev/null; then
    pass "systemd service running（已跑 $(systemctl show -p ActiveEnterTimestamp --value sing-box 2>/dev/null | cut -d' ' -f2-3)）"
  else
    fail "systemd service 未行 → sudo systemctl status sing-box"
  fi
else
  warn "未裝 sing-box — 行 deploy.sh"
fi

head_ "端口監聽"
if command -v ss >/dev/null; then
  t=$(ss -tlnp 2>/dev/null | grep -c ':443 ' || true)
  u=$(ss -ulnp 2>/dev/null | grep -c ':8443 ' || true)
  [[ "$t" -gt 0 ]] && pass "443/tcp 有嘢聽住" || fail "443/tcp 冇嘢聽 — sing-box 未行？"
  [[ "$u" -gt 0 ]] && pass "8443/udp 有嘢聽住" || fail "8443/udp 冇嘢聽"
else
  warn "冇 ss，跳過"
fi

head_ "本機防火牆 (iptables)"
if [[ $IS_ROOT -eq 0 ]]; then
  warn "要 root 先查到 — 跳過。用 ${CYA}sudo bash $0${RST}${YEL} 重跑${RST}"
elif command -v iptables >/dev/null; then
  iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null \
    && pass "443/tcp 已放行" || fail "443/tcp 未放行 — 行 deploy.sh 會自動加"
  iptables -C INPUT -p udp --dport 8443 -j ACCEPT 2>/dev/null \
    && pass "8443/udp 已放行" || fail "8443/udp 未放行"
  if iptables -S INPUT 2>/dev/null | grep -qE 'REJECT|DROP'; then
    warn "INPUT 鏈有 REJECT/DROP（Oracle image 預設有）— 確認 ACCEPT 規則排喺佢前面："
    echo "    sudo iptables -L INPUT -n --line-numbers | head -12"
  fi
else
  warn "冇 iptables"
fi

head_ "雲端防火牆"
warn "呢層喺機入面檢查唔到 — 要自己入供應商控制台確認"
echo "    Oracle：Networking → VCN → Subnet → Security List → Ingress Rules"
echo "    Vultr ：Products → Firewall（冇綁 Firewall Group 就唔使理）"
echo "    需要：TCP 443（Source 0.0.0.0/0）+ UDP 8443（Source 0.0.0.0/0）"

head_ "BBR"
cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
[[ "$cc" == "bbr" ]] && pass "擁塞控制：bbr" || warn "擁塞控制：$cc（唔係 bbr，跨境速度會差啲）"

echo
echo "${BLD}最後一步：喺澳門／香港（唔好喺呢部機）行${RST}"
echo "  ${CYA}bash scripts/check-env.sh ${v4:-你嘅IP}${RST}"
echo
