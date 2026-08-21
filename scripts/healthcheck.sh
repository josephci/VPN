#!/usr/bin/env bash
#
# healthcheck.sh — 定期自動健康檢查（可以自我修復）
#
# 同 selftest.sh 嘅分別：selftest 係你手動診斷用；呢個係俾 systemd timer
# 定期跑，靜靜哋監察，有事先出聲，而且會試自動重啟。
#
#   sudo bash scripts/healthcheck.sh              跑一次，印報告
#   sudo bash scripts/healthcheck.sh --quiet      只喺有問題先出聲（timer 用）
#   sudo bash scripts/healthcheck.sh --install    裝 systemd timer（每 10 分鐘）
#   sudo bash scripts/healthcheck.sh --uninstall  移除 timer
#   sudo bash scripts/healthcheck.sh --status     睇最近嘅檢查結果
#
set -uo pipefail

CONF=/etc/sing-box/config.json
STATE=/var/lib/sing-box/health.state
SOCKS_PORT=11081
MODE=report

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'

case "${1:-}" in
  --quiet)     MODE=quiet ;;
  --install)   MODE=install ;;
  --uninstall) MODE=uninstall ;;
  --status)    MODE=status ;;
  "")          ;;
  *) echo "${RED}唔認得嘅參數：$1${RST}" >&2; sed -n '2,13p' "$0"; exit 1 ;;
esac

# ── --status：唔使 root，淨係讀狀態
if [[ $MODE == status ]]; then
  if [[ -r $STATE ]]; then
    echo "${BLD}最近一次健康檢查${RST}"
    cat "$STATE"
  else
    echo "${YEL}未有紀錄（未跑過，或者要 sudo 先讀到）${RST}"
  fi
  echo
  systemctl list-timers singbox-health.timer --no-pager 2>/dev/null | head -3
  exit 0
fi

[[ $EUID -eq 0 ]] || { echo "${RED}要 root：sudo bash $0 ${1:-}${RST}" >&2; exit 1; }

# ── --install / --uninstall
if [[ $MODE == install ]]; then
  # 複製去 /usr/local/bin —— 唔好指住 repo，repo 刪咗 timer 就爛
  install -m 755 "$(readlink -f "$0")" /usr/local/bin/singbox-health
  cat >/etc/systemd/system/singbox-health.service <<'EOF'
[Unit]
Description=sing-box health check
After=sing-box.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/singbox-health --quiet
EOF
  cat >/etc/systemd/system/singbox-health.timer <<'EOF'
[Unit]
Description=Run sing-box health check periodically

[Timer]
OnBootSec=5min
OnUnitActiveSec=10min
RandomizedDelaySec=2min

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now singbox-health.timer
  echo "${GRN} ✔${RST} 已安裝，每 10 分鐘自動檢查一次"
  echo "   睇結果：${CYA}sudo singbox-health --status${RST}"
  echo "   睇歷史：${CYA}journalctl -t singbox-health --since today${RST}"
  exit 0
fi

if [[ $MODE == uninstall ]]; then
  systemctl disable --now singbox-health.timer 2>/dev/null || true
  rm -f /etc/systemd/system/singbox-health.{service,timer} /usr/local/bin/singbox-health
  systemctl daemon-reload
  echo "${GRN} ✔${RST} 已移除"
  exit 0
fi

# ══════════════════════════════════════════════ 實際檢查
FAILS=()
NOTES=()
say()  { [[ $MODE == quiet ]] || echo "$@"; }
ok()   { say "${GRN} ✔${RST} $1"; }
bad()  { say "${RED} ✘${RST} $1"; FAILS+=("$1"); }
note() { say "${YEL} ⚠${RST} $1"; NOTES+=("$1"); }

SB=$(command -v sing-box || echo /usr/local/bin/sing-box)

# 1. 服務
if systemctl is-active --quiet sing-box 2>/dev/null; then
  ok "服務運行中"
else
  bad "服務未運行"
fi

# 2. config
if [[ -f $CONF ]] && "$SB" check -c "$CONF" >/dev/null 2>&1; then
  ok "config 合法"
