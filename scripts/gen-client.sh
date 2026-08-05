#!/usr/bin/env bash
#
# gen-client.sh — 喺伺服器上生成「OpenWrt 旁路由」用嘅 sing-box client config
#
# 參數直接由 /etc/sing-box/config.json 讀出（同 verify-reality.sh 同一套推導），
# 唔會抄錯 UUID／公鑰。同時落埋中國 IP/域名 rule-set 檔。
#
#   sudo bash scripts/gen-client.sh
#   sudo bash scripts/gen-client.sh --subnet 192.168.9.0/24   指定走代理嗰個網段
#   sudo bash scripts/gen-client.sh --out /tmp/router          輸出目錄
#
set -euo pipefail

CONF=/etc/sing-box/config.json
PARAMS=/etc/sing-box/params.env
OUT=/tmp/router
SUBNET=192.168.9.0/24
TUN_NAME=singbox

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subnet) SUBNET="${2:?}"; shift 2 ;;
    --out)    OUT="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "${RED}唔認得嘅參數：$1${RST}" >&2; exit 1 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "${RED}要 root：sudo bash $0${RST}" >&2; exit 1; }
[[ -f $CONF ]]    || { echo "${RED}搵唔到 $CONF${RST}" >&2; exit 1; }
command -v python3 >/dev/null || { echo "${RED}需要 python3${RST}" >&2; exit 1; }

# ── 由 config.json 抽參數 + 反推公鑰
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

# Hysteria2 參數 + 伺服器地址
read -r HY2_PORT HY2_PASS HY2_SNI <<<"$(python3 - "$CONF" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
ib = next((i for i in cfg["inbounds"] if i.get("type") == "hysteria2"), None)
print(ib["listen_port"], ib["users"][0]["password"], ib["tls"].get("server_name") or "www.bing.com") if ib else print("- - -")
PY
)"

