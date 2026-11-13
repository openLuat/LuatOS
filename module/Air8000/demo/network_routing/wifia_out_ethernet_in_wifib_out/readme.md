## 这个 demo 是干什么的

一句话：**把 Air8000 当成一台“WiFi 转网线”的小路由器，并且演示“换一个 WiFi 上网，网线上挂的设备不用重新配网”。**

- Air8000 用 **WiFi STA** 连上一个能上网的路由器（WiFi A），这一个口叫**上游**；
- 别人把网线插到 Air8000 的 **RJ45 网口**（板载 CH390 以太网芯片），这一个口叫**下游**；
- Air8000 在中间做 **NAPT 地址转换 + DNS 代理**，网线那头的设备就能上网，它拿到的网关是 `192.168.5.1`；
- 跑 30 秒后，脚本把上游从 WiFi A 换成 WiFi B，演示“换网不改配置、下游设备 IP 不变”。

> 目录名 `wifia_out_ethernet_in_wifib_out` 是按 `<上游>_out_<接入侧>_in` 的规则起的：
> `wifia_out` = 用 WiFi A 出去，`ethernet_in` = 网口给别人接进来，`wifib_out` = 再换成 WiFi B 出去。

## 网络拓扑

![](https://docs.openluat.com/air8000/luatos/app/image/netdrv_multi.jpg)

```
[WiFi A / WiFi B]  --WiFi STA(adapter 2)-->  [Air8000]  --CH390 网口(adapter 4)-->  [下游设备]
     上游出网                                  NAPT + DNS 代理                    插网线即可上网
```

日志里出现的网卡编号含义（排查时最容易搞混）：

| 编号 | 网卡 | 角色 |
|---|---|---|
| `adapter 2` | `socket.LWIP_STA`（WiFi STA） | 上游，出网口 |
| `adapter 4` | `socket.LWIP_ETH`（CH390 网口） | 下游，LAN 口 |

## 文件说明

本目录下只有 2 个脚本：

1、`main.lua`：主程序入口，只负责 `require "netif_app"` 和启动 `sys.run()`；

2、`netif_app.lua`：网络管理模块，建立多网融合代理并演示上游 WiFi 切换。

**但运行还需要 5 个库文件**，它们不在本目录，位于仓库 `script/libs/`：

| 库文件 | 被谁引用 | 作用 |
|---|---|---|
| `exnetif.lua` | `netif_app.lua` | 多网融合主逻辑 |
| `dnsproxy.lua` | `exnetif.lua` | 给下游设备做 DNS 代理 |
| `dhcpsrv.lua` | `exnetif.lua` | 给下游设备分配 IP |
| `httpdns.lua` | `exnetif.lua` | HTTP DNS 解析 |
| `udpsrv.lua` | `dhcpsrv.lua` | UDP 服务框架 |

用 Luatools 创建工程时会自动带上这些库；**用 `luatos-cli` 手工建项目时必须自己拷进脚本目录**，否则会出现：

```log
E/main exnetif.lua:67: module 'dnsproxy' not found
E/main Lua VM exit!! reboot in 15000ms
```

（这是本 demo 在 Air8000A 上实测踩到的第一个坑。）

## 演示流程

| 阶段 | 动作 | 结果 |
|---|---|---|
| 第一阶段 | `exnetif.setproxy` 建 WiFi A → 以太网代理 | 网口出 `192.168.5.1`，DHCP/DNS 代理/NAPT 全部就绪，并自动开启 WiFi 掉线重连 |
| 等待 | `sys.wait(switch_interval)` | WiFi A 工作 30 秒 |
| 第二阶段 | 再次 `exnetif.setproxy`，只把 SSID 换成 WiFi B | 库检测到凭证变化，自动“关 NAPT → 断旧 WiFi → 连新 WiFi → 重开 NAPT” |

第二次调用时**网卡参数完全没变**（下游还是 `LWIP_ETH`，上游还是 `LWIP_STA`），只有 `ssid/password` 变了。库内部据此判断是“切换上游”而不是“重新初始化”，所以 DHCP 服务器和网口 IP 都不会重建。

## 演示硬件环境

1、Air8000 开发板一块 + WiFi 天线 + 网线一根：

- WiFi 天线拧到开发板的天线座上（接 WiFi/BT 丝印那一路）；
- 网线一端插开发板 RJ45 网口，另一端接**需要联网的以太网设备**（电脑、摄像头、PLC 等）；
- **本 demo 不需要 SIM 卡**，全程走 WiFi 出网，4G 不参与。

2、TYPE-C USB 数据线一根：

- 开发板通过 TYPE-C USB 口供电（外部供电/USB 供电 拨动开关拨到 USB 供电一侧）；
- 另一端接电脑 USB 口，用于烧录和看日志。

## 演示软件环境

1、Luatools 下载调试工具；

2、Air8000 固件：V2044-1 或更新版本（理论上 2025 年 7 月 26 日之后发布的固件都可以），需支持 `netdrv.napt`、`dhcpsrv.create`、`dnsproxy.setup` 等接口；

3、**`script/libs/exnetif.lua` 库版本必须 ≥ `202607211200`，建议 ≥ `202611121939`**。

| 库版本 | 行为差异 |
|---|---|
| `< 202607211200` | 没有“检测凭证变化并切换”的逻辑，第二次调用只会打印 `代理已存在，跳过` |
| `202607211200` | 支持切换，但切换失败仍返回 `true`、切换后掉线重连失效、同 SSID 改密码不切换 |
| `>= 202611121939` | 上述 3 个问题已修复 |

> 判断方法：看启动日志里的 `exnetif 库版本 xxxx`，或直接调用 `exnetif.version()`。

## 演示核心步骤

1、按接线图连接硬件：插好 WiFi 天线、网线接到下游设备、USB 线接电脑；

2、修改 `netif_app.lua` 顶部“用户配置区”的两个表：

```lua
local wifi_a_config = {
    ssid = "WIFI_A_SSID",        -- 改成现场真实 WiFi 名称
    password = "WIFI_A_PASSWORD",-- 改成现场真实 WiFi 密码
}

local wifi_b_config = {
    ssid = "WIFI_B_SSID",
    password = "WIFI_B_PASSWORD",
}
```

3、（可选）修改切换时间，单位毫秒；设为 `nil` 则只建 WiFi A、不演示切换：

```lua
local switch_interval = 30000
```

4、用 Luatools 烧录内核固件和本项目的两个 Lua 脚本（`main.lua`、`netif_app.lua`），并确认项目里的 `exnetif.lua` 是仓库 `script/libs/exnetif.lua` 的最新版本；

5、启动设备，观察日志输出。

## 预期日志

**启动与第一阶段**（Air8000A 实测，IP 随环境变化）：

```log
I/user.netif_app exnetif 库版本 202611121939 （切换功能需 >= 202607211200）
D/ch390h 注册完成 adapter 4 spi 1 cs 12 irq 21
I/user.netdrv 自定义以太网IP地址 nil 网关地址 nil
I/netdrv 设置IP[4] 192.168.5.1 255.255.255.0 0.0.0.0 ret 0
I/netdrv.ch390x link is up 1 12 100M
I/user.netdrv 创建dhcp服务器, 供以太网使用
I/user.netdrv 创建dns代理服务, 供以太网使用
D/netdrv NAPT is enabled gw 2
I/user.exnetif 已启用上游WiFi自动重连
I/user.netif_app 第一阶段成功：WiFi A -> 以太网 代理已建立，WiFi IP 192.168.31.103
I/user.netif_app WiFi A 将工作 30 秒后切换到 WiFi B
```

**下游设备接入**（网线插上后会自动拿地址）：

```log
I/user.dhcpsrv 是discover包 6C1FF7643392 12
I/user.dhcpsrv 分配ip 6C1FF7643392 192.168.5.100
I/user.dhcpsrv send offer
I/user.dhcpsrv request,发现已经分配的mac地址, send ack 6C1FF7643392 12
```

**第二阶段（切换）**：

```log
I/user.setproxy 检测到上游WiFi变化，切换中
I/user.switch_upstream_wifi 关闭NAPT, 断开当前WiFi
I/netdrv.napt 关闭NAPT, 清理所有映射表, 原网关适配器=2
D/airlink wifi sta掉线了
I/user.switch_upstream_wifi 正在连接新WiFi: HH_PC
D/airlink wifi sta上线了
D/DHCP DHCP acquired IP 192.168.137.155
I/user.switch_upstream_wifi NAPT已重新打开, 切换完成
I/user.switch_upstream_wifi 已启用上游WiFi自动重连
I/user.netif_app 第二阶段成功：WiFi B -> 以太网 代理已建立，WiFi IP 192.168.137.155
I/user.netif_app WiFi 切换演示完成，当前使用 WiFi B 提供网络
```

**切换失败时**（`wifi_b_config` 填了不存在的 SSID）：

```log
I/user.setproxy 检测到上游WiFi变化，切换中
I/user.switch_upstream_wifi 正在连接新WiFi: NOT_EXIST_WIFI_9999
[60 秒后]
E/user.switch_upstream_wifi 新WiFi连接超时: NOT_EXIST_WIFI_9999
I/user.switch_upstream_wifi 已恢复原WiFi凭证，自动重连仍有效: HHHHHHHHHHH
E/user.第二阶段失败：无法切换到 WiFi B NOT_EXIST_WIFI_9999
W/user.netif_app 切换失败，先等待 exnetif 自动重连 WiFi A
I/user.switch_upstream_wifi 正在连接新WiFi: HHHHHHHHHHH
I/user.switch_upstream_wifi 新WiFi已连接, IP: 192.168.31.103
I/user.switch_upstream_wifi NAPT已重新打开, 切换完成
I/user.exnetif 上游WiFi重连成功
I/user.netif_app WiFi A 已自动恢复，IP 192.168.31.103
```

这条失败路径是本次修复的重点：原版本这里会打印“第二阶段成功”，且不会重连，只能重启设备。

## 验证方法

下游设备（插网线的电脑/摄像头）能正常打开网页、能 ping 通外网，就说明代理链路通了。

在电脑上看一眼网络配置，应该是：

- IP：`192.168.5.x`（由 Air8000 的 DHCP 分配）
- 网关：`192.168.5.1`（Air8000 网口地址）
- DNS：`192.168.5.1`（Air8000 的 DNS 代理）

切换上游 WiFi 后，这三项**都不会变**。

## 注意事项

1、**切换会断开下游已建立的 TCP 连接**。切换时要先关 NAPT 并清理映射表，所以下游设备上正在跑的下载、长连接、MQTT 会话都会断，需要重连。它保证的是“IP 不变、不用重新 DHCP”，不是“连接不断”。

2、**切换失败时 `setproxy` 返回什么，取决于库版本**。`202611121939` 之前无论成败都返回 `true`（返回值没有向上传递），之后正确返回 `false`。所以本 demo 不把返回值当作唯一依据，每次调用后都再用 `netdrv.ipv4(socket.LWIP_STA)` 复核是否真的拿到了 IP。二次开发时建议照抄这个判断方式。

3、**切换失败后的自动恢复，同样取决于库版本**。`202611121939` 之前，`switch_upstream_wifi` 一进入就把内部 `wifi_config` 清空且失败时不恢复，导致 `on_proxy_sta_ip_lose` 里的重连判断直接 return，**自动重连永久失效**；之后版本会恢复原凭证，由 `IP_LOSE` 自动重连 WiFi A。

   本 demo 的处理是：失败后先等 10 秒，看库能否自愈，不行再用 `wlan.connect` 手动回退。手动回退只保证 WiFi A 重新通网；如果库内部 `wifi_config` 仍为空，“掉线自动重连”要重启设备才能恢复。

4、**同一 SSID 只改密码，需要库 ≥ `202611121939` 才会触发切换**。旧库只比较 `ssid`，密码变了但 SSID 没变时不会重连，会一直用旧密码失败；新库已改为 `ssid` 或 `password` 任一变化都触发切换。

5、`PROJECT` 名为 `wifia_out_ethernet_in_wifib_out`，共 31 个字符。如果后续要接入 `iot.openluat.com` 做远程升级，注意项目名不要超过平台的长度限制，二次开发时也不建议再加长。

## 常见问题

**Q：日志打印“当前 exnetif 库不支持自动切换上游 WiFi，跳过第二阶段”**
A：`exnetif.lua` 版本太旧（< `202607211200`），换成仓库 `script/libs/exnetif.lua` 最新版。

**Q：日志打印“setproxy 代理已存在，跳过”，没有切换**
A：同上，库版本太旧。旧版本没有“检测凭证变化”的逻辑，第二次调用会被当成重复调用直接返回。

**Q：只改了 WiFi 密码、没换 SSID，设备一直连不上**
A：库 `< 202611121939` 只比较 SSID，密码变了不会触发重连，会一直用旧密码。升级库即可，或临时把 SSID 也改一下 / 重启设备。

**Q：日志打印“wifi_a_config 与 wifi_b_config 的 ssid 相同，无法演示切换”**
A：两个配置表填了同一个 WiFi。这个 demo 必须准备两个可用的 WiFi（手机热点也算一个）。

**Q：第一阶段就失败，提示“WiFi A 初始化失败”**
A：先确认 `wifi_a_config` 的 SSID/密码正确、路由器没有开启 MAC 地址过滤或隐藏 SSID；再确认网线插在 Air8000 的 RJ45 口，而不是电脑的网口。

**Q：网口灯不亮，日志没有 `link is up`**
A：CH390 供电没起来。检查 `eth_config.ethpower_en = 140` 是否与实际板子一致，以及开发板是否被识别为 Air8000（不是 Air8000A 等其他型号）。

**Q：下游设备能拿到 IP，但打不开网页**
A：DNS 代理没生效。看日志里有没有 `创建dns代理服务` 和 `NAPT is enabled gw 2`，若 `gw` 不是 2，说明上游网卡选错了。
