#!/usr/bin/env bash
#
# deploy.sh — 一鍵部署 sing-box (VLESS-REALITY + Hysteria2)
#
# 適用於任何 Debian / Ubuntu 機（Oracle Cloud Always Free、RackNerd VPS 等）
# 支援 x86_64 / aarch64 / armv7
#
#   sudo bash scripts/deploy.sh                     全新部署
#   sudo bash scripts/deploy.sh --update            只更新 sing-box，保留現有金鑰
#   sudo bash scripts/deploy.sh --address 1.2.3.4   指定連結入面用嘅地址
#   sudo bash scripts/deploy.sh --keepalive         加裝閒置保活（防甲骨文回收）
#
set -euo pipefail

CONF_DIR=/etc/sing-box
CONF=$CONF_DIR/config.json
PARAMS=$CONF_DIR/params.env
FALLBACK_VERSION=1.12.0          # GitHub API 攞唔到版本時用呢個

REALITY_PORT=443
HY2_PORT=8443
REALITY_SNI=www.apple.com        # REALITY 借用嘅真實網站
                                 # 唔好用 www.microsoft.com —— 佢喺 Akamai 上，
                                 # 部分邊緣節點嘅 TLS 行為令 REALITY 握手必定失敗
HY2_SNI=www.bing.com             # Hysteria2 自簽憑證嘅 CN
ADDRESS=""
REALITY_SNI_SET=""
REALITY_PORT_SET=""
HY2_PORT_SET=""
DO_UPDATE=0
DO_KEEPALIVE=0

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'
info() { echo "${CYA}==>${RST} $*"; }
ok()   { echo "${GRN} ✔${RST} $*"; }
warn() { echo "${YEL} ⚠${RST} $*"; }
die()  { echo "${RED} ✘ $*${RST}" >&2; exit 1; }

# ---------------------------------------------------------------- 參數
while [[ $# -gt 0 ]]; do
  case "$1" in
    --address)      ADDRESS="${2:?--address 要跟住一個 IP 或域名}"; shift 2 ;;
    --update)       DO_UPDATE=1; shift ;;
    --keepalive)    DO_KEEPALIVE=1; shift ;;
    --reality-sni)  REALITY_SNI="${2:?}"; REALITY_SNI_SET=1; shift 2 ;;
    --port)         REALITY_PORT="${2:?}"; REALITY_PORT_SET=1; shift 2 ;;
    --hy2-port)     HY2_PORT="${2:?}"; HY2_PORT_SET=1; shift 2 ;;
    -h|--help)      sed -n '2,14p' "$0"; exit 0 ;;
    *)              die "唔認得嘅參數：$1（用 --help 睇用法）" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "要用 root 行：sudo bash $0"
command -v systemctl >/dev/null || die "呢個腳本需要 systemd"

# ---------------------------------------------------------------- 裝 sing-box
install_singbox() {
  info "安裝 sing-box …"

  # 先試官方 apt repo（有自動更新，最理想）
  if command -v apt-get >/dev/null; then
    apt-get update -qq || true
    apt-get install -y -qq ca-certificates curl openssl jq qrencode >/dev/null 2>&1 || \
      apt-get install -y ca-certificates curl openssl jq qrencode
    if curl -fsSL --max-time 30 https://sing-box.app/deb-install.sh -o /tmp/sb-install.sh 2>/dev/null \
       && bash /tmp/sb-install.sh >/dev/null 2>&1 && command -v sing-box >/dev/null; then
      ok "由官方 apt repo 裝好：$(sing-box version | head -1)"
      rm -f /tmp/sb-install.sh
      return
    fi
    warn "官方 apt repo 唔通，改用 GitHub binary"
  fi

  # 後備：直接落 GitHub release binary
  local arch ver url tmp
  case "$(uname -m)" in
    x86_64|amd64)  arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    armv7l|armv7)  arch=armv7 ;;
    *) die "唔支援嘅 CPU 架構：$(uname -m)" ;;
  esac

  ver=$(curl -fsSL --max-time 20 https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null \
        | grep -oP '"tag_name":\s*"v\K[^"]+' | head -1 || true)
  [[ -n "$ver" ]] || { ver=$FALLBACK_VERSION; warn "攞唔到最新版本號，用 $ver"; }

  url="https://github.com/SagerNet/sing-box/releases/download/v${ver}/sing-box-${ver}-linux-${arch}.tar.gz"
  tmp=$(mktemp -d)
  info "下載 sing-box ${ver} (${arch}) …"
  curl -fsSL --max-time 120 -o "$tmp/sb.tgz" "$url" || die "下載失敗：$url"
  tar -xzf "$tmp/sb.tgz" -C "$tmp"
  install -m 755 "$tmp"/sing-box-*/sing-box /usr/local/bin/sing-box
  rm -rf "$tmp"
  ok "裝好：$(sing-box version | head -1)"
}

SB=""
resolve_sb() { SB=$(command -v sing-box || echo /usr/local/bin/sing-box); }

