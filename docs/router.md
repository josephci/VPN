# OpenWrt 旁路由 + 雙 SSID（全屋走代理）

俾屋企人用 —— **佢哋唔使裝任何 app**，切個 WiFi 就得。

---

## 架構

```
光貓 / 主路由（唔郁佢）
   │
   └── OpenWrt 旁路由
         ├── SSID「Home-WiFi」    → 192.168.1.x  直連（預設用呢個）
         └── SSID「Home-WiFi-X」  → 192.168.9.x  走代理
                                        │
                                   sing-box (TUN)
                                        │  分流：內地直連、外網走隧道
                                        ▼
                                   你部 Oracle 機
```

**點解要雙 SSID 而唔係全屋走代理：**

- ✅ **opt-in** — 平時上淘寶、微信、銀行 app 行正常 WiFi，唔會因為 IP 地區異常而被風控
- ✅ **速度** — 內地網站唔使繞去日本再返嚟
- ✅ **風險低** — 唔會全屋流量 24 小時經同一條隧道
- ✅ **家人唔使學嘢** — 「上唔到 Google 就轉去嗰個 WiFi」，一句講完
- ✅ **壞咗唔會斷曬** — 主路由完全冇改動

---

## ⚠️ 先講風險

| | |
|---|---|
| **流量特徵** | 路由器係 24 小時在線、流量大、全部去同一個外國 IP。比一部手機間歇性連線突出好多 |
| **實名制** | 內地寬頻登記喺真人名下 |
| **家人唔知情** | 有人做咗引起注意嘅事，追返嚟都係你條線 |
| **法律** | 個人自用屬灰色地帶，實務上針對個人嘅執法罕見；**但「經營／轉賣」有實際判刑案例** |

**呢啲措施實質降低風險：**

1. **一定要開分流**（本文檔預設已開）—— 只有外網走隧道，流量量級同特徵都低好多
2. **雙 SSID，唔好全屋預設走代理** —— 用嗰陣先切
3. **唔好分享出屋企以外** —— 呢個就係「自用」同「經營」嘅界線

> 💡 **如果只係你同伴侶要用，唔值得搞呢套。** 手機裝 client 就夠。呢套係為咗「屋企人裝唔到 / 唔想教」而設。

---

## 硬件

> **🔴 唔好刷你部主路由。** 刷壞咗全屋即刻斷網，而你連上網去查點救都冇。旁路由嘅整個意義就係「出事拔咗插頭就恢復正常」。

### 🔴 雙 SSID 需要有 WiFi 嘅機

**大部分 N100 軟路由冇 WiFi** —— 冇 WiFi 就做唔到雙 SSID，架構要退化成「每部裝置手動設定閘道」，即係家人第一次要有人幫手設定。如果目標係「屋企人唔使學嘢」，就一定要揀有 WiFi 嗰種。

### 推薦：GL.iNet（原生 OpenWrt，唔使刷）

出廠就係跑真正嘅 OpenWrt，唔使刷、唔使解鎖、冇變磚風險，有 WiFi。

| 型號 | 價錢 | RAM | 評價 |
|---|---|---|---|
| **GL-MT3000（Beryl AX）** | 約 ¥400 | 512MB | ⭐ **最推薦** — 性價比最好，WiFi 6 |
| GL-AXT1800（Slate AX） | 約 ¥500 | 512MB | 差唔多，多幾個口 |
| GL-MT6000（Flint 2） | 約 ¥900 | 1GB | 過剩，除非想佢做主路由 |

買原廠固件就得，底層就係 OpenWrt，LuCI 開得到，本文檔啲 `uci` 指令照用。

### 手頭有閒置舊路由器？

小米／紅米可刷 OpenWrt 而且 RAM 夠嘅型號：

| 型號 | RAM | |
|---|---|---|
| Redmi AX6S / 小米 AX3200 | 256MB | ✅ 夠用 |
| 小米 AX3600 | 512MB | ✅ 好，但刷機較煩 |
| 小米 4A 千兆版、Redmi AC2100 | **128MB** | ⚠️ 太細，sing-box + rule-set 唔夠用 |

⚠️ 新型號好多鎖死咗 bootloader 刷唔到，而且**刷機有變磚風險**。

### 冇 WiFi 嘅選擇（要放棄雙 SSID）

| | 價錢 | |
|---|---|---|
| N100 軟路由 | ¥400–700 | 性能最好，但要每部裝置手動設閘道 |
| 樹莓派 4/5 | ¥400+ | 同上，慳電 |

