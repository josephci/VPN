# 客戶端設定

> **⚠️ 一定要喺入境內地之前裝好曬。** 內地區 App Store 冇呢啲 app，Google Play 直頭上唔到。落地先裝就太遲。
>
> 建議：**至少兩部裝置**（手機 + 電腦）都裝好、測試好，再備份埋 `params.env`。

最快嘅做法：喺伺服器行 `sudo bash scripts/show-links.sh`，用手機掃 QR code 匯入。以下係逐個平台嘅細節。

---

## iOS

### Shadowrocket（最推薦）

US$2.99，**要非中國區嘅 Apple ID**（中國區 App Store 已經落架）。冇非中國區 ID 嘅話，去 https://appleid.apple.com 開個新嘅，地區揀香港／美國，用禮品卡充值即可。

1. 開 Shadowrocket → 右上角 `+`
2. 撳右上角掃碼圖示 → 掃 REALITY 嗰個 QR code
3. 重複一次，掃 Hysteria2 嗰個
4. 返主頁，撳一下 REALITY 節點 → 上面掣切「連線」
5. 首次會彈窗要求安裝 VPN 設定描述檔 → 允許

**建議設定**：`設定` → `全域路由` 揀 **`配置`**（唔好揀「代理」），咁內地網站行直連、外網先走代理，快好多又慳流量。

### sing-box（免費）

App Store 搜 `sing-box`，官方出品，免費。撳 `+` → `Import from clipboard`（先複製連結）或掃碼。

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
