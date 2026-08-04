#!/usr/bin/env bash
#
# verify-reality.sh — 以「伺服器真正運行緊嘅 config.json」為準，
#                     反推正確嘅 REALITY 公鑰同分享連結。
#
# 用嚟查 "REALITY: processed invalid connection" —— 呢個錯代表客戶端嘅
# 公鑰 (pbk) 或 short_id (sid) 同伺服器對唔上。
#
#   sudo bash scripts/verify-reality.sh              比對 + 印正確連結
#   sudo bash scripts/verify-reality.sh --fix        順手修正 params.env
#
set -euo pipefail

CONF=/etc/sing-box/config.json
PARAMS=/etc/sing-box/params.env
DO_FIX=0
[[ "${1:-}" == "--fix" ]] && DO_FIX=1

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'

[[ $EUID -eq 0 ]] || { echo "${RED}要 root：sudo bash $0${RST}" >&2; exit 1; }
[[ -f $CONF ]]    || { echo "${RED}搵唔到 $CONF${RST}" >&2; exit 1; }
command -v python3 >/dev/null || { echo "${RED}需要 python3${RST}" >&2; exit 1; }

# 用 C_ 前綴，避免之後 source params.env 覆蓋咗由 config 讀出嚟嘅值
read -r C_UUID C_FLOW C_SNI C_SID C_PRIV C_PUB <<<"$(python3 - "$CONF" <<'PY'
import base64, json, sys

P, A24 = 2**255 - 19, 121665

def cswap(swap, a, b):
    d = (swap * ((a - b) % P)) % P
    return (a - d) % P, (b + d) % P

def scalarmult(k, u):
    x1, x2, z2, x3, z3, swap = u, 1, 0, u, 1, 0
    for t in range(254, -1, -1):
        kt = (k >> t) & 1
        swap ^= kt
        x2, x3 = cswap(swap, x2, x3)
        z2, z3 = cswap(swap, z2, z3)
        swap = kt
        A = (x2 + z2) % P; AA = A * A % P
        B = (x2 - z2) % P; BB = B * B % P
        E = (AA - BB) % P
        C = (x3 + z3) % P; D = (x3 - z3) % P
        DA = D * A % P; CB = C * B % P
        x3 = pow(DA + CB, 2, P)
        z3 = x1 * pow(DA - CB, 2, P) % P
        x2 = AA * BB % P
        z2 = E * (AA + A24 * E) % P
    x2, x3 = cswap(swap, x2, x3)
    z2, z3 = cswap(swap, z2, z3)
    return x2 * pow(z2, P - 2, P) % P

b64d = lambda s: base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
b64e = lambda b: base64.urlsafe_b64encode(b).decode().rstrip("=")

def pub_from_priv(priv):
    b = bytearray(b64d(priv))
    b[0] &= 248; b[31] &= 127; b[31] |= 64
    return b64e(scalarmult(int.from_bytes(b, "little"), 9).to_bytes(32, "little"))

cfg = json.load(open(sys.argv[1]))
ib = next(i for i in cfg["inbounds"] if i.get("type") == "vless")
tls = ib["tls"]; r = tls["reality"]
priv = r["private_key"]
sid = (r.get("short_id") or [""])[0]
print(ib["users"][0]["uuid"],
      ib["users"][0].get("flow", "") or "-",
      tls.get("server_name", "-"),
      sid or '""',
      priv,
      pub_from_priv(priv))
PY
)"

echo
echo "${BLD}由 config.json（伺服器真正跑緊嗰份）反推：${RST}"
echo "────────────────────────────────────────────────"
echo "  UUID       : $C_UUID"
echo "  flow       : $C_FLOW"
echo "  SNI        : $C_SNI"
echo "  short_id   : $C_SID"
echo "  公鑰 (pbk) : ${BLD}${C_PUB}${RST}"
echo

MISMATCH=0
if [[ -f $PARAMS ]]; then
  # shellcheck disable=SC1090
  source "$PARAMS"
  echo "${BLD}同 params.env 比對：${RST}"
  echo "────────────────────────────────────────────────"
  chk() { # $1=名 $2=config值 $3=params值
    if [[ "$2" == "$3" ]]; then
      echo "${GRN} ✔${RST} $1 一致"
    else
      echo "${RED} ✘ $1 唔一致${RST}"
      echo "     config.json : $2"
      echo "     params.env  : ${3:-（冇值）}"
      MISMATCH=1
    fi
  }
  chk "UUID    " "$C_UUID" "${UUID:-}"
  chk "公鑰    " "$C_PUB"  "${REALITY_PUBLIC:-}"
  chk "short_id" "$C_SID"  "${SHORT_ID:-}"
  chk "SNI     " "$C_SNI"  "${REALITY_SNI:-}"
  echo
  if [[ $MISMATCH -eq 1 ]]; then
    echo "${YEL}${BLD} ⚠ params.env 同實際運行嘅 config 對唔上。${RST}"
    echo "${YEL}   之前用 show-links.sh 出嘅連結係錯嘅 —— 用下面呢條。${RST}"
    if [[ $DO_FIX -eq 1 ]]; then
      sed -i "s|^UUID=.*|UUID=$C_UUID|; s|^REALITY_PUBLIC=.*|REALITY_PUBLIC=$C_PUB|; s|^SHORT_ID=.*|SHORT_ID=$C_SID|; s|^REALITY_SNI=.*|REALITY_SNI=$C_SNI|" "$PARAMS"
      echo "${GRN} ✔ 已修正 params.env${RST}"
    else
      echo "   加 ${CYA}--fix${RST} 可以順手改正 params.env"
    fi
    echo
  fi
fi

ADDR="${SERVER_ADDR:-}"
[[ -n "$ADDR" ]] || ADDR=$(curl -4fsSL --max-time 10 https://api.ipify.org 2>/dev/null || echo "你嘅IP")
HOST="$ADDR"; [[ "$HOST" == *:* && "$HOST" != \[* ]] && HOST="[$HOST]"
PORT="${REALITY_PORT:-443}"

FLOW_Q=""; [[ "$C_FLOW" != "-" ]] && FLOW_Q="&flow=${C_FLOW}"
SID_Q="";  [[ "$C_SID" != '""' ]] && SID_Q="&sid=${C_SID}"

echo "${BLD}✅ 正確嘅 VLESS-REALITY 連結（以 config.json 為準）${RST}"
echo "────────────────────────────────────────────────"
echo "vless://${C_UUID}@${HOST}:${PORT}?encryption=none${FLOW_Q}&security=reality&sni=${C_SNI}&fp=chrome&pbk=${C_PUB}${SID_Q}&type=tcp#REALITY"
echo
echo "${YEL} ⚠ 匯入前先喺客戶端刪曬舊節點，免得撳錯返舊嗰個。${RST}"
