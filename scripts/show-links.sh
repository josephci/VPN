#!/usr/bin/env bash
#
# show-links.sh — 由 /etc/sing-box/params.env 重新產生分享連結同 QR code
#
#   sudo bash scripts/show-links.sh
#   sudo bash scripts/show-links.sh --set-address my.ddns.net   改地址並重印
#   sudo bash scripts/show-links.sh --no-qr                     淨係印連結
#
set -euo pipefail

PARAMS=/etc/sing-box/params.env
SHOW_QR=1
NEW_ADDR=""

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --set-address) NEW_ADDR="${2:?--set-address 要跟住一個 IP 或域名}"; shift 2 ;;
    --no-qr)       SHOW_QR=0; shift ;;
    -h|--help)     sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "${RED}唔認得嘅參數：$1${RST}" >&2; exit 1 ;;
  esac
done

[[ -f $PARAMS ]] || { echo "${RED}搵唔到 $PARAMS，請先行 deploy.sh${RST}" >&2; exit 1; }
# shellcheck disable=SC1090
source "$PARAMS"

# 改地址
if [[ -n "$NEW_ADDR" ]]; then
  [[ $EUID -eq 0 ]] || { echo "${RED}改地址要 root${RST}" >&2; exit 1; }
  sed -i "s|^SERVER_ADDR=.*|SERVER_ADDR=${NEW_ADDR}|" "$PARAMS"
  SERVER_ADDR="$NEW_ADDR"
  echo "${GRN} ✔${RST} 地址已更新做 ${BLD}${SERVER_ADDR}${RST}"
fi

# IPv6 字面地址要用 [] 包住
HOST="$SERVER_ADDR"
[[ "$HOST" == *:* && "$HOST" != \[* ]] && HOST="[$HOST]"

VLESS_URL="vless://${UUID}@${HOST}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${REALITY_PUBLIC}&sid=${SHORT_ID}&type=tcp#Oracle-REALITY"
HY2_URL="hysteria2://${HY2_PASS}@${HOST}:${HY2_PORT}?sni=${HY2_SNI}&insecure=1#Oracle-HY2"

qr() {
  [[ $SHOW_QR -eq 1 ]] || return 0
  if command -v qrencode >/dev/null; then
    echo; qrencode -t ANSIUTF8 -m 1 "$1"
  else
    echo "${YEL} ⚠ 未裝 qrencode，冇 QR code。裝法：sudo apt install -y qrencode${RST}"
  fi
}

line() { printf '%s\n' "════════════════════════════════════════════════════════════"; }
sub()  { printf '%s\n' "────────────────────────────────────────────────────────────"; }

echo
line
echo "${BLD}  VLESS-REALITY（主力，TCP ${REALITY_PORT}）${RST}"
sub
echo "$VLESS_URL"
qr "$VLESS_URL"
echo
line
echo "${BLD}  Hysteria2（備用，UDP ${HY2_PORT}）${RST}"
sub
echo "$HY2_URL"
qr "$HY2_URL"
echo
line

echo
echo "${BLD}手動填參數（如果客戶端唔支援匯入連結）${RST}"
sub
echo "地址：            $SERVER_ADDR"
echo
echo "${CYA}VLESS-REALITY${RST}"
echo "  端口：          $REALITY_PORT (TCP)"
echo "  UUID：          $UUID"
echo "  流控 flow：     xtls-rprx-vision"
echo "  傳輸：          tcp"
echo "  安全：          reality"
echo "  SNI：           $REALITY_SNI"
echo "  指紋 fp：       chrome"
echo "  公鑰 pbk：      $REALITY_PUBLIC"
echo "  short id：      $SHORT_ID"
echo
echo "${CYA}Hysteria2${RST}"
echo "  端口：          $HY2_PORT (UDP)"
echo "  密碼：          $HY2_PASS"
echo "  SNI：           $HY2_SNI"
echo "  跳過憑證驗證：  是（自簽憑證，insecure=1）"
echo
echo "${YEL} ⚠ 呢啲係你嘅憑證，唔好公開貼上網。${RST}"
