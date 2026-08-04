#!/usr/bin/env bash
#
# selftest.sh — 喺伺服器自己身上經 REALITY 隧道行一次真實請求（loopback 測試）
#
# 用嚟斬斷變數：
#   通到  → 伺服器 100% 正常，問題喺網絡路徑或者客戶端
#   通唔到 → 伺服器本身有問題，唔使再喺客戶端度浪費時間
#
#   sudo bash scripts/selftest.sh
#
set -uo pipefail

CONF=/etc/sing-box/config.json
TMP=$(mktemp -d)
SOCKS_PORT=11080
DEBUG=0
[[ "${1:-}" == "--debug" ]] && DEBUG=1

restore_log() {
  [[ ${LEVEL_CHANGED:-0} -eq 1 ]] || return 0
  sed -i "s/\"level\": \"debug\"/\"level\": \"$OLD_LEVEL\"/" "$CONF"
  systemctl restart sing-box 2>/dev/null || true
}
trap 'kill ${CPID:-0} 2>/dev/null; restore_log; rm -rf "$TMP"' EXIT

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'

[[ $EUID -eq 0 ]] || { echo "${RED}要 root：sudo bash $0${RST}" >&2; exit 1; }
[[ -f $CONF ]]    || { echo "${RED}搵唔到 $CONF${RST}" >&2; exit 1; }
SB=$(command -v sing-box || echo /usr/local/bin/sing-box)
[[ -x $SB ]]      || { echo "${RED}搵唔到 sing-box${RST}" >&2; exit 1; }

echo "${BLD}REALITY loopback 自測${RST}"
echo

# ── 環境快照：呢啲直接決定 REALITY 握手成唔成
echo "${CYA}── 伺服器環境${RST}"
DNSBLK=$(python3 -c 'import json,sys;c=json.load(open(sys.argv[1]));print(json.dumps(c.get("dns","（冇 dns 設定）"),ensure_ascii=False))' "$CONF" 2>/dev/null)
echo "  dns 設定 : $DNSBLK"
HS=$(python3 -c 'import json,sys
c=json.load(open(sys.argv[1]))
i=next(x for x in c["inbounds"] if x.get("type")=="vless")
h=i["tls"]["reality"]["handshake"]
print(h["server"], h["server_port"])' "$CONF" 2>/dev/null)
HS_HOST=${HS%% *}; HS_PORT=${HS##* }
echo "  握手目標 : ${HS_HOST}:${HS_PORT}"
printf "  IPv4 撥號: "; if curl -4 -sI --max-time 8 "https://${HS_HOST}" -o /dev/null 2>/dev/null; then
  echo "${GRN}通${RST}"; else echo "${RED}唔通${RST}  ← REALITY 一定死"; fi
printf "  IPv6 撥號: "; if curl -6 -sI --max-time 8 "https://${HS_HOST}" -o /dev/null 2>/dev/null; then
  echo "${GRN}通${RST}"; else echo "${YEL}唔通（Oracle 預設冇 IPv6，正常）${RST}"; fi
echo

# ── --debug：臨時將伺服器 log 調到 debug
if [[ $DEBUG -eq 1 ]]; then
  OLD_LEVEL=$(python3 -c "import json;print(json.load(open('$CONF')).get('log',{}).get('level','warn'))" 2>/dev/null || echo warn)
  if [[ "$OLD_LEVEL" != "debug" ]]; then
    sed -i "s/\"level\": \"$OLD_LEVEL\"/\"level\": \"debug\"/" "$CONF"
    LEVEL_CHANGED=1
    systemctl restart sing-box
    sleep 2
    echo "${CYA}已臨時將伺服器 log 調到 debug（測完自動復原）${RST}"
    echo
  fi
fi
SINCE=$(date '+%Y-%m-%d %H:%M:%S')

# ── 由 config.json 抽出真實參數（同 verify-reality.sh 同一套推導）
read -r UUID FLOW SNI SID PORT PUB <<<"$(python3 - "$CONF" <<'PY'
import base64, json, sys
P, A24 = 2**255 - 19, 121665
def cswap(s, a, b):
    d = (s * ((a - b) % P)) % P
    return (a - d) % P, (b + d) % P
def mult(k, u):
    x1, x2, z2, x3, z3, sw = u, 1, 0, u, 1, 0
    for t in range(254, -1, -1):
        kt = (k >> t) & 1; sw ^= kt
        x2, x3 = cswap(sw, x2, x3); z2, z3 = cswap(sw, z2, z3); sw = kt
        A = (x2 + z2) % P; AA = A * A % P
        B = (x2 - z2) % P; BB = B * B % P
        E = (AA - BB) % P
        C = (x3 + z3) % P; D = (x3 - z3) % P
        DA = D * A % P; CB = C * B % P
        x3 = pow(DA + CB, 2, P); z3 = x1 * pow(DA - CB, 2, P) % P
        x2 = AA * BB % P; z2 = E * (AA + A24 * E) % P
    x2, x3 = cswap(sw, x2, x3); z2, z3 = cswap(sw, z2, z3)
    return x2 * pow(z2, P - 2, P) % P
b64d = lambda s: base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
b64e = lambda b: base64.urlsafe_b64encode(b).decode().rstrip("=")
def pub(priv):
    b = bytearray(b64d(priv)); b[0] &= 248; b[31] &= 127; b[31] |= 64
    return b64e(mult(int.from_bytes(b, "little"), 9).to_bytes(32, "little"))
cfg = json.load(open(sys.argv[1]))
ib = next(i for i in cfg["inbounds"] if i.get("type") == "vless")
r = ib["tls"]["reality"]
print(ib["users"][0]["uuid"], ib["users"][0].get("flow", "") or "-",
      ib["tls"]["server_name"], (r.get("short_id") or [""])[0] or "-",
      ib["listen_port"], pub(r["private_key"]))
PY
)"

[[ -n "${UUID:-}" ]] || { echo "${RED}✘ 讀唔到 config.json 嘅 REALITY 參數${RST}"; exit 1; }
echo "  目標：127.0.0.1:${PORT}   SNI：${SNI}"
echo

# ── 砌一份對應嘅 client config
FLOW_J=""; [[ "$FLOW" != "-" ]] && FLOW_J="\"flow\": \"$FLOW\","
SID_J="";  [[ "$SID"  != "-" ]] && SID_J=", \"short_id\": \"$SID\""
cat >"$TMP/client.json" <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    { "type": "socks", "tag": "in", "listen": "127.0.0.1", "listen_port": $SOCKS_PORT }
  ],
  "outbounds": [
    {
      "type": "vless", "tag": "out",
      "server": "127.0.0.1", "server_port": $PORT,
      "uuid": "$UUID", $FLOW_J
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": { "enabled": true, "public_key": "$PUB"$SID_J }
      }
    }
  ]
}
EOF