if command -v sing-box >/dev/null && [[ $DO_UPDATE -eq 0 ]]; then
  ok "sing-box 已經裝咗：$(sing-box version | head -1)"
else
  install_singbox
fi
resolve_sb
[[ -x "$SB" ]] || die "搵唔到 sing-box binary"

# ---------------------------------------------------------------- 生成 / 沿用金鑰
mkdir -p "$CONF_DIR"

# 記低command line明確指定咗嘅值 —— source params.env 會覆蓋佢哋，之後要還原
CLI_SNI="${REALITY_SNI_SET:+$REALITY_SNI}"
CLI_PORT="${REALITY_PORT_SET:+$REALITY_PORT}"
CLI_HY2PORT="${HY2_PORT_SET:+$HY2_PORT}"

if [[ -f $PARAMS ]]; then
  # shellcheck disable=SC1090
  source "$PARAMS"
  # command line 優先於存檔嘅值
  [[ -n "$CLI_SNI" ]]     && REALITY_SNI="$CLI_SNI"
  [[ -n "$CLI_PORT" ]]    && REALITY_PORT="$CLI_PORT"
  [[ -n "$CLI_HY2PORT" ]] && HY2_PORT="$CLI_HY2PORT"
  ok "沿用現有金鑰（$PARAMS）— 客戶端唔使重新設定"
else
  [[ $DO_UPDATE -eq 1 ]] && warn "搵唔到舊參數，改為全新部署"
  info "生成金鑰 …"
  UUID=$("$SB" generate uuid)
  SHORT_ID=$("$SB" generate rand 8 --hex)
  HY2_PASS=$("$SB" generate rand 16 --hex)
  _kp=$("$SB" generate reality-keypair)
  REALITY_PRIVATE=$(awk '/PrivateKey/{print $2}' <<<"$_kp")
  REALITY_PUBLIC=$(awk '/PublicKey/{print $2}' <<<"$_kp")
  ok "金鑰生成完成"
fi

# 地址：--address > 已存 > 自動偵測公網 IP
if [[ -n "$ADDRESS" ]]; then
  SERVER_ADDR="$ADDRESS"
elif [[ -n "${SERVER_ADDR:-}" ]]; then
  :