> ⚠️ **唔好買標榜「內置翻牆」嘅現成機**。你唔知入面跑緊咩、有冇後門，而且嗰啲固件多數用緊落後協議。

> 價錢會變，落單前自己核實。

---

## Step 1：喺伺服器生成 config

```bash
cd ~/vpn && git pull
sudo bash scripts/gen-client.sh
```

會喺 `/tmp/router/` 出四個檔：

| 檔案 | 用途 |
|---|---|
| `config.json` | sing-box client 設定（UUID、公鑰已填好）|
| `geoip-cn.srs` | 中國 IP 段（分流用）|
| `geosite-cn.srs` | 中國域名（分流用）|
| `openwrt-setup.sh` | 路由器上跑嘅設定腳本 |

想改網段：`sudo bash scripts/gen-client.sh --subnet 192.168.9.0/24`

> 💡 **rule-set 用本地檔而唔係 remote**，係刻意嘅：`remote` 要經代理落載，即係「隧道未通就開唔到機」；而喺內地行 direct 落 GitHub 又唔穩定。本地檔冇呢個開機依賴。

---

## Step 2：路由器裝 sing-box

SSH 入 OpenWrt（預設 `root@192.168.1.1`）：

```sh
opkg update
opkg install sing-box
```

**如果 opkg 冇 sing-box**（舊版本或者精簡固件），落官方 binary：

```sh
# 先睇架構
opkg print-architecture
# 常見：x86_64 / aarch64_cortex-a53 / mipsel_24kc

cd /tmp
VER=1.13.16
ARCH=amd64        # x86_64→amd64、aarch64→arm64、mipsel→mipsle
wget -O sb.tgz "https://github.com/SagerNet/sing-box/releases/download/v${VER}/sing-box-${VER}-linux-${ARCH}.tar.gz"
tar xzf sb.tgz
install -m755 sing-box-*/sing-box /usr/bin/sing-box
sing-box version
```

⚠️ 呢步要路由器本身上到 GitHub。內地嘅話可能要先用手機熱點，或者喺伺服器落好再 `scp` 過去。

---

## Step 3：放檔案 + 跑設定腳本

喺**你部電腦**（唔係伺服器、唔係路由器）：

```bash
# 先由伺服器拉落嚟
scp -i ~/.ssh/oracle_vpn ubuntu@伺服器IP:/tmp/router/* ./router/

# 再推上路由器
ssh root@192.168.1.1 'mkdir -p /etc/sing-box'
scp ./router/config.json ./router/*.srs root@192.168.1.1:/etc/sing-box/
scp ./router/openwrt-setup.sh root@192.168.1.1:/tmp/
```

然後喺路由器上：

```sh
sh /tmp/openwrt-setup.sh
```

腳本會：驗證 config → 安裝 `/etc/init.d/singbox`（開機自啟）→ 啟動 → 設定 policy routing → 寫入 `rc.local` 令重開機都保持。

確認：

```sh
ip link show singbox        # 應該見到 tun 介面
ip rule show | grep 192.168.9
logread -e sing-box | tail
```

---

## Step 4：建立第二個網段同 SSID

以下係 UCI 指令。**`Home-WiFi-X` 同密碼記得改做你自己嘅。**

### 4a. 新網段

```sh
uci set network.proxynet=interface
uci set network.proxynet.proto='static'
uci set network.proxynet.ipaddr='192.168.9.1'
uci set network.proxynet.netmask='255.255.255.0'

# 註冊 tun 介面，等防火牆管得到佢
uci set network.singbox=interface
uci set network.singbox.proto='none'
uci set network.singbox.device='singbox'

uci commit network
```

### 4b. DHCP（關鍵：DNS 同 IPv6）

```sh
uci set dhcp.proxynet=dhcp
uci set dhcp.proxynet.interface='proxynet'
uci set dhcp.proxynet.start='100'
uci set dhcp.proxynet.limit='100'
uci set dhcp.proxynet.leasetime='12h'

# 派 1.1.1.1 做 DNS —— 呢啲查詢會經 policy route 入 tun，
# 由 sing-box 嘅 hijack-dns 接住，再按分流規則解析
uci add_list dhcp.proxynet.dhcp_option='6,1.1.1.1'

# 🔴 一定要關 IPv6，唔係會繞過代理直接洩漏出去
uci set dhcp.proxynet.dhcpv6='disabled'
uci set dhcp.proxynet.ra='disabled'

uci commit dhcp
```

> **🔴 IPv6 洩漏係最容易中招嘅位。** policy routing 只處理 IPv4，如果客戶端攞到 IPv6 位址，佢會直接經 IPv6 出去，完全繞過代理 —— 你以為通緊代理，其實冇。

