## 功能模块介绍

1、main.lua：主程序入口，定义 PROJECT/VERSION，加载网卡和 GB28181 应用，最后调用 `sys.run()`；

2、netdrv_device.lua：网卡选择模块，根据 `gb28181_config.lua` 的 `M.NETDRV` 加载 4G 或 CH390H 驱动；

3、netdrv/netdrv_4g.lua：4G 网卡驱动，使用内核默认的 `socket.LWIP_GP`，订阅并打印 `IP_READY` / `IP_LOSE`；

4、netdrv/netdrv_eth_spi.lua：SPI 外挂 CH390H 以太网驱动，`M.NETDRV = "eth"` 时使用；

5、gb28181_config.lua：集中配置，包括平台 SIP 参数、设备/通道编码、媒体端口、视频源、音频参数和功能开关；

6、gb28181_app.lua：业务主体，完成“等 IP → NTP 对时 → 装载视频源 → 板级音频初始化 → 启动 GB28181 客户端 → 事件循环 → 状态打印”；

7、video_source.lua：视频源，把 annex-b H.264 裸流切成访问单元（AU）并按节拍推流；

8、demo.h264：自带的测试视频（480x360 / 25fps / 8 秒 / 约 109 KB）。

## 系统消息介绍

1、"IP_READY"：某种网卡已经获取到 IP 信息；

2、"IP_LOSE"：某种网卡已经掉网；

3、"NTP_UPDATE"：SNTP 对时完成，demo 用它决定是否打印对时结果。

## 演示功能概述

1、设备上电后通过 4G（默认）或 SPI 外挂 CH390H 以太网接入网络，作为 GB28181 设备端向合宙视频物联网平台（`video.luatos.com`）注册，并按 `KEEPALIVE` 周期发送心跳；

2、应答平台的 Catalog 目录查询，返回 `gb28181_config.lua` 里 `CHANNELS` 定义的通道；

3、平台点播时，把 `/luadb/demo.h264` 切成访问单元后打成 PS/RTP **持续**推流；平台在 INVITE 里给了 `y=<SSRC>` 就沿用平台的 SSRC，没有才自己生成；

4、平台语音广播/对讲时启动音频引擎，双向收发 G.711A。音频走 native 模式：编解码与收发都在 voip 的 C 任务里，Lua 不碰 PCM；

5、每 `STAT_MS`（默认 10 秒）打印一行状态日志，包含注册状态、会话数、音频收发字节和内存水位；

6、接入其它标准 GB28181 平台时，只改 `gb28181_config.lua` 第零节的 6 个 SIP 参数和第一节的设备编码，脚本逻辑不用动。

## 演示硬件环境

1、Air780EHV 核心板/整机一块；

2、TYPE-C USB 数据线一根，用于供电和下载固件/脚本；

3、USB 转串口数据线一根，连接 UART1 查看日志（默认 115200-8-N-1）；

4、4G 测试需要：SIM 卡（或贴片卡）、4G 天线；

5、以太网测试可选：板载 CH390H + 网口的开发板，或核心板 + AirETH_1000 配件板，接线如下：

| Air780EHV 核心板 | AirETH_1000 配件板 |
| --- | --- |
| 3V3 | 3.3v |
| gnd | gnd |
| 86 / SPI0CLK | SCK |
| 83 / SPI0CS | CSS |
| 84 / SPI0MISO | SDO |
| 85 / SPI0MOSI | SDI |
| 22 / GPIO1 | INT |

- 开发板（板载 CH390H）默认参数：**GPIO20 = 供电使能，spi0，片选 GPIO8，中断 GPIO22**；
- 核心板 + AirETH_1000 要把 `netdrv/netdrv_eth_spi.lua` 改成 `pwrpin = nil`、`opts = {spi = 0, cs = 8, irq = 1}`；
- CH390 的 INT 是可选的，没引出中断就去掉 `irq`，驱动退化为轮询，功能不受影响。

