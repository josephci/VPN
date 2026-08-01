# 方案 A：Oracle Cloud 永久免費機 + VLESS-REALITY

用甲骨文雲嘅 **Always Free（永久免費，唔係試用期）** 開一部機，跑 **VLESS-REALITY**（主力）同 **Hysteria2**（備用），俾內地嘅裝置連出嚟。

| | |
|---|---|
| **成本** | **$0**（註冊要信用卡驗證，會扣 US$1 左右做授權再退返） |
| **機器** | ARM Ampere 4 核 / 24GB RAM，或者 2 部 AMD 細機 |
| **流量** | 每月 10TB 出站 |
| **機房** | 東京 / 大阪 / 首爾（對內地延遲最好） |

⚠️ **成個流程最難嘅唔係技術，係「開到機」** — ARM 機經常 out of capacity，要刷。[Step 3](#step-3-開實例最難嗰步) 有解決方法。

---

## 目錄

| Step | 做乜 | 難度 |
|---|---|---|
| [0](#step-0-開始之前) | 開始之前 | — |
| [1](#step-1-註冊甲骨文帳號) | 註冊甲骨文帳號 | ⭐⭐ 有坑 |
| [2](#step-2-生成-ssh-key) | 生成 SSH key | ⭐ |
| [3](#step-3-開實例最難嗰步) | 開實例 | ⭐⭐⭐ 最難 |
| [4](#step-4-開防火牆兩層都要開) | 開防火牆（**兩層**） | ⭐⭐ 最易漏 |
| [5](#step-5-ssh-入去跑部署腳本) | SSH 入去跑部署腳本 | ⭐ |
| [6](#step-6-客戶端設定) | 客戶端設定 | ⭐ |
| [7](#step-7-防止部機被回收) | 防止部機被回收 | ⭐ |

其他文件：
- [`docs/clients.md`](docs/clients.md) — 各平台客戶端逐步設定
- [`docs/troubleshooting.md`](docs/troubleshooting.md) — 排錯（連唔到／被封／速度慢）
- [`docs/maintenance.md`](docs/maintenance.md) — 換 IP、加用戶、更新、備份

---

## Step 0: 開始之前

準備好：

- **一張 Visa / Mastercard**（銀聯唔得；虛擬卡經常過唔到。香港／澳門發嘅卡冇問題）
- **一個唔係 QQ / 163 嘅 email**（Gmail / Outlook 最穩陣）
- **一個真實地址**（帳單地址要同信用卡對得上）
- **註冊嗰陣自己已經要有得上外網** — 甲骨文個註冊頁喺內地上唔到。喺澳門／香港做呢步最好。

⏱ 註冊 + 開機大約要 30 分鐘到幾日（睇你幾快刷到 ARM 機）。

---

## Step 1: 註冊甲骨文帳號

去 https://signup.cloud.oracle.com

### 🔴 最重要嘅一步：揀 Home Region

註冊表格會叫你揀 **Home Region**。

> **Home Region 一經確認就永遠改唔到，而 Always Free 嘅資源只可以開喺 Home Region。**

揀呢啲（對內地延遲由好到普通）：

| Region | 代號 | 備註 |
|---|---|---|
| **Japan East (Tokyo)** | `ap-tokyo-1` | 延遲最好，但 ARM 最搶手 |
| **Japan Central (Osaka)** | `ap-osaka-1` | 延遲差唔多，**ARM 容易開好多，推薦** |
| **South Korea Central (Seoul)** | `ap-seoul-1` | 延遲好，容量中等 |
| Singapore | `ap-singapore-1` | 延遲較高，但好易開機 |

**唔好揀**美國、歐洲嘅 region — 延遲會由 30ms 變 200ms+。

**建議揀大阪（Osaka）** — 東京同大阪對內地嘅延遲實測差好少，但大阪嘅 ARM 容量鬆好多，可以慳你幾日刷機時間。

### 註冊流程嘅坑

1. **Country/Territory** 揀你真實所在地（Macau / Hong Kong）
2. 驗證 email → 設密碼 → 填地址
3. **信用卡驗證**：會扣 US$1（或等值 HK$8）做授權，幾日後自動退返。**呢個唔係收費**。
4. 填完之後可能會見到 **"Account under review"** — 正常，一般等 15 分鐘到 24 小時。

**如果註冊失敗（"We are unable to process your request"）**，常見原因：
- 信用卡唔支援國際交易 → 換張卡
- 用緊 VPN 而 IP 同帳單地址對唔上 → 熄咗 VPN，或者換返本地 IP
- 同一張卡開過帳號 → 一張卡通常只可以開一個 Always Free 帳號

---

## Step 2: 生成 SSH key

喺你自己部電腦（澳門嗰部，唔係雲上面）行：

```bash
ssh-keygen -t ed25519 -C "oracle-vpn" -f ~/.ssh/oracle_vpn
```

一路撳 Enter（passphrase 可以留空）。完成之後：

```bash
cat ~/.ssh/oracle_vpn.pub
```

**複製呢串嘢**（`ssh-ed25519 AAAA... oracle-vpn`），Step 3 要用。

> Windows 用戶：喺 PowerShell 行同樣嘅指令就得，Windows 10 之後內置 OpenSSH。

⚠️ `~/.ssh/oracle_vpn`（冇 `.pub` 嗰個）係私鑰，**唔好俾任何人**。整份 backup 收好，唔見咗就入唔到部機。

---

## Step 3: 開實例（最難嗰步）

登入 https://cloud.oracle.com → 左上角漢堡選單 → `Compute` → `Instances` → **`Create instance`**

### 設定

| 欄位 | 揀乜 |
|---|---|
| **Name** | 隨便，例如 `proxy` |
| **Image** | 撳 `Change image` → **Canonical Ubuntu 24.04**（唔好用 Oracle Linux，麻煩好多） |
| **Shape** | 撳 `Change shape` → `Ampere` → **`VM.Standard.A1.Flex`**（要見到 `Always Free-eligible` 標籤）→ **預設 1 核 / 6 GB 就得，唔使改** |
| **Primary network / Subnet** | ⚠️ Subnet 一定要揀 **public subnet**（見下面） |
| **Public IPv4 address** | ✅ **一定要開 `Automatically assign public IPv4 address`** |
| **Add SSH keys** | 揀 `Paste public keys`，貼低 Step 2 複製嗰串 |
| **Boot volume** | 預設 50GB 就夠（Always Free 總共 200GB） |

撳 `Create`。

> **💡 唔好貪心拉去 4 核 / 24GB。**
>
> `A1.Flex` 個 "Flex" 係彈性嘅意思，揀完 shape 之後下面會有 OCPU / Memory 調整欄，最大可以拉到 4 核 / 24GB（Always Free 總額度）。**但唔好郁佢** ——
>
> 1. 跑代理 **1 核 / 6GB 有凸**（sing-box 閒時食唔到 50MB RAM，CPU 幾乎唔郁），24GB 對呢個用途冇任何分別
> 2. **細規格開得到嘅機會高好多** — 你最大嘅敵人係下面嗰個 "Out of host capacity"，4 核 24GB 係最搶手嘅配置
>
> 首要目標係**先開到部機**。之後想加隨時停機改得返。

> **🔴 `Automatically assign public IPv4 address` 個掣係灰色㩒唔到？**
>
> 你會見到下面有個黃色警告：*"You must select a public subnet to assign a public IPv4 address"*。
>
> **原因：你揀咗 private subnet（私有子網）。** 私有子網冇 internet gateway，所以連分配公網 IP 嘅選項都會被禁用。
>
> 喺同一個 Networking 步驟向上 scroll 搵 `Subnet`：
> - 有得揀現有 subnet → 揀 **`public subnet-vcn-xxxxx`**（唔好揀 `private subnet-...`）
> - 係 `Create new subnet` → `Subnet type` 揀 **`Public subnet`**
> - 得一個 private subnet 揀 → 喺 `Primary network` 改揀 **`Create new virtual cloud network`**，精靈會自動整個帶 internet gateway 同 public subnet 嘅 VCN
>
> 改完個掣就會著返，**記得撳開佢**。

> **📱 用緊手機做？** Oracle console 喺手機上排版好易爛（成幅右邊會俾切走），特別容易漏咗公網 IP 呢一步 —— 漏咗就成件事做唔到。**打橫拎部機**會好啲，但有電腦嘅話強烈建議轉電腦：後面仲有 Security List 加防火牆規則同 SSH，喺手機上會更折騰。
>
> 真係要喺手機做，SSH key 嗰步可以揀 **`Generate a key pair for me`** → 撳 **`Save private key`** 下載，唔使自己 `ssh-keygen`（但個私鑰檔之後要傳去你平時用嘅電腦）。

### 🔴 遇到 "Out of host capacity" 點算

呢個係甲骨文最出名嘅問題，ARM 機喺熱門 region 長期缺貨。三個解決方法，由好到差：

**① 升級做 Pay As You Go（最有效，強烈推薦）**

聽落嚇人，但**唔會扣你錢**：

> `Billing & Cost Management` → `Upgrade and Payment Method` → `Upgrade to Pay As You Go`

- Always Free 嗰堆額度**完全保留**，繼續免費
- 你只係「有咗」用付費資源嘅能力，唔開就唔收費
- **PAYG 帳號嘅開機優先級高好多**，通常即刻開到
- **另一個大好處**：PAYG 帳號嘅實例**唔會因為閒置被回收**（見 [Step 7](#step-7-防止部機被回收)）

⚠️ 記得之後唔好手多開咗收費規格嘅機。想穩陣可以去 `Billing` → `Budgets` 設個 US$1 預算警報。

**② 降低規格再試**

如果你郁咗個 OCPU / Memory，調返落去。**1 核 / 6GB** 開得到嘅機會比 4 核 / 24GB 高好多，而跑代理其實 1 核 6GB 已經非常夠用。

**③ 改開 AMD 免費機**

Shape 揀 **`VM.Standard.E2.1.Micro`**（1/8 OCPU、1GB RAM），Always Free 可以開 **2 部**。

規格細好多，但**跑代理完全夠**。呢款幾乎一定開到。如果你只係想快啲用到，直接開呢個。

**④ 換 Availability Domain**

如果你個 region 有 AD-1 / AD-2 / AD-3，逐個試。

> 唔好用第三方「自動搶機腳本」— 好多會叫你交 API 私鑰，等於將成個帳號交出去。寧願升 PAYG。

### 開好之後

實例頁面會顯示 **Public IP address**，例如 `168.138.xx.xx`。**記低佢**，之後成日要用。

---

## Step 4: 開防火牆（兩層都要開）

> **🔴 呢步係新手最常失敗嘅地方。** 甲骨文有**兩層**防火牆，兩層都要開，缺一連唔到。

### 第一層：VCN Security List（雲端層）

實例頁面 → `Primary VNIC` 區塊 → 撳 `Subnet` 個連結 → 撳 `Security Lists` 入面嗰個（通常叫 `Default Security List for vcn-xxx`）→ **`Add Ingress Rules`**

加兩條：

**規則 1 — REALITY (TCP 443)**
```
Stateless:              唔剔
Source Type:            CIDR
Source CIDR:            0.0.0.0/0
IP Protocol:            TCP
Source Port Range:      (留空)
Destination Port Range: 443
```

**規則 2 — Hysteria2 (UDP 8443)**
```
Stateless:              唔剔
Source Type:            CIDR
Source CIDR:            0.0.0.0/0
IP Protocol:            UDP
Source Port Range:      (留空)
Destination Port Range: 8443
```

⚠️ **第二條一定要揀 UDP。** Hysteria2 行 UDP，揀錯 TCP 就一世連唔到，而且症狀好難查。

### 第二層：實例入面嘅 iptables（系統層）

甲骨文嘅 Ubuntu image 預設帶住一套好嚴嘅 `iptables` 規則（唔係 `ufw`），淨係開咗 22 port。

**呢步唔使你自己做 — [Step 5](#step-5-ssh-入去跑部署腳本) 嘅 `deploy.sh` 會自動搞掂，仲會做持久化。**

---

## Step 5: SSH 入去跑部署腳本

喺你自己部電腦：

```bash
ssh -i ~/.ssh/oracle_vpn ubuntu@你嘅公網IP
```

> 用 Ubuntu image 嘅話用戶名係 `ubuntu`。如果話 `Permission denied`，行 `chmod 600 ~/.ssh/oracle_vpn` 再試。

入到去之後：

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/josephci/vpn.git
cd vpn
sudo bash scripts/deploy.sh
```

腳本會自動做曬：

1. 裝 sing-box（官方 apt repo，唔得就落 GitHub binary，自動認 ARM / x86）
2. 生成 UUID、REALITY 公私鑰對、short_id、Hysteria2 密碼
3. 幫 Hysteria2 整張自簽憑證
4. 寫 `/etc/sing-box/config.json`，跑 `sing-box check` 驗證先至啟動
5. 註冊 systemd service，開機自啟
6. **開 iptables 443/tcp + 8443/udp 並做持久化**（Step 4 第二層）
7. 開 BBR 擁塞控制（明顯改善跨境速度）
8. 印出 **分享連結 + QR code**

跑完之後你會見到類似咁：

```
════════════════════════════════════════════
  VLESS-REALITY（主力）
────────────────────────────────────────────
vless://xxxxxxxx-xxxx-...@168.138.xx.xx:443?encryption=none&flow=xtls-rprx-vision
&security=reality&sni=www.microsoft.com&fp=chrome&pbk=YJ2Ih...&sid=472c32...&type=tcp#Oracle-REALITY

  [QR code]

════════════════════════════════════════════
  Hysteria2（備用）
────────────────────────────────────────────
hysteria2://xxxxxxxx@168.138.xx.xx:8443?sni=www.bing.com&insecure=1#Oracle-HY2

  [QR code]
════════════════════════════════════════════
```

所有參數存喺 `/etc/sing-box/params.env`。想再睇一次：

```bash
sudo bash scripts/show-links.sh
```

### 呢兩個協議做緊乜

**VLESS-REALITY（主力）** — REALITY 唔使你買域名同憑證。佢握手嗰陣直接向真實嘅 `www.microsoft.com` 攞真憑證轉發俾你，所以 GFW 主動探測你個 443 端口嗰陣，見到嘅係一個貨真價實嘅微軟 TLS 站，驗證憑證鏈都過到。呢個由 2024 年起一直係內地抗封嘅事實標準。

**Hysteria2（備用）** — 基於改造版 QUIC，用 Salamander 混淆扮成 Chrome 上 Google 嘅正常 QUIC 流量。內地跨境線路夜晚丟包好嚴重，Hysteria2 有自己嘅擁塞控制，**喺丟包環境下反而比 TCP 類快好多**。REALITY 死咗就切呢個。

兩個一齊開，同時被破解嘅機會低好多。

---

## Step 6: 客戶端設定

> **⚠️ 一定要喺入境內地之前裝好。** 內地區 App Store 冇呢啲 app，Google Play 直頭上唔到，落地先裝就太遲。

| 平台 | 客戶端 |
|---|---|
| **iOS** | **Shadowrocket**（US$2.99，要非中國區 Apple ID）/ Stash / sing-box |
| **Android** | **NekoBox** / v2rayNG（GitHub 下 APK）/ sing-box |
| **Windows** | **v2rayN** / Clash Verge Rev |
| **macOS** | **Clash Verge Rev** / sing-box |

最快：用手機客戶端「掃描二維碼匯入」掃 Step 5 印出嗰兩個 QR code。

逐個平台嘅詳細設定見 [`docs/clients.md`](docs/clients.md)。

### 喺澳門／香港先測試好佢

**唔好等返到內地先試。** 喺澳門開住客戶端，去 https://ip.sb 睇下個 IP 係咪變咗做日本，通到先算。

同時喺伺服器度睇 log 確認連得入：

```bash
sudo journalctl -u sing-box -f
```

---

## Step 7: 防止部機被回收

> **甲骨文會回收「閒置」嘅 Always Free 實例。**

判斷標準係連續 7 日入面：CPU 95 百分位使用率 < 20%、網絡使用率 < 20%、記憶體 < 20%。一部淨係跑代理嘅機好容易中招 —— **回收咗就冇曬，要重新開過。**

兩個做法：

**① 升級做 Pay As You Go（最乾淨）**

同 [Step 3](#-遇到-out-of-host-capacity-點算) 講嘅同一個做法。**PAYG 帳號完全唔適用閒置回收規則**，仲順便解決開機難嘅問題。唔開收費資源就唔會有任何收費。

**② 跑個保活任務**

如果你唔想升 PAYG，`deploy.sh` 有個選項可以裝個輕量保活（定時做少量 CPU + 網絡活動）：

```bash
sudo bash scripts/deploy.sh --keepalive
```

⚠️ 唔好用網上啲「跑滿 CPU」嘅腳本 — 又嘥電又可能觸發甲骨文嘅濫用檢測。

---

## 之後要記住嘅事

- **一定要有 plan B。** 單一出口一定會有斷嘅一日。建議另外買部最平嘅 VPS（**RackNerd** 促銷約 US$12 **一年**）跑同一套腳本 —— `deploy.sh` 喺任何 Debian/Ubuntu 機都用得。再加埋 **Psiphon**、**Cloudflare WARP** 做最後保險。
- **IP 被封點算** — 機房 IP 係 GFW 主要打擊目標。甲骨文可以免費換 IP，做法見 [`docs/maintenance.md`](docs/maintenance.md#換-ip)。
- **敏感時期封鎖會收緊**（兩會、重要會議前後）。呢個時候 REALITY 都可能唔穩，Hysteria2 通常撐得耐啲。
- **唔好變成公用出口。** 借俾屋企人朋友冇問題，但人一多、流量一大，個 IP 就好突出。而且喺內地，**「經營／轉賣」翻牆服務係真係會被檢控**（刑法 285 條、非法經營）；自己用同攞嚟做生意係兩回事。
- **定期更新**：`sudo apt update && sudo apt upgrade sing-box`，或者 `sudo bash scripts/deploy.sh --update`（會保留你現有嘅 UUID / 金鑰，客戶端唔使重設）。

---

## 檔案結構

```
scripts/
  deploy.sh          一鍵部署（裝 sing-box + 生成 config + systemd + 防火牆 + BBR）
  show-links.sh      重新印分享連結同 QR code
  check-env.sh       部署前後嘅環境自檢
docs/
  clients.md         各平台客戶端設定
  troubleshooting.md 排錯
  maintenance.md     換 IP、加用戶、更新、備份
```

腳本喺 **sing-box 1.12.0** 上驗證過（`sing-box check` 通過 + 實際啟動成功），ARM64 同 x86_64 都支援。