SERVER_ADDR=""
[[ -f $PARAMS ]] && SERVER_ADDR=$(awk -F= '/^SERVER_ADDR=/{print $2}' "$PARAMS")
[[ -n "$SERVER_ADDR" ]] || SERVER_ADDR=$(curl -4fsSL --max-time 10 https://api.ipify.org 2>/dev/null || true)
[[ -n "$SERVER_ADDR" ]] || { echo "${RED}偵測唔到伺服器地址${RST}" >&2; exit 1; }

mkdir -p "$OUT"

# ── rule-set：用本地檔，唔好用 remote
#    remote + download_detour=proxy 會令「隧道未通就開唔到機」；
#    而喺內地行 direct 落 GitHub 又唔穩定。
echo "${CYA}==>${RST} 下載中國 IP／域名 rule-set …"
for f in geoip-cn geosite-cn; do
  repo=$([[ "$f" == "geoip-cn" ]] && echo sing-geoip || echo sing-geosite)
  if curl -fsSL --max-time 90 -o "$OUT/$f.srs" \
       "https://raw.githubusercontent.com/SagerNet/$repo/rule-set/$f.srs"; then
    echo "${GRN} ✔${RST} $f.srs ($(stat -c%s "$OUT/$f.srs") bytes)"
  else
    echo "${RED} ✘ $f.srs 下載失敗${RST}"; exit 1
  fi
done

FLOW_J=""; [[ "$FLOW" != "-" ]] && FLOW_J="\"flow\": \"$FLOW\","
SID_J="";  [[ "$SID"  != "-" ]] && SID_J=", \"short_id\": \"$SID\""

cat >"$OUT/config.json" <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "dns": {
    "servers": [
      { "type": "udp", "tag": "dns-remote", "server": "1.1.1.1", "detour": "proxy" },
      { "type": "udp", "tag": "dns-local",  "server": "223.5.5.5" }
    ],
    "rules": [
      { "rule_set": "geosite-cn", "server": "dns-local" }
    ],
    "final": "dns-remote",
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "$TUN_NAME",
      "address": ["172.19.0.1/30"],
      "auto_route": false,
      "stack": "system"
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "$SERVER_ADDR",
      "server_port": $PORT,
      "uuid": "$UUID", $FLOW_J
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": { "enabled": true, "public_key": "$PUB"$SID_J }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2",
      "server": "$SERVER_ADDR",
      "server_port": $HY2_PORT,
      "password": "$HY2_PASS",
      "tls": { "enabled": true, "server_name": "$HY2_SNI", "insecure": true, "alpn": ["h3"] }
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "default_domain_resolver": { "server": "dns-local" },
    "rules": [
      { "action": "sniff" },
      { "protocol": "dns", "action": "hijack-dns" },
      { "ip_is_private": true, "outbound": "direct" },
      { "rule_set": ["geoip-cn", "geosite-cn"], "outbound": "direct" }
    ],
    "rule_set": [
      { "type": "local", "tag": "geoip-cn",   "format": "binary", "path": "/etc/sing-box/geoip-cn.srs" },
      { "type": "local", "tag": "geosite-cn", "format": "binary", "path": "/etc/sing-box/geosite-cn.srs" }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  }
}
EOF

if command -v sing-box >/dev/null; then
  # 用本機路徑驗證（路由器上先會有 /etc/sing-box/*.srs）
  sed "s#/etc/sing-box/geo#$OUT/geo#g" "$OUT/config.json" >"$OUT/.check.json"
  if sing-box check -c "$OUT/.check.json" 2>"$OUT/.err"; then
    echo "${GRN} ✔${RST} config 驗證通過"
  else
    echo "${RED} ✘ config 驗證失敗${RST}"; cat "$OUT/.err"; exit 1
  fi
  rm -f "$OUT/.check.json" "$OUT/.err"
fi

cat >"$OUT/openwrt-setup.sh" <<EOF
#!/bin/sh
# 喺 OpenWrt 路由器上行（唔係喺伺服器）。
#   1. 安裝 sing-box 嘅 init 腳本（開機自啟）
#   2. 設定 policy routing：只有代理網段行 tun
#   3. 寫入 rc.local 令重開機都保持
set -e

TUN=$TUN_NAME
NET=$SUBNET
TABLE=100
SB=\$(command -v sing-box || echo /usr/bin/sing-box)

[ -x "\$SB" ] || { echo "✘ 搵唔到 sing-box，先裝咗佢"; exit 1; }
[ -f /etc/sing-box/config.json ] || { echo "✘ 搵唔到 /etc/sing-box/config.json"; exit 1; }

echo "==> 驗證 config"
"\$SB" check -c /etc/sing-box/config.json || { echo "✘ config 唔合法"; exit 1; }

echo "==> 安裝 /etc/init.d/singbox"
cat >/etc/init.d/singbox <<'INIT'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1
start_service() {
    mkdir -p /var/lib/sing-box
    procd_open_instance
    procd_set_param command /usr/bin/sing-box -D /var/lib/sing-box -C /etc/sing-box run
    procd_set_param respawn 3600 5 0
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
INIT
chmod +x /etc/init.d/singbox
/etc/init.d/singbox enable
/etc/init.d/singbox restart

echo "==> 設定 policy routing（\$NET → \$TUN）"
# 直接嵌入實際值，唔喺 singbox-route 入面再用變數（避免巢狀轉義出錯）
printf '%s\n' \
  '#!/bin/sh' \
  '# 等 tun 出現先加規則 —— sing-box 起身要幾秒' \
  'i=0' \
  'while [ \$i -lt 60 ]; do' \
  "    ip link show $TUN_NAME >/dev/null 2>&1 && break" \
  '    sleep 1; i=\$((i+1))' \
  'done' \
  "if ! ip link show $TUN_NAME >/dev/null 2>&1; then" \
  "    logger -t singbox-route '$TUN_NAME 冇出現，放棄'; exit 1" \
  'fi' \
  "ip route replace default dev $TUN_NAME table 100" \
  "ip rule del from $SUBNET lookup 100 2>/dev/null" \
  "ip rule add from $SUBNET lookup 100" \
  "logger -t singbox-route '已設定 $SUBNET -> $TUN_NAME (table 100)'" \
  >/usr/bin/singbox-route
chmod +x /usr/bin/singbox-route
/usr/bin/singbox-route

echo "==> 寫入 rc.local（重開機保持）"
if ! grep -q singbox-route /etc/rc.local 2>/dev/null; then
    sed -i '/^exit 0/i (/usr/bin/singbox-route \&)' /etc/rc.local
fi

echo
echo "✔ 完成"
ip rule show | grep "$SUBNET" || echo "⚠ 搵唔到 ip rule，睇下 logread -e singbox"
EOF
chmod +x "$OUT/openwrt-setup.sh"

echo
echo "${BLD}生成完成 → $OUT${RST}"
echo "────────────────────────────────────────"
ls -1 "$OUT" | sed 's/^/  /'
echo "────────────────────────────────────────"
echo "  伺服器   : $SERVER_ADDR"
echo "  代理網段 : $SUBNET"
echo "  TUN 名   : $TUN_NAME"
echo
echo "${BLD}下一步：將呢三個檔 copy 落路由器${RST}"
echo "  ${CYA}scp $OUT/config.json $OUT/geoip-cn.srs $OUT/geosite-cn.srs root@路由器IP:/etc/sing-box/${RST}"
echo
echo "詳細步驟見 ${CYA}docs/router.md${RST}"
echo "${YEL} ⚠ config.json 入面有你嘅憑證，唔好公開。${RST}"
