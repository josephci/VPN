# 排錯

先跑自檢，八成問題佢會直接指出嚟：

```bash
# 喺伺服器上 —— 一定要加 sudo
sudo bash scripts/check-env.sh

# 喺澳門／香港（由外面探測，唔使 sudo）
bash scripts/check-env.sh 你嘅IP
```

> ⚠️ 伺服器自檢**冇 sudo 會查唔到 config 同防火牆** —— `config.json` 係 600 root-only，`iptables` 亦要 root。腳本會提你，唔會再報假失敗。

---

## 診斷次序

**由外面連唔到嘅時候，逐層排除，唔好跳步：**

```
① sing-box 有冇行？        sudo systemctl status sing-box
② 有冇聽住個 port？        sudo ss -tlnp | grep 443
                          sudo ss -ulnp | grep 8443
③ 本機 iptables 開咗未？    sudo iptables -L INPUT -n --line-numbers | head -12
④ 雲端 Security List 開咗未？（Oracle Console，腳本檢查唔到）
⑤ 客戶端參數啱唔啱？        sudo bash scripts/show-links.sh 對一次
⑥ IP 係咪俾 GFW 封咗？      見下面
```

---

## 常見問題

### 完全連唔到，端口探測都唔通

**九成係甲骨文嘅雲端防火牆漏咗開。** 呢個係最常見嘅失敗原因。

去 Oracle Console → `Networking` → `Virtual Cloud Networks` → 你個 VCN → `Subnets` → 你個 subnet → `Security Lists` → `Default Security List` → `Ingress Rules`

確認有：

| Source | Protocol | Dest Port |
|---|---|---|
| `0.0.0.0/0` | TCP | `443` |
| `0.0.0.0/0` | UDP | `8443` |

> ⚠️ 如果你用緊 **Network Security Group (NSG)** 而唔係 Security List，就要喺 NSG 度加，兩者係獨立嘅。

### REALITY 通，但 Hysteria2 唔通

幾乎一定係 **UDP 規則寫成 TCP**。返 Security List 睇清楚第二條規則個 Protocol 係咪 **UDP**。

另外查伺服器：

```bash
sudo ss -ulnp | grep 8443          # 要見到 sing-box
sudo iptables -C INPUT -p udp --dport 8443 -j ACCEPT && echo OK
```

### 重開機之後就唔通

iptables 規則冇持久化。Oracle 嘅 Ubuntu image 重開機會還原預設規則。

```bash
sudo apt install -y iptables-persistent
sudo bash scripts/deploy.sh          # 會重新加規則並持久化
```

### 客戶端顯示「握手失敗 / TLS handshake error」

REALITY 參數對唔上。**逐個字對**：

```bash
sudo bash scripts/show-links.sh
```

最常打錯嘅係 **公鑰 (pbk)** 同 **short id (sid)**。留意 REALITY 嘅**公鑰**先係客戶端用嘅，**私鑰**淨係留喺伺服器。

另外確認客戶端嘅：
- `flow` = `xtls-rprx-vision`
- `fp`（指紋）= `chrome`
- `sni` = `www.microsoft.com`（同伺服器 config 一致）

### Hysteria2 顯示憑證錯誤

腳本用嘅係**自簽憑證**，所以客戶端一定要開 **`跳過憑證驗證` / `insecure` / `允許不安全`**。分享連結入面嘅 `insecure=1` 已經帶咗，但有啲客戶端要手動剔。

### 用咗一段時間之後突然斷

先搞清楚係邊一種封鎖 —— 對策完全唔同：

| | 係乜 | 症狀 | 對策 |
|---|---|---|---|
| **協議被識別** | GFW 認出流量特徵係代理 | 換幾多次 IP 都一樣死 | 換協議（REALITY / Hysteria2 已經係最強嗰批）|
| **IP 被封** | 淨係封你個 IP，唔理協議 | **換 IP 即刻復活** | 見下面 |