if ! "$SB" check -c "$TMP/client.json" 2>"$TMP/err"; then
  echo "${RED}✘ 測試用 client config 唔合法${RST}"; cat "$TMP/err"; exit 1
fi

"$SB" run -c "$TMP/client.json" >"$TMP/client.log" 2>&1 &
CPID=$!

for _ in $(seq 1 50); do
  ss -tln 2>/dev/null | grep -q ":$SOCKS_PORT" && break
  sleep 0.2
done
if ! kill -0 $CPID 2>/dev/null; then
  echo "${RED}✘ 測試客戶端起唔到${RST}"; cat "$TMP/client.log"; exit 1
fi

# ── 經隧道行真實請求
echo "${CYA}經 REALITY 隧道發請求 …${RST}"
OK=0
# 每個 URL 配一個內容檢查 —— 唔可以淨係睇 curl exit code，
# 因為中途嘅攔截 proxy 會回一版錯誤頁但 exit 0。
for pair in \
  'https://api.ipify.org|^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
  'https://www.cloudflare.com/cdn-cgi/trace|^ip=' \
  'https://ifconfig.me/ip|^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
do
  url="${pair%%|*}"; want="${pair#*|}"
  body=$(curl -s --max-time 15 --socks5-hostname 127.0.0.1:$SOCKS_PORT "$url" 2>&1)
  code=$?
  if [[ $code -ne 0 ]]; then
    echo "${YEL} · $url — curl exit $code，試下一個${RST}"
  elif grep -qE "$want" <<<"$body"; then
    echo "${GRN} ✔ 隧道通${RST}  ($url)"
    echo "$body" | head -3 | sed 's/^/     /'
    OK=1; break
  else
    echo "${YEL} · $url — 有回應但內容唔啱（可能俾中途 proxy 攔咗）：${RST}"
    echo "$body" | head -2 | sed 's/^/     /'
  fi
done

echo
if [[ $OK -eq 1 ]]; then
  echo "${GRN}${BLD}══ 伺服器 100% 正常 ══${RST}"
  echo "REALITY 握手、認證、出站全部work。問題唔喺伺服器，喺以下其中一樣："
  echo "  1. ${BLD}客戶端系統時間唔準${RST} — REALITY 對時間敏感，差幾分鐘就認證失敗"
  echo "     Windows：設定 → 時間與語言 → 立即同步"
  echo "  2. 客戶端撳緊舊節點 — 刪曬所有節點再重新匯入"
  echo "  3. v2rayN 核心係 v2fly 而唔係 Xray — v2fly 唔支援 REALITY"
  echo "  4. 中途網絡干擾 — 試下 Hysteria2 節點（走 UDP，完全唔同機制）"
elif grep -q 'ERROR' "$TMP/client.log" || ! grep -q 'outbound/vless' "$TMP/client.log"; then
  echo "${RED}${BLD}══ REALITY 握手失敗（伺服器側）══${RST}"
  echo "連自己都連唔到自己 —— 唔使再喺客戶端或者網絡度搞。"
  echo
  echo "${BLD}伺服器側 log（呢個先係關鍵）：${RST}"
  echo "────────────────────────────────────────"
  journalctl -u sing-box --since "$SINCE" --no-pager 2>/dev/null | tail -40 | sed 's/^/  /'
  echo "────────────────────────────────────────"
  [[ $DEBUG -eq 0 ]] && echo "${YEL}想睇更detail：${CYA}sudo bash $0 --debug${RST}"
else
  echo "${YEL}${BLD}══ 隧道通到，但伺服器出唔到外網 ══${RST}"
  echo "log 見到 ${BLD}outbound/vless${RST} 成功建立，即係 REALITY 握手同認證${GRN}冇問題${RST}；"
  echo "失敗喺最後一步 —— 伺服器連唔到目標網站。查："
  echo "  1. 伺服器 DNS：${CYA}getent hosts api.ipify.org${RST}"
  echo "  2. 伺服器出站：${CYA}curl -sI https://api.ipify.org${RST}"
  echo "  3. 供應商嘅 ${BLD}egress${RST} 規則（Oracle Security List 預設全開，但自訂過就要查）"
  echo "────────────────────────────────────────"
  tail -20 "$TMP/client.log" | sed 's/^/  /'
fi