else
  bad "config 唔合法或者搵唔到"
fi

# 3. 端口
read -r RPORT HPORT <<<"$(python3 -c '
import json,sys
c=json.load(open(sys.argv[1]))
v=next((i for i in c["inbounds"] if i.get("type")=="vless"),None)
h=next((i for i in c["inbounds"] if i.get("type")=="hysteria2"),None)
print(v["listen_port"] if v else 0, h["listen_port"] if h else 0)' "$CONF" 2>/dev/null || echo "443 8443")"

if ss -tln 2>/dev/null | grep -q ":${RPORT} "; then ok "${RPORT}/tcp 聽緊"; else bad "${RPORT}/tcp 冇聽"; fi
if ss -uln 2>/dev/null | grep -q ":${HPORT} "; then ok "${HPORT}/udp 聽緊"; else bad "${HPORT}/udp 冇聽"; fi

# 4. REALITY 握手目標 —— 撥唔通就成個 REALITY 死
HS=$(python3 -c '
import json,sys
c=json.load(open(sys.argv[1]))
i=next(x for x in c["inbounds"] if x.get("type")=="vless")
print(i["tls"]["reality"]["handshake"]["server"])' "$CONF" 2>/dev/null || echo "")
if [[ -n "$HS" ]]; then
  if curl -4 -sI --max-time 10 "https://${HS}" -o /dev/null 2>/dev/null; then
    ok "握手目標 ${HS} 撥得通"
  else
    bad "握手目標 ${HS} 撥唔通 — REALITY 會全面失敗"
  fi
fi

# 5. 真隧道測試（決定性）
tunnel_test() {
  local tmp; tmp=$(mktemp -d)
  local uuid flow sni sid pub
  read -r uuid flow sni sid pub <<<"$(python3 - "$CONF" <<'PY'
import base64, json, sys
P, A24 = 2**255 - 19, 121665
def cswap(s,a,b):
    d=(s*((a-b)%P))%P
    return (a-d)%P,(b+d)%P
def mult(k,u):
    x1,x2,z2,x3,z3,sw=u,1,0,u,1,0
    for t in range(254,-1,-1):
        kt=(k>>t)&1; sw^=kt
        x2,x3=cswap(sw,x2,x3); z2,z3=cswap(sw,z2,z3); sw=kt
        A=(x2+z2)%P; AA=A*A%P
        B=(x2-z2)%P; BB=B*B%P
        E=(AA-BB)%P
        C=(x3+z3)%P; D=(x3-z3)%P
        DA=D*A%P; CB=C*B%P
        x3=pow(DA+CB,2,P); z3=x1*pow(DA-CB,2,P)%P
        x2=AA*BB%P; z2=E*(AA+A24*E)%P
    x2,x3=cswap(sw,x2,x3); z2,z3=cswap(sw,z2,z3)
    return x2*pow(z2,P-2,P)%P
b64d=lambda s: base64.urlsafe_b64decode(s+"="*(-len(s)%4))
b64e=lambda b: base64.urlsafe_b64encode(b).decode().rstrip("=")
def pub(p):
    b=bytearray(b64d(p)); b[0]&=248; b[31]&=127; b[31]|=64
    return b64e(mult(int.from_bytes(b,"little"),9).to_bytes(32,"little"))
c=json.load(open(sys.argv[1]))
i=next(x for x in c["inbounds"] if x.get("type")=="vless")
r=i["tls"]["reality"]
print(i["users"][0]["uuid"], i["users"][0].get("flow","") or "-",
      i["tls"]["server_name"], (r.get("short_id") or [""])[0] or "-",
      pub(r["private_key"]))
PY
)"
  local fj="" sj=""
  [[ "$flow" != "-" ]] && fj="\"flow\": \"$flow\","
  [[ "$sid"  != "-" ]] && sj=", \"short_id\": \"$sid\""
  cat >"$tmp/c.json" <<EOF
{
  "log": { "level": "error" },
  "inbounds": [ { "type": "socks", "tag": "in", "listen": "127.0.0.1", "listen_port": $SOCKS_PORT } ],
  "outbounds": [
    { "type": "vless", "tag": "out", "server": "127.0.0.1", "server_port": $RPORT,
      "uuid": "$uuid", $fj
      "tls": { "enabled": true, "server_name": "$sni",
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": { "enabled": true, "public_key": "$pub"$sj } } }
  ]
}
EOF
  "$SB" run -c "$tmp/c.json" >"$tmp/log" 2>&1 &
  local pid=$!
  local i=0
  while [[ $i -lt 40 ]]; do
    ss -tln 2>/dev/null | grep -q ":$SOCKS_PORT " && break
    sleep 0.25; i=$((i+1))
  done
  local rc=1 body
  for pair in 'https://api.ipify.org|^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
              'https://www.cloudflare.com/cdn-cgi/trace|^ip=' \
              'https://ifconfig.me/ip|^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; do
    body=$(curl -s --max-time 12 --socks5-hostname "127.0.0.1:$SOCKS_PORT" "${pair%%|*}" 2>/dev/null)
    if [[ -n "$body" ]] && grep -qE "${pair#*|}" <<<"$body"; then rc=0; break; fi
  done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  rm -rf "$tmp"
  return $rc
}

if tunnel_test; then
  ok "隧道實測通過"
else
  bad "隧道實測失敗 — 客戶端連唔到"
fi

# 6. 資源
DISK=$(df -P / | awk 'NR==2{print $5}' | tr -d '%')
[[ "$DISK" -lt 90 ]] && ok "磁碟 ${DISK}%" || note "磁碟 ${DISK}% — 快滿"
MEMFREE=$(free -m | awk '/^Mem:/{print int($7*100/$2)}')
[[ "$MEMFREE" -gt 10 ]] && ok "記憶體可用 ${MEMFREE}%" || note "記憶體可用 ${MEMFREE}% — 偏低"

# ══════════════════════════════════════════════ 自我修復
HEALED=""
if [[ ${#FAILS[@]} -gt 0 ]]; then
  logger -t singbox-health "unhealthy: ${FAILS[*]}"
  say
  say "${YEL}試自動重啟 sing-box …${RST}"
  systemctl restart sing-box 2>/dev/null
  sleep 5
  if systemctl is-active --quiet sing-box && tunnel_test; then
    HEALED="重啟後恢復正常"
    logger -t singbox-health "recovered after restart"
    say "${GRN} ✔ ${HEALED}${RST}"
    FAILS=()
  else
    logger -t singbox-health "still unhealthy after restart"
    say "${RED} ✘ 重啟後仍然有問題${RST}"
  fi
fi

# ── 寫狀態檔
mkdir -p "$(dirname "$STATE")"
{
  echo "時間     : $(date '+%F %T %Z')"
  if [[ ${#FAILS[@]} -eq 0 ]]; then
    echo "狀態     : OK${HEALED:+（$HEALED）}"
  else
    echo "狀態     : FAIL"
    printf '問題     : %s\n' "${FAILS[@]}"
  fi
  [[ ${#NOTES[@]} -gt 0 ]] && printf '注意     : %s\n' "${NOTES[@]}"
} >"$STATE"

# ── 總結
if [[ ${#FAILS[@]} -eq 0 ]]; then
  say
  say "${GRN}${BLD}══ 一切正常 ══${RST}"
  [[ $MODE == quiet ]] && exit 0
  echo
  echo "${CYA}⚠ 呢個檢查證明唔到「內地連唔連得到」${RST} —— 佢喺伺服器上面跑，"
  echo "  測唔到 GFW 有冇封你個 IP。嗰樣要用 ${BLD}itdog.cn${RST} 由內地節點測。"
  exit 0
else
  echo "${RED}${BLD}══ 有問題 ══${RST}" >&2
  printf '  ✘ %s\n' "${FAILS[@]}" >&2
  echo "  詳細診斷：sudo bash $(dirname "$0")/selftest.sh --debug" >&2
  exit 1
fi
