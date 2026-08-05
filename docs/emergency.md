# 應急卡：人喺內地、得部手機、連唔到

> 📱 **呢頁設計成喺手機上睇。** 連唔到嗰陣你未必開到 GitHub —— **建議而家 screenshot 低，或者存做離線筆記。**

---

## 核心認知

**換 IP 唔需要 SSH、唔需要電腦。**

客戶端節點入面嘅 **UUID、公鑰 (pbk)、short_id (sid)、SNI、端口全部唔會變**。IP 換咗，你只需要改 app 入面「**地址**」嗰一欄。

---

## 事前準備（唔做就救唔到自己）

### ① 確認手機登入到 Oracle Console

而家試登入一次 https://cloud.oracle.com，特別確認：

- **Cloud Account Name（tenancy 名）** — 登入頁第一格就要填，好多人只記得 email
- **MFA 方法** — authenticator 若果只裝喺電腦，到時就死。**手機一定要有**

### ② 抄低所有參數

```bash
sudo cat /etc/sing-box/params.env
```

存入手機密碼管理器。要由零重建節點嘅話，冇呢啲就重建唔到。

### ③ 手機裝定 Psiphon（救生艇）

`cloud.oracle.com` 喺內地通常上到（商業服務，唔喺封鎖名單），但唔好賭。Psiphon 免費、細，裝住當保險。

### ④ 記低實例名同 IP

例如 `instance-20260804-2311` / `129.x.x.x`，到時搵得快。

---

## 換 IP：純手機步驟

> 手機**打橫拎**，Oracle Console 喺手機上排版好易爛。

1. 開 **Psiphon**（若 `cloud.oracle.com` 直接上到可跳過）
2. 瀏覽器登入 https://cloud.oracle.com
3. 漢堡選單 → `Compute` → `Instances` → 撳你部機
4. 向下 scroll → **`Resources`** → **`Attached VNICs`** → 撳個 VNIC
5. **`IPv4 Addresses`** → 右邊**三點** → **`Edit`**
6. `Public IP Type` → **`No Public IP`** → **Update**
7. **等 30 秒**
8. 再 **`Edit`** → **`Ephemeral Public IP`** → **Update**
9. 返實例主頁，**抄低新 Public IP**

### 然後改客戶端

| App | 點改 |
|---|---|
| **Shadowrocket** | 撳節點 → `地址` 改新 IP → 儲存 |
| **NekoBox** | 長按節點 → `編輯` → `地址` 改新 IP → 儲存 |
| **v2rayN** | 雙擊節點 → `地址` 改新 IP → 確定 |

**兩個節點（REALITY + Hysteria2）都要改。**

---

## 連唔到時嘅判斷次序

```
1. 試 REALITY
   ↓ 唔通
2. 切 Hysteria2                    ← 兩個都唔通先算真係出事
   ↓ 唔通
3. 換手機數據 ↔ WiFi 再試          ← 唔同營運商差好遠
   ↓ 唔通
4. 開 Psiphon / WARP 應急上網
   ↓
5. 用佢登入 Oracle Console 換 IP（上面步驟）
   ↓ 換完仍然唔通
6. 換偽裝目標或端口（需要 SSH — 見下面）
```

### 冇電腦但要 SSH？用 Cloud Shell

Oracle Console 頂部 **`>_`** 圖示 = 瀏覽器版終端機，手機都用得。

```bash
ssh -i ~/.ssh/oracle_vpn ubuntu@新IP
cd vpn && sudo bash scripts/deploy.sh --reality-sni dl.google.com
sudo bash scripts/show-links.sh
```

> 前提：SSH 私鑰係喺 Cloud Shell 入面生成嘅（[README Step 2 路線 B](../README.md#路線-b淨係有手機--用-oracle-cloud-shell)）。若果私鑰只喺你電腦，Cloud Shell 就入唔到部機。
>
> 💡 **建議而家就喺 Cloud Shell 多生成一對金鑰**，加入實例嘅 `authorized_keys`，等你隨時可以純手機 SSH。

---

## 更好嘅長遠做法：用域名

買個平域名（`.xyz` / `.top` 首年幾蚊美金），A 記錄指住 IP，客戶端填域名。

換 IP 之後**只需改 DNS 記錄**，客戶端完全唔使動 —— 手機上快好多。再進一步可以喺伺服器裝自動更新腳本，換 IP 後一分鐘自己恢復。

⚠️ 兩個注意：
- DNS 記錄一定要 **DNS only（灰色雲）**，開咗 Cloudflare CDN proxy 會搞爛 REALITY 握手
- 域名多一重依賴，理論上可被 DNS 污染 —— **客戶端保留一個 IP 版節點做後備**

---

## 最後保險：免費工具

呢三個**要而家就裝好**，斷網時根本落唔到：

| 工具 | 用途 |
|---|---|
| **Psiphon（賽風）** | 主力救生艇，自動輪換協議 |
| **Cloudflare WARP** | 偶爾通，免費 |
| **Tor + Snowflake** | 最慢但最難封死 |

佢哋唔係用嚟日常上網，係用嚟**登入 Oracle Console 救返你個主力方案**。