6、语音对讲：**Air780EHV** 的 codec（ES8311）在模块内部，PA 常开，直接用 `gb28181_config.lua` 的默认音频参数，不需要外接线。

> 4G 下设备在运营商 NAT 后面，平台主动发起的 INVITE 只能顺着**设备先连出去**的
> TCP 信令进来，所以 `TRANSPORT` 必须是 `"tcp"`（默认值）。若换成只支持 UDP
> 的平台，4G 收不到平台主动发起的点播/对讲 INVITE。

## 演示软件环境

1、Luatools 下载调试工具；

2、**带 GB28181 组件的自定义内核固件**（标准公开发行固件不一定带 GB28181），编译时至少需要：

- `LUAT_USE_GB28181`：GB28181 组件；
- `LUAT_USE_VOIP`：语音对讲（个别固件编号会关掉它，此时对讲不可用，信令和点播不受影响）；
- `LUAT_USE_AUDIO_V2`：对讲音频通路必需；
- `LUAT_USE_NETDRV_CH390H`：仅以太网接线需要（默认打开）。

3、PC 端串口工具（SSCOM、LLCOM 等）；

4、平台侧先建好设备：设备编码与 `gb28181_config.lua` 的 `DEVICE_ID` 一致，传输协议与 `TRANSPORT` 一致（`video.luatos.com` 用 TCP）；

5、Lua 库 `exgb28181client.lua` / `exgb28181audio.lua` / `es8311.lua` 等由固件脚本区里的 `script/libs/` 提供。若下载脚本后报 `module 'exgb28181client' not found`，把本仓库 `script/libs/exgb28181*.lua` 和 `es8311.lua` 一起放进本目录后再下载（Luatools 会把目录内所有文件放进 `/luadb/`）。

## 演示核心步骤

1、按“演示硬件环境”接线，插好 SIM 卡和天线（以太网方案则插好网线）；

2、按需修改 `gb28181_config.lua`：

```lua
M.NETDRV = "4g"   -- "4g" | "eth"
```

- 第零节是平台 SIP 参数，已按 `video.luatos.com` 填好；接其它平台时改 `SERVER_ADDR` / `SERVER_PORT` / `DOMAIN` / `SERVER_ID` / `PASSWORD` / `TRANSPORT` 六项；
- 第一节是设备参数，`DEVICE_ID` / `CHANNEL_ID` 要与平台上的设备记录一致；
- `M.NETDRV` 决定用 4G 还是 CH390H 以太网。

3、用 Luatools 烧录内核固件，再把**整个 demo 目录**下载为脚本（`demo.h264` 才会一起进 `/luadb/`）；

4、上电运行，正常情况下可以看到如下日志：

```text
I/user.netdrv_4g.ip_ready_func IP_READY 10.x.x.x              -- 拿到 IP
I/user.gb28181 网络就绪 10.x.x.x
I/user.gb28181 NTP 同步成功 2026-10-15 10:00:00
I/user.gb28181 视频源就绪 /luadb/demo.h264 访问单元 200 个
I/user.gb28181 平台配置 = luatos video.luatos.com:8116 tcp 设备编码 ... 通道 ...
I/user.gb28181 ★ 注册成功 有效期 3600                          -- ★ 信令通了
```

5、在平台上点「播放」，设备日志出现：

```text
I/user.gb28181 平台请求点播 <call-id> (实时)
I/user.gb28181 ★ 对话已建立，开始推流 <call-id> ssrc 1234567    -- ★ 点播通了
```

6、在平台上点「语音对讲」，设备日志出现：

```text
I/user.gb28181 对讲会话建立 对讲(平台发起)                       -- ★ 对讲通了
I/user.gb28181 注册=true 点播会话=1 对讲会话=1 音频下行=1234 字节 上行=2345 字节 丢=0
```

`音频下行` 和 `上行` 都大于 0，才算双向通。

7、`demo.h264` 是 8 秒循环推，平台上看到同一段画面反复播放属于正常现象；换成真实摄像头时，只需要替换 `video_source` 的取帧来源。

