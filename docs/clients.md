# 客戶端設定

> **⚠️ 一定要喺入境內地之前裝好曬。** 內地區 App Store 冇呢啲 app，Google Play 直頭上唔到。落地先裝就太遲。
>
> 建議：**至少兩部裝置**（手機 + 電腦）都裝好、測試好，再備份埋 `params.env`。

最快嘅做法：喺伺服器行 `sudo bash scripts/show-links.sh`，用手機掃 QR code 匯入。以下係逐個平台嘅細節。

---

## 先搞清楚：你需要嘅係「代理客戶端」，唔係 VPN app

**OpenVPN、WireGuard 呢啲 app 用唔到** —— 唔係佢哋唔好，係**佢哋只識講自己嗰種協議**，唔識 VLESS-REALITY 同 Hysteria2。就好似 DVD 機播唔到藍光碟。

（而且就算你真係喺伺服器開返個 OpenVPN，喺內地一樣會俾 GFW 殺 —— 見 [`faq.md`](faq.md#點解普通-vpnipsec--wireguard--pptp喺內地唔得)。）

另外值得知嘅分別：

| | **VPN**（OpenVPN / WireGuard）| **代理**（VLESS / Hysteria2）|
|---|---|---|
| 層次 | 網絡層（L3），建虛擬網卡 | 應用層（L7），逐個連線轉發 |
| 流量 | **全部**入隧道 | **逐條連線**決定走邊 |
| 分流 | 粗糙 | 精細（域名 / IP / GeoIP / 按 app）|

分流唔止令你上淘寶微信快同慳流量，仲**大幅降低流量特徵** —— 只有真正需要嘅流量先經隧道。

---

## iOS

> iOS 上要接管系統流量必須用 Apple 嘅 **NetworkExtension** 框架，需要付費開發者帳號同權限審批 —— 所以 iOS 嘅選擇比 Android 少，而且多數收費。**但有免費嘅。**

### sing-box（免費，推薦先試呢個）

App Store 搜 `sing-box`，官方出品，**完全免費**。佢就係你部伺服器上跑緊嗰個 sing-box 嘅 iOS 版，**同源同宗，兼容性最好**。

撳 `+` → `Import from clipboard`（先複製連結）或者掃碼。

> 同樣要**非中國區 Apple ID** —— 呢點所有選擇都一樣，唔係 Shadowrocket 獨有。

### Karing（免費）

介面友善啲，都係免費。

### Shadowrocket（約 US$2.99）

**唔係必需**，但佢嘅**規則系統最強、教學資源最多**，遇到問題最易搵到答案。一次性收費，唔係訂閱。

要非中國區 Apple ID（中國區 App Store 已落架）。冇嘅話去 https://appleid.apple.com 開個新嘅，地區揀香港／美國，用禮品卡充值。

1. 開 Shadowrocket → 右上角 `+`
2. 撳右上角掃碼圖示 → 掃 REALITY 嗰個 QR code
3. 重複一次，掃 Hysteria2 嗰個
4. 返主頁，撳一下 REALITY 節點 → 上面掣切「連線」
5. 首次會彈窗要求安裝 VPN 設定描述檔 → 允許

**建議設定**：`設定` → `全域路由` 揀 **`配置`**（唔好揀「代理」），咁內地網站行直連、外網先走代理，快好多又慳流量。

> 💡 **Android 冇呢個問題** —— NekoBox、sing-box 都係免費開源，GitHub 下 APK 就得。

---

## Android

### NekoBox（推薦）

GitHub 下 APK：https://github.com/MatsuriDayo/NekoBoxForAndroid/releases → 揀 `arm64-v8a` 嗰個。

1. 右上角 `+` → `從剪貼簿匯入`（或者掃碼）
2. 兩個節點都加入
3. 撳節點 → 右下角紙飛機掣連線

**建議**：`設定` → `路由模式` 揀 **繞過中國大陸位址**。

### v2rayNG

https://github.com/2dust/v2rayNG/releases

⚠️ v2rayNG 支援 REALITY，但**唔支援 Hysteria2**。想兩個都用就揀 NekoBox。

---

## Windows

### v2rayN（推薦）

https://github.com/2dust/v2rayN/releases → `v2rayN-windows-64.zip`

1. 解壓、開 `v2rayN.exe`（首次會提示裝 .NET，跟住做）
2. `伺服器` → `從剪貼簿匯入批次 URL`（先複製兩條連結）
3. 右下角托盤圖示右鍵 → `系統代理` → **`自動設定系統代理`**
4. `路由` → 揀 **`繞過大陸`**

### Clash Verge Rev

https://github.com/clash-verge-rev/clash-verge-rev/releases

介面靚啲，`設定檔` → `新增` → 貼連結。

---

## macOS

### Clash Verge Rev（推薦）

同上，下載 `.dmg`。Apple Silicon 揀 `aarch64`，Intel 揀 `x64`。

首次開會被 Gatekeeper 攔：`系統設定` → `私隱與安全性` → 拉到底 → `仍要打開`。

### sing-box（命令列）

```bash
brew install sing-box
```

自己寫 client config，或者用上面嘅 GUI。

---

## 路由器全屋翻牆（進階）

如果你想屋企／公司成個網絡都走代理，可以喺 OpenWrt 路由器上跑 sing-box client。留意：

- 內地嘅路由器行呢啲，**風險比個人裝置高**（流量特徵集中、長期在線）
- 建議一定要配「繞過大陸位址」嘅路由規則，唔好全流量走代理

---

## 兩個協議點揀

| 情況 | 用邊個 |
|---|---|
| 平時日常 | **VLESS-REALITY**（偽裝最好，最穩陣） |
| 夜晚高峰、丟包嚴重、睇片卡 | **Hysteria2**（QUIC 抗丟包，明顯快啲） |
| REALITY 突然連唔到 | 切 **Hysteria2** |
| 兩個都連唔到 | 睇 [`troubleshooting.md`](troubleshooting.md) |

大部分客戶端支援「自動測速選最快」，可以將兩個放埋一個群組，設 URL test。

---

## NAS Docker 做法

如果你想喺 Synology / QNAP 上跑（做 client 或者第二個 server）：

```yaml
# docker-compose.yml
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sing-box
    restart: unless-stopped
    network_mode: host          # REALITY 需要，唔好用 bridge
    cap_add:
      - NET_ADMIN
    volumes:
      - ./config.json:/etc/sing-box/config.json:ro
      - ./cert.pem:/etc/sing-box/cert.pem:ro
      - ./key.pem:/etc/sing-box/key.pem:ro
    command: -D /var/lib/sing-box -C /etc/sing-box run
```

`config.json` 直接用伺服器上 `/etc/sing-box/config.json` 嗰份（改埋憑證路徑）。