用緊 REALITY 嘅話，第一種好難發生 —— GFW 主動探測你個 443 port 會見到一個真嘅微軟 TLS 站，連憑證鏈都驗得過。所以**九成係第二種**。

IP 被封又分兩類：
- **針對性封鎖** — 探測到你係代理先封。REALITY 令呢個好難發生。
- **整段範圍誤殺** — 某啲 VPS 供應商嘅 IP 段太多人攞嚟翻牆，GFW 索性成段封。**你冇做錯任何嘢都會中招**，呢個先係機房 IP 嘅主要風險。

判斷方法：

```bash
# 喺內地：ping 唔通 + TCP 443 唔通，但喺香港／澳門一切正常 → IP 被封
```

處理方法見 [`maintenance.md` 換 IP](maintenance.md#換-ip)。甲骨文換 IP 免費。

換完 IP 之後：

```bash
sudo bash scripts/show-links.sh --set-address 新IP
```

再重新匯入客戶端。

### 通得到但好慢

按可能性排：

1. **未開 BBR** — `sysctl -n net.ipv4.tcp_congestion_control` 應該係 `bbr`。唔係就跑 `sudo bash scripts/deploy.sh`
2. **夜晚高峰（20:00–24:00）跨境擁塞** — 切去 **Hysteria2**，QUIC 抗丟包好好多，通常快幾倍
3. **客戶端全流量走代理** — 開「繞過大陸位址」路由規則，內地網站行直連
4. **region 揀錯咗** — 如果 Home Region 揀咗美國／歐洲，延遲會由 30ms 變 200ms+。Home Region 改唔到，只能重開帳號

### 「Out of host capacity」開唔到機

見 [README Step 3](../README.md#-遇到-out-of-host-capacity-點算)。最有效係**升級做 Pay As You Go**（唔會扣錢，Always Free 額度保留，開機優先級大幅提高）。

或者直接改開 `VM.Standard.E2.1.Micro`（AMD 免費機），規格細但跑代理夠有凸，而且幾乎一定開到。

### 部機無啦啦冇咗

Always Free 實例閒置太耐會被回收（連續 7 日 CPU/網絡/記憶體都低於 20%）。

預防：升 PAYG（完全豁免呢條規則），或者 `sudo bash scripts/deploy.sh --keepalive`。

### SSH 都入唔到

- `Permission denied (publickey)` → `chmod 600 ~/.ssh/oracle_vpn`，同確認用戶名係 `ubuntu`（Ubuntu image）
- 連線 timeout → Security List 有冇 TCP 22 ingress；或者你之前改 iptables 時鎖死咗自己
- 真係入唔到 → Oracle Console 有 **Cloud Shell** 同 **Console Connection**（序列埠）可以救返

---

## IPv6 方案

如果你嘅出口只有 IPv6（例如 CGNAT 環境），sing-box 嘅 `"listen": "::"` 已經同時聽 IPv4 同 IPv6，唔使改 config。

但要留意：
- 客戶端所在嘅內地網絡要有 IPv6（移動、電信覆蓋唔錯，聯通較差）
- 分享連結入面 IPv6 字面地址要用 `[]` 包住 — `show-links.sh` 已經自動處理
- GFW **一樣會檢測 IPv6 流量**，唔會因為行 IPv6 就免疫

---

## 睇 log

```bash
sudo journalctl -u sing-box -f              # 實時
sudo journalctl -u sing-box -n 100 --no-pager   # 最近 100 行
sudo journalctl -u sing-box --since "1 hour ago"
```

想睇詳細啲，改 `/etc/sing-box/config.json` 入面 `"level": "warn"` 做 `"info"` 或 `"debug"`，然後 `sudo systemctl restart sing-box`。

⚠️ debug level 會記低連線目標，查完記得改返 `warn`。

---

## 完全重來

```bash
sudo systemctl stop sing-box
sudo rm -rf /etc/sing-box
sudo bash scripts/deploy.sh
```

會生成全新嘅 UUID / 金鑰，所有客戶端都要重新匯入。