## 常见问题

| 现象 | 先查这些 |
| --- | --- |
| `module 'main' not found` | 脚本区没写进去，重新下载整个目录 |
| `module 'exgb28181client' / 'es8311' not found` | 固件脚本区缺 `script/libs/exgb28181*.lua` 或 `es8311.lua`，见“演示软件环境” |
| Luatools 下载时提示缺少 `gb28181.lua` | 项目里混入了**旧版** gb28181 Lua 库（旧版有 `pcall(require, "gb28181")`）。`gb28181` 是固件注册的 C 全局模块，没有同名 Lua 文件；用 `script/libs/` 下当前的 `exgb28181*.lua` 覆盖旧库即可 |
| `exgb28181sip.lua:88: attempt to call a nil value (field 'build_name_addr')` | 设备上的 `exsipproto.lua` 是旧版，缺 `build_name_addr`。用 `script/libs/exsipproto.lua` 覆盖后重新下载脚本（可用 `grep -n 'function M.build_name_addr' exsipproto.lua` 确认） |
| `module 'netdrv_4g' / 'netdrv_eth_spi' not found` | 下载时没有带上 `netdrv/` 子目录 |
| 没有 `IP_READY`（4G） | SIM 卡是否插好/欠费；天线与信号；专网卡的 APN/DNS |
| 没有 `IP_READY`（以太网） | 网线/DHCP；`pwrpin`/`cs`/`irq` 是否和板子一致；供电是否够 |
| 等 IP 超时 | 看日志里的提示：4G 查 SIM/天线/附着，以太网查网线/DHCP/接线参数 |
| 注册反复 401 | `PASSWORD` 与平台 SIP 密码不一致；`DEVICE_ID` 前 10 位与 `DOMAIN` 不一致 |
| 注册一直没回应 | `SERVER_ADDR`/`SERVER_PORT` 不可达；`TRANSPORT`（UDP/TCP）与平台不一致 |
| 设备在线，点播没画面 | 日志搜“视频源不可用”：`/luadb/demo.h264` 没下载进去，或文件不是 annex-b；`发=N包` 不涨说明媒体链没建起来；`发` 在涨而平台无画面则问题不在设备 |
| 点播 TCP 建不起来 | CH390 网卡的入向 TCP 尚未验证；先用 `nc -vz <设备IP> <端口>` 自证网卡能不能被连进来，或改用 UDP 收流模式 |
| 播放几秒就断 | 不要把 `video_source.next_frame_policy` 的节拍调太大；停推几秒平台会判定流停滞并内部清理而不发 BYE |
| 对讲完全没声 | 查开机日志的 codec 电源/ES8311 初始化；状态行 `jbsil` 每秒 +50、`tx_packets` 100 包/秒说明 I2S 参数没设上 |
| 对讲下行有、上行恒 0 | 引擎建在广播会话上了。等平台发起的 Talk INVITE 自动切换；界面上先点“语音对讲” |
| 对讲一通之后下一通全不通 | 检查 `talk/ended` 和 `call/ended` 是否都处理；本 demo 两个都接了 |
| `注册=false` 反复横跳 | `KEEPALIVE` 不要大于 15 秒（组件判活窗口是 `keepalive + 15s`） |
| 对讲时好时坏 | `RTP_PORT_BASE`（视频，默认 30000）和 `AUDIO_PORT`（对讲，默认 31000）不能重叠 |

## 注意事项

1、用 4G 时，平台要能顺着设备主动建立的 TCP 信令连接把 INVITE 送进来，因此 `TRANSPORT` 必须是 `"tcp"`；

2、局域网之外使用时，平台要能回连设备的媒体端口段 `30000~30003`（点播）与 `31000~31003`（对讲），跨 NAT 时需要放行这一小段；

3、对讲回声与音频参数相关，`AUDIO_OPTS.aec`（AEC/降噪/AGC）按现场调试；固件未编入 `LUAT_USE_VOIP_AEC` 时必须保持 `false`。