### 4c. 第二個 SSID

```sh
uci add wireless wifi-iface
uci set wireless.@wifi-iface[-1].device='radio0'      # 2.4G；5G 通常係 radio1
uci set wireless.@wifi-iface[-1].mode='ap'
uci set wireless.@wifi-iface[-1].network='proxynet'
uci set wireless.@wifi-iface[-1].ssid='Home-WiFi-X'
uci set wireless.@wifi-iface[-1].encryption='psk2'
uci set wireless.@wifi-iface[-1].key='改做你嘅密碼'
uci commit wireless
```

### 4d. 防火牆

```sh
uci add firewall zone
uci set firewall.@zone[-1].name='proxyzone'
uci add_list firewall.@zone[-1].network='proxynet'
uci add_list firewall.@zone[-1].network='singbox'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='proxyzone'
uci set firewall.@forwarding[-1].dest='wan'

uci commit firewall
```

### 4e. 套用

```sh
/etc/init.d/network restart
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart
wifi reload
/usr/bin/singbox-route      # 網絡重啟後要重新加 policy route
```

---

## 驗證

**手機連去 `Home-WiFi-X`：**

| 測試 | 預期 |
|---|---|
| 開 https://ip.sb | 顯示**日本 IP** ✅ |
| 開 https://www.baidu.com | 秒開（行直連）✅ |
| 開 https://test-ipv6.com | **唔應該有 IPv6** ✅ |

**連去 `Home-WiFi`（正常嗰個）：**
- ip.sb 應該顯示你屋企 IP
- Google 上唔到（正常，證明兩個網分開咗）

**喺路由器睇：**

```sh
logread -e sing-box | tail -20
ip rule show
```

---

## 排錯

### 連到 X SSID 但完全冇網

```sh
ip link show singbox              # tun 有冇建立
ip rule show | grep 192.168.9     # policy route 有冇
logread -e sing-box | tail -30    # sing-box 有冇報錯
```

最常見：**網絡重啟之後 policy route 冇咗** → 行 `/usr/bin/singbox-route`

### 上到內地網站但上唔到外網

隧道有問題。喺路由器直接測：

```sh
sing-box check -c /etc/sing-box/config.json
logread -e sing-box | grep -i error
```

再返伺服器行 `sudo bash scripts/selftest.sh` 確認伺服器側正常。

### ip.sb 顯示屋企 IP（代理冇生效）

- 確認你真係連緊 `Home-WiFi-X` 而唔係另一個
- 睇下部機攞到嘅 IP 係咪 `192.168.9.x`
- **查 IPv6 洩漏** — 開 test-ipv6.com，有 IPv6 就代表 4b 嗰兩行冇生效

### 內地網站好慢

分流冇生效，全部走咗代理。確認 `/etc/sing-box/*.srs` 兩個檔存在而且唔係 0 bytes。

### 路由器記憶體不足

`free` 睇下。128MB 機跑 sing-box + rule-set 好緊張，考慮換硬件。

---

## 維護

**更新分流規則**（建議兩三個月一次，內地 IP 段會變）：

```bash
# 伺服器上
sudo bash scripts/gen-client.sh
# 再 scp 兩個 .srs 落路由器，然後
ssh root@192.168.1.1 '/etc/init.d/singbox restart && /usr/bin/singbox-route'
```

**伺服器換咗 IP** → 重新跑 `gen-client.sh`，推新 `config.json` 落去，重啟。

**臨時停用**：

```sh
/etc/init.d/singbox stop
ip rule del from 192.168.9.0/24 lookup 100
```

X SSID 就會變成冇網（唔會 fallback 直連，呢個係刻意嘅 —— 免得你以為通緊代理其實冇）。

---

## 已驗證同未驗證

- ✅ **sing-box client config** —— 喺 sing-box **1.13.16** 上 `check` 通過、實際啟動成功，包括**伺服器連唔到嗰陣一樣起得到**（本地 rule-set，冇開機依賴）
- ✅ **生成腳本** —— 三層產出（config、openwrt-setup.sh、singbox-route）語法同變數展開都驗證過
- ⚠️ **OpenWrt 嘅 UCI 指令未經實機測試**（呢邊冇 OpenWrt 環境）。不同版本嘅語法有差異，特別係 **21.02 之前用 iptables、22.03+ 用 nftables**，同埋 DSA 架構嘅 bridge 寫法。跑之前建議先 `uci show network` 睇下你嗰部嘅現有結構。
