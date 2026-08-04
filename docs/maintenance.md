# 日常維護

## 備份（最重要）

`/etc/sing-box/params.env` 入面係你所有憑證。**冇咗就要重新設定曬所有客戶端。**

```bash
sudo cat /etc/sing-box/params.env
```

抄低收好（密碼管理器最好）。或者由本機拉返落嚟：

```bash
scp -i ~/.ssh/oracle_vpn ubuntu@你嘅IP:/tmp/params.env ./params.env.bak
# （要先喺伺服器 sudo cp /etc/sing-box/params.env /tmp/ && sudo chown ubuntu /tmp/params.env）
```

⚠️ 連同 `~/.ssh/oracle_vpn` 私鑰一齊備份 — 冇咗就 SSH 唔入部機。

---

## 更新 sing-box

```bash
sudo apt update && sudo apt upgrade sing-box    # 官方 apt repo 裝嘅
sudo bash scripts/deploy.sh --update            # 或者用腳本（binary 安裝都得）
```

`--update` **會保留現有 UUID 同金鑰**，客戶端唔使重新設定。

建議一兩個月更新一次 — 新版通常有針對新封鎖手法嘅改進。

---

## 換 IP

IP 俾 GFW 封咗嘅時候用。**甲骨文換 IP 免費。**

1. Oracle Console → `Compute` → `Instances` → 你部機
2. 落到 `Resources` → `Attached VNICs` → 撳個 VNIC
3. `IPv4 Addresses` → 右邊三點 → `Edit`
4. `Public IP Type` 改做 **`No Public IP`** → Update
5. 等 30 秒，再 `Edit` 一次，改返做 **`Ephemeral Public IP`** → Update
6. 返實例頁面攞新 IP

然後喺伺服器：

```bash
sudo bash scripts/show-links.sh --set-address 新IP
```

重新掃 QR code 匯入客戶端就得。

> 想要一個唔會變嘅 IP，可以攞 **Reserved Public IP**（Always Free 有 1 個額度）。但被封嘅時候換起上嚟就冇咁方便。
>
> **一個更好嘅做法**：買個平域名（`.top` / `.xyz` 首年幾蚊美金），DNS A 記錄指住 IP。換 IP 只需改 DNS，客戶端完全唔使動。
> ⚠️ DNS 記錄一定要係 **DNS only（灰色雲）**，唔好開 Cloudflare CDN proxy — 會直接搞爛 REALITY 握手。

---

## 加多個用戶

改 `/etc/sing-box/config.json`，喺 `users` 陣列加多個：

```json
"users": [
  { "uuid": "原本嗰個", "flow": "xtls-rprx-vision" },
  { "uuid": "新生成嘅",  "flow": "xtls-rprx-vision" }
]
```

新 UUID：`sing-box generate uuid`

Hysteria2 同理，喺佢個 `users` 加 `{ "password": "新密碼" }`。

改完一定要先驗證再重啟：

```bash
sudo sing-box check -c /etc/sing-box/config.json && sudo systemctl restart sing-box
```

> ⚠️ 借俾屋企人朋友冇問題，但**唔好變成公用出口**。人一多、流量一大，個 IP 嘅行為模式就好突出，好易被盯。
>
> 而且喺內地，**「經營／轉賣」翻牆服務係真係會被檢控**（刑法 285 條、非法經營）。自己用同攞嚟做生意係兩回事。

---

## 換 REALITY 偽裝目標

如果覺得 `www.microsoft.com` 太多人用，可以換。**條件**：目標站要支援 TLS 1.3 + H2、喺內地連得到、而且唔係你自己嘅站。

常用選擇：`www.apple.com`、`www.amazon.com`、`www.cloudflare.com`、`dl.google.com`

```bash
sudo bash scripts/deploy.sh --reality-sni www.apple.com
sudo bash scripts/show-links.sh          # 出新連結，客戶端要重新匯入
```

---

## 換端口

443 最好（同普通 HTTPS 撈埋一齊），一般唔建議改。真係要改：

```bash
sudo bash scripts/deploy.sh --port 8443 --hy2-port 20443
```

**記得同步更新 Oracle 嘅 Security List ingress 規則**，唔係就連唔到。

---

## 監控

```bash
systemctl status sing-box                    # 服務狀態
journalctl -u sing-box --since today         # 今日 log
ss -tnp | grep sing-box | wc -l              # 有幾多條連線
vnstat -m                                    # 每月流量（sudo apt install vnstat）
```

Always Free 每月 10TB 出站，正常用途好難用得完。想睇實際用量：Oracle Console → `Billing` → `Cost Analysis`。

---

## 建立第二個出口（強烈建議）

單一出口一定會有斷嘅一日 — IP 被封、實例被回收、甲骨文帳號出事。

**同一套腳本可以直接跑喺任何 Debian/Ubuntu 機上**：

```bash
git clone https://github.com/josephci/vpn.git && cd vpn
sudo bash scripts/deploy.sh
```

### 揀 VPS 嘅三個準則

**① 位置：亞洲 > 美國／歐洲。** 日本／韓國／新加坡對內地通常 **30–60ms**；美國西岸 **150–200ms**，歐洲更差。日常瀏覽嘅分別好明顯。平價 VPS 好多都係美國機房，貪平之前要衡量。

**② 唔好揀「翻牆界最紅」嗰幾間。** 越多人攞嚟翻牆嘅供應商，佢啲 IP 段越大機會俾 GFW **整段誤殺** —— 你冇做錯任何嘢都會中招。呢個係反直覺嘅：論壇成日推薦嗰幾間，正正就係被打得最勁嗰幾間。

**③ 一定要支援換 IP。** IP 被封唔係「如果」係「幾時」。有啲供應商換 IP 免費或者收幾蚊，有啲要你重新買過機。

| 供應商 | 價錢 | 備註 |
|---|---|---|
| **Vultr 東京** | 按小時計費 | 延遲好；**可以開咗測完唔通就即刻銷毀再開**，每次試幾毫子 |
| **RackNerd** | 約 US$11–15 **一年** | 最平，但機房喺美國，延遲 150ms+ |
| **Hetzner** | 約 €4/月 | 機器質素好，但歐洲延遲高 |
| 甲骨文第二部機 | $0 | Always Free 額度共用，但要諗埋容量問題 |

> 價錢會變，買之前自己核實。

### 買之前一定要測個 IP

**唔好買咗先算。** 好多供應商喺購買頁會俾 **test IP**，用呢啲工具由內地節點測佢通唔通：

- **itdog.cn** — 內地多節點 ping / traceroute
- **ping.chinaz.com** — 同類工具

如果內地大部分節點都 timeout，嗰段 IP 大機會已經被封，唔好買。

**最穩陣嘅做法**：揀按小時計費嘅供應商（例如 Vultr），開機 → 跑 `deploy.sh` → 由內地測 → 唔通就銷毀再開一部新 IP。幾毫子就試到一次。

### 最後保險

再加埋 **Psiphon（賽風）** 同 **Cloudflare WARP** — 兩個都免費，通唔通睇彩數，但關鍵時刻救得你命。

---

## 停用 / 刪除

```bash
sudo systemctl disable --now sing-box
sudo systemctl disable --now sb-keepalive.timer   # 如果裝咗保活
sudo rm -rf /etc/sing-box
```

Oracle 實例終止：Console → 實例 → `More Actions` → `Terminate`（記得剔 `Delete boot volume`，唔係會繼續食你 200GB 額度）。