else
  info "偵測公網 IP …"
  SERVER_ADDR=$(curl -4fsSL --max-time 10 https://api.ipify.org 2>/dev/null \
             || curl -4fsSL --max-time 10 https://ifconfig.me 2>/dev/null || true)
  [[ -n "$SERVER_ADDR" ]] || die "偵測唔到公網 IP，請用 --address 手動指定"
  ok "公網 IP：$SERVER_ADDR"
fi

cat >"$PARAMS" <<EOF
# sing-box 部署參數 — 呢個檔案好重要，記得 backup
# 重印連結：sudo bash scripts/show-links.sh
UUID=$UUID
SHORT_ID=$SHORT_ID
HY2_PASS=$HY2_PASS
REALITY_PRIVATE=$REALITY_PRIVATE
REALITY_PUBLIC=$REALITY_PUBLIC
REALITY_SNI=$REALITY_SNI
HY2_SNI=$HY2_SNI
REALITY_PORT=$REALITY_PORT
HY2_PORT=$HY2_PORT
SERVER_ADDR=$SERVER_ADDR
EOF
chmod 600 "$PARAMS"

# ---------------------------------------------------------------- Hysteria2 自簽憑證
if [[ ! -f $CONF_DIR/cert.pem || ! -f $CONF_DIR/key.pem ]]; then
  info "生成 Hysteria2 自簽憑證（CN=$HY2_SNI）…"
  openssl ecparam -genkey -name prime256v1 -out "$CONF_DIR/key.pem" 2>/dev/null
  openssl req -new -x509 -days 3650 -key "$CONF_DIR/key.pem" \
          -out "$CONF_DIR/cert.pem" -subj "/CN=$HY2_SNI" 2>/dev/null
  chmod 600 "$CONF_DIR/key.pem"
  ok "憑證生成完成（自簽，所以客戶端要 insecure=1）"
fi

# ---------------------------------------------------------------- 寫 config
info "寫 $CONF …"
cat >"$CONF" <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "dns": {
    "servers": [ { "type": "local", "tag": "local" } ],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": $REALITY_PORT,
      "users": [
        { "uuid": "$UUID", "flow": "xtls-rprx-vision" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$REALITY_SNI",
        "reality": {
          "enabled": true,
          "handshake": { "server": "$REALITY_SNI", "server_port": 443 },
          "private_key": "$REALITY_PRIVATE",
          "short_id": ["$SHORT_ID"]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2",
      "listen": "::",
      "listen_port": $HY2_PORT,
      "users": [ { "password": "$HY2_PASS" } ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CONF_DIR/cert.pem",
        "key_path": "$CONF_DIR/key.pem"
      }
    }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF
chmod 600 "$CONF"

# 一定要驗證過先至啟動 —— 唔好搞到 service 起唔返
"$SB" check -c "$CONF" || die "config 驗證失敗，未有改動任何運行中嘅服務"
ok "config 驗證通過"

# ---------------------------------------------------------------- systemd
if [[ ! -f /etc/systemd/system/sing-box.service ]] && \
   [[ ! -f /lib/systemd/system/sing-box.service ]]; then
  info "建立 systemd service …"
  cat >/etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box proxy service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=$SB -D /var/lib/sing-box -C $CONF_DIR run
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  mkdir -p /var/lib/sing-box
fi

systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1 || true
systemctl restart sing-box

sleep 2
if systemctl is-active --quiet sing-box; then
  ok "sing-box running"
else
  echo; journalctl -u sing-box -n 30 --no-pager || true
  die "sing-box 啟動失敗，上面係 log"
fi

# ---------------------------------------------------------------- 防火牆（第二層）
info "開防火牆 ${REALITY_PORT}/tcp + ${HY2_PORT}/udp …"
open_port() {  # $1=proto $2=port
  local v
  for v in iptables ip6tables; do
    command -v "$v" >/dev/null || continue
    "$v" -C INPUT -p "$1" --dport "$2" -j ACCEPT 2>/dev/null \
      || "$v" -I INPUT 1 -p "$1" --dport "$2" -j ACCEPT 2>/dev/null || true
  done
}
open_port tcp "$REALITY_PORT"
open_port udp "$HY2_PORT"

# 持久化（Oracle 嘅 Ubuntu image 重開機會還原 iptables）
if command -v netfilter-persistent >/dev/null; then
  netfilter-persistent save >/dev/null 2>&1 && ok "iptables 已持久化"
else
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent >/dev/null 2>&1 || true
  command -v netfilter-persistent >/dev/null && netfilter-persistent save >/dev/null 2>&1 \
    && ok "iptables 已持久化" || warn "裝唔到 iptables-persistent，重開機後可能要再行一次呢個腳本"
fi

# 有 ufw / firewalld 嘅話一併開
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "^Status: active"; then
  ufw allow "${REALITY_PORT}/tcp" >/dev/null 2>&1 || true
  ufw allow "${HY2_PORT}/udp"     >/dev/null 2>&1 || true
fi
if command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${REALITY_PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-port="${HY2_PORT}/udp"     >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

warn "記得埋雲端嗰層！Oracle 要喺 VCN Security List 加 ingress：TCP ${REALITY_PORT} + UDP ${HY2_PORT}"

# ---------------------------------------------------------------- BBR
if ! grep -q '^net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf 2>/dev/null; then
  info "開啟 BBR 擁塞控制 …"
  { echo 'net.core.default_qdisc=fq'
    echo 'net.ipv4.tcp_congestion_control=bbr'; } >>/etc/sysctl.conf
  sysctl -p >/dev/null 2>&1 || true
fi
if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" == "bbr" ]]; then
  ok "BBR 已啟用"
else
  warn "BBR 開唔到（kernel 可能唔支援），唔影響使用"
fi

# ---------------------------------------------------------------- 保活（可選）
if [[ $DO_KEEPALIVE -eq 1 ]]; then
  info "安裝閒置保活 …"
  cat >/usr/local/bin/sb-keepalive.sh <<'KA'
#!/usr/bin/env bash
# 產生少量 CPU + 網絡活動，避免 Oracle Always Free 因閒置回收實例。
# 刻意保持輕量：唔好用網上啲「跑滿 CPU」嘅腳本。
timeout 45 openssl speed -seconds 40 rsa2048 >/dev/null 2>&1 || true
curl -s --max-time 30 -o /dev/null https://speed.cloudflare.com/__down?bytes=52428800 || true
KA
  chmod 755 /usr/local/bin/sb-keepalive.sh
  cat >/etc/systemd/system/sb-keepalive.service <<'KA'
[Unit]
Description=Idle keepalive for Oracle Always Free
[Service]
Type=oneshot
ExecStart=/usr/local/bin/sb-keepalive.sh
KA
  cat >/etc/systemd/system/sb-keepalive.timer <<'KA'
[Unit]
Description=Run idle keepalive periodically
[Timer]
OnBootSec=10min
OnUnitActiveSec=30min
RandomizedDelaySec=10min
[Install]
WantedBy=timers.target
KA
  systemctl daemon-reload
  systemctl enable --now sb-keepalive.timer >/dev/null 2>&1 || true
  ok "保活已安裝（每 30 分鐘一次，好輕量）"
  warn "升級做 Pay As You Go 係更乾淨嘅做法 — PAYG 帳號完全唔會被閒置回收"
fi

# ---------------------------------------------------------------- 出連結
echo
"$(dirname "$(readlink -f "$0")")/show-links.sh"

echo
echo "${BLD}下一步：${RST}"
echo "  1. Oracle 用家：確認 VCN Security List 已加 ingress（TCP ${REALITY_PORT} / UDP ${HY2_PORT}）"
echo "  2. 喺澳門／香港先測試通到，唔好等返內地先試"
echo "  3. 睇實 log：${CYA}sudo journalctl -u sing-box -f${RST}"
echo "  4. Backup 好 ${CYA}${PARAMS}${RST} —— 冇咗就要全部客戶端重新設定"
