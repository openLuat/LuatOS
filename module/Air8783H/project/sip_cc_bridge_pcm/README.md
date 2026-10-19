# Air8783H SIP / CC 纯 PCM 桥接通话 Demo

本 Demo 演示将 SIP 网络通话与模组 SIM 卡的蜂窝语音通话（CC，Call Control）双向桥接。两侧语音在模组内部通过 PCM 数据流传递，无需外接音频 Codec 芯片，也无需连接开发板上的麦克风、喇叭或音频回环线。通话人员分别使用 SIP 客户端和手机收听、讲话。

“纯 PCM”指模组内部的音频桥接方式。SIP 网络侧仍通过 RTP 传输 PCMA、PCMU、G729 或 G722 编码的语音，需由固件完成编解码；本 Demo 仍需要真实模组和支持语音业务的 SIM 卡。

## 1. 功能与通话路径

支持以下两种演示方式：

- **SIP 来电转手机**：SIP 客户端呼叫模组注册的 SIP 账号，模组拨打 `target_phone_number`，手机接听后建立桥接。
- **手机来电转 SIP**：手机拨打模组 SIM 卡号码，模组呼叫 `remote_sip_uri`，SIP 对端接听后模组接听蜂窝来电并建立桥接。

```text
SIP 客户端 <-- SIP 信令 / RTP --> SIP 服务器与模组
                                      |
                              VoIP 编解码 / PCM
                                      |
                              内部双向 PCM 桥接
                                      |
                                 CC / VoLTE
                                      |
                                     手机
```

每次只桥接一通电话。任一侧挂断后，应用联动结束另一侧通话并释放媒体资源；新的呼叫需等待旧通话清理完成。默认 PCMA/PCMU 通话接通后还会向两端播放一次本地 MP3，播放结束后恢复双向讲话。

## 2. 演示环境

| 项目 | 要求 |
| --- | --- |
| 模组 / 开发板 | Air8783H 项目对应的硬件，接好供电、蜂窝天线和调试下载接口 |
| SIM 卡 | 已开通语音与 VoLTE，能够正常呼入、呼出；使用 4G 承载 SIP 时还需可用的数据业务 |
| 配套固件 | 适配该硬件，包含 CC 纯 PCM 后端、VoIP PCM 桥接、所选 SIP 编解码器及远端播报能力 |
| SIP 服务 | 可供模组和 SIP 客户端注册、呼叫的 SIP 服务器，提供模组账号和对端账号 |
| SIP 通话端 | 能与服务器互通的 SIP 客户端，带麦克风和扬声器 / 耳机 |
| 蜂窝通话端 | 一部可正常拨打、接听电话的手机 |
| 下载与日志 | 电脑、Luatools、可用的下载连接和运行日志通道 |

默认使用 **4G 网络承载 SIP**。目录中也提供 Wi-Fi STA 驱动；切换前需确认目标硬件和固件支持该功能。使用 Wi-Fi 只改变 SIP 联网方式，蜂窝通话仍需要 SIM 卡和 VoLTE。

固件需提供以下能力，不能只通过添加 Lua 脚本补齐：

- CC：`cc.AUDIO_MODE_BRIDGE_PCM`、`cc.bridgePcmStats()`、`cc.bridgeAudioStop()`，以及底层 PCM 接收与上传支持。
- VoIP：`voip.AUDIO_MODE_BRIDGE`、`voip.setAudioMode()`、`voip.pcmIn()`、`voip.pcmOut()`，以及 `voip.start()` 等媒体接口。
- 默认播报：`voip.on("play", ...)`、`voip.playFile()`、`voip.playStop()`、`voip.playStatus()`、`voip.bridgeMute()`；切换 TTS 时还需 `voip.playTTS()` 和配套 TTS 能力。
- 基础库：`sys`、`socket`、`crypto`、`zbuff`、`mcu.ticks2()` 等；TLS 模式还需 TLS 与网络校时支持。

本目录未指定可直接下载的 Air8783H 固件文件名或最低版本号，应以配套固件是否包含上述能力为准。脚本中部分注释沿用 Air8000 命名，不代表可以混用其他型号固件。

## 3. 文件说明与烧录清单

```text
sip_cc_bridge_pcm/
├── main.lua                    # 应用入口，当前版本 1.1.9
├── netdrv/
│   ├── netdrv_device.lua        # 选择 4G / Wi-Fi 联网
│   ├── netdrv_4g.lua            # 4G 网络事件与 DNS 设置
│   └── netdrv_wifi.lua          # Wi-Fi STA 配置
├── sip_cc/
│   ├── config.lua              # SIP 账号、目标号码、codec 与检测参数
│   ├── sip_cc_app.lua          # 等待网络，依次初始化 CC、SIP
│   ├── cc_main.lua             # 蜂窝呼叫、PCM 就绪与异常检测
│   ├── sip_main.lua            # SIP 呼叫控制
│   ├── pcm_sip.lua             # SIP 信令与 VoIP PCM 媒体适配
│   └── bridge.lua              # 双向呼叫协调、挂断联动和远端播报
├── Time_travel_8k.mp3           # 默认接通播报资源
├── sip-ca.pem                  # TLS 模式可用的 CA 证书资源
└── README.md
```

在 Luatools 新建脚本项目，选择适配硬件的配套固件，并加入：

1. 本目录全部 **10 个 `.lua` 文件**：`main.lua`、`netdrv/` 下 3 个、`sip_cc/` 下 6 个。
2. 当前仓库 `script/libs/` 中的 `exsipclient.lua`、`exsipproto.lua`。
3. 启用 Wi-Fi 时，另加 `script/libs/` 中的 `exnetif.lua`、`dnsproxy.lua`、`dhcpsrv.lua`、`httpdns.lua`、`udpsrv.lua`。仅使用 4G 时运行中不加载这些库；统一添加上述 10 个 Demo 脚本时，也可一并添加这 5 个依赖，便于切换网络和打包检查。
4. 默认播报使用的 `Time_travel_8k.mp3`，保留文件名，板端路径为 `/luadb/Time_travel_8k.mp3`。
5. 使用 TLS 时，加入与实际 SIP 服务器证书链匹配的 CA 文件，详见后文。

子目录中的 Lua 脚本需保留原文件名，使 `require "config"`、`require "netdrv_device"` 等可以直接加载。入口为 `main.lua`。清理 Luatools 项目中其他 Demo 的同名脚本条目，避免烧录到旧版 `config.lua`、`bridge.lua` 或 `pcm_sip.lua`。本 Demo 使用自己的 `pcm_sip.lua`，不需要额外添加普通 SIP Demo 的 `exsip.lua` 或本地音频 Codec 驱动。

## 4. 修改配置

### 4.1 SIP 账号与拨号目标

编辑 [sip_cc/config.lua](sip_cc/config.lua)，把示例占位值替换为实际环境参数：

```lua
sip_server_addr = "sip.example.com",                -- 服务器地址或 IP
sip_server_port = 5060,                            -- 按服务器监听端口填写
sip_domain = "sip.example.com",                    -- SIP 账号所属域
sip_transport = "udp",                            -- udp / tcp / tls
sip_username = "YOUR_SIP_USERNAME",                -- 模组注册的账号
sip_password = "YOUR_SIP_PASSWORD",                -- 该账号的密码
remote_sip_uri = "sip:REMOTE_USER@sip.example.com", -- 手机来电时呼叫的 SIP 对端
target_phone_number = "YOUR_PHONE_NUMBER",         -- SIP 来电时拨打的手机号
rtp_port = 40000,
codec = "PCMA",
ptime = 20,
adapter = socket.LWIP_GP,
auto_answer_sip = true,
auto_handle_mobile_incoming = true,
```

以上为现有配置表内字段的示意，修改原文件对应项即可。`sip_username` 是模组账号，`remote_sip_uri` 是另一个通话端的地址，两者用途不同。`target_phone_number` 是固定蜂窝拨号目标，当前脚本不会从 SIP 来电 URI 中提取号码进行动态拨号。

演示双向自动桥接时，保留两个自动处理开关为 `true`。`auto_answer_sip` 控制 SIP 来电后的自动桥接流程，最终应答在 CC 接通且 PCM 就绪后完成；`auto_handle_mobile_incoming` 控制蜂窝来电后的 SIP 外呼流程。将其设为 `false` 不会自动提供交互式接听界面。

SIP 服务器、客户端和模组需允许协商出的 RTP 地址及端口双向可达。若注册正常但无声，需继续检查媒体路径，不能只检查 SIP 信令端口。

### 4.2 网络选择

默认 [netdrv/netdrv_device.lua](netdrv/netdrv_device.lua) 为：

```lua
require "netdrv_4g"
-- require "netdrv_wifi"
```

对应 `config.lua` 中 `adapter = socket.LWIP_GP`。

若目标硬件支持 Wi-Fi STA，切换为：

```lua
-- require "netdrv_4g"
require "netdrv_wifi"
```

同时将 `config.lua` 的 `adapter` 改为 `socket.LWIP_STA`，并在 `netdrv/netdrv_wifi.lua` 中填写实际 `ssid`、`password`。该驱动按 2.4 GHz Wi-Fi 配置，公共依赖见烧录清单。两种驱动只启用一种，网卡选择与 `adapter` 必须一致。

两个驱动都在获取 IP 后设置了公共 DNS。使用专网卡或其他不适用这些 DNS 的网络时，应按实际网络要求调整对应驱动的 `socket.setDNS()` 配置。

### 4.3 SIP 编解码与 PCM 参数

| `codec` | SIP 媒体侧 PCM 采样率 | `ptime` | 接通后自动播报 |
| --- | --- | --- | --- |
| `PCMA`（默认） | 8000 Hz | 20 ms | 播放 MP3，或按配置播放 TTS |
| `PCMU` | 8000 Hz | 20 ms | 播放 MP3，或按配置播放 TTS |
| `G729` | 8000 Hz | 20 ms | 当前脚本跳过播报 |
| `G722` | 16000 Hz | 20 ms | 当前脚本跳过播报 |

PCM 为 16 位有符号小端、单声道。G722 的 SIP 媒体与 CC 通道之间需要固件提供相应的采样率转换；SDP 中的 `G722/8000` 表示 RTP 时钟为 8000 Hz，其媒体 PCM 仍为 16000 Hz。选择某个 codec 前，需确认固件、SIP 服务器与客户端都支持它；无需外接硬件 Codec，但仍需固件中的语音编解码实现。

`ptime` 固定为 `20`，其他值会导致初始化失败。当前 `sip_main.lua` 实际传入的是 `codecs = {config.codec}`，因此通过 `codec` 单选编解码器；仅取消 `config.lua` 中 `codecs` 列表的注释不会启用多编解码器协商。

### 4.4 接通播报

默认 [sip_cc/bridge.lua](sip_cc/bridge.lua) 配置为：

```lua
local CALL_NOTICE_TARGET = "both"
local CALL_NOTICE_TEXT = "通话已建立，本段进行TTS播报测试"
local CALL_NOTICE_FILE = "/luadb/Time_travel_8k.mp3"
local CALL_NOTICE_DELAY_MS = 500
```

PCMA/PCMU 通话的 SIP 和 CC 两侧都接通、媒体就绪后，应用先静音原双向桥接语音，等待 500 ms，再以 `mode = "replace"` 播放一次文件。两端听到播报后，等待 `双向桥接语音已恢复` 日志，再验证互相讲话；静音覆盖播报前的延时和播放阶段。

- `CALL_NOTICE_TARGET` 可选 `"sip"`、`"cc"`、`"both"`，控制播报送达哪一端。
- 将 `CALL_NOTICE_FILE` 设为 `nil`，改用 `CALL_NOTICE_TEXT` 进行 TTS 播报，固件需具备对应 TTS 能力。
- 更换文件时，同步修改板端路径并烧录资源。板端路径使用 `/luadb/...`，不能填电脑上的 `E:\...` 路径。
- `CALL_NOTICE_DELAY_MS = 0` 表示立即播报；当前没有独立的“关闭播报”配置开关。
- G729/G722 通话按当前脚本直接跳过 TTS / 文件播报。

## 5. 运行与演示步骤

### 5.1 烧录与启动确认

1. 插入 SIM 卡，接好天线、供电和下载线。
2. 完成上述账号、目标号码、网络和 codec 配置，将配套固件、脚本及默认 MP3 资源烧录到模组。
3. 重启，打开 Luatools 运行日志，确认出现以下关键内容：

```text
main              SIP_CC_BRIDGE_PCM 1.1.9
pcm_sip           media revision 1.1.9-g729-asmb-rodata
netdrv_4g...      IP_READY ...
cc_main           CC 初始化完成 bridge_pcm
sip_cc_app        SIP/CC 桥接应用启动成功 bridge_pcm
sip_main          event register ok
```

以上为日志关键内容示意，实际前缀和时序以运行为准；Wi-Fi 模式观察 `netdrv_wifi` 的 `IP_READY`。`SIP/CC 桥接应用启动成功` 表示初始化完成，还需看到 `event register ok` 才表示 SIP 注册成功。

应用启动时最多等待 10 秒网络就绪，超时会打印 `等待网络超时，继续初始化 SIP`。遇到该日志应继续检查 IP 获取和后续注册结果。

### 5.2 SIP 来电转手机

1. SIP 客户端使用对端账号登录同一套可互通的 SIP 服务。
2. 在 SIP 客户端呼叫模组的 `sip_username`，或由服务器路由到该账号的 SIP URI。
3. 模组先发送带 SDP 的 `183`，确认 SIP 早期媒体与 VoIP 启动后，拨打 `target_phone_number`。此时可观察 `183 和 VoIP started 已确认，拨打手机` 日志。
4. 目标手机接听。CC 接通且 PCM 就绪后，模组正式应答 SIP 来电；日志出现 `CC 已接通且 PCM 通道就绪`。
5. 默认 PCMA/PCMU 模式下先验证两端收到 MP3，再等待恢复语音；随后分别从 SIP 端和手机端讲话，验证双向声音。
6. 任一侧挂断，确认另一侧结束通话，再发起下一通。

### 5.3 手机来电转 SIP

1. 手机拨打模组 SIM 卡的电话号码。
2. 模组收到蜂窝来电后呼叫 `remote_sip_uri`，可观察 `手机来电，等待桥接可用` 和 `呼入场景：拨打 SIP` 日志。
3. SIP 对端接听、SIP 媒体就绪后，模组再接听蜂窝来电。
4. 按当前 codec 的播报行为完成验证，然后检查双方讲话与挂断联动。

这两种流程都由来电触发；程序启动后不会立即自动拨打配置中的号码。

## 6. PCM 异常检测与日志

`config.lua` 中默认检测参数如下：

| 参数 | 默认值 | 作用 |
| --- | --- | --- |
| `cc_audio_start_timeout_ms` | `3000` | CC 接通后 PCM 通道等待超时；超时会结束本次桥接 |
| `cc_media_min_connected_ms` | `2000` | 当前接通媒体阶段至少持续此时长，才可能计入缺少真实 PCM 的异常；小于等于 0 关闭该检测 |
| `cc_media_missing_call_limit` | `3` | 连续达到此次数的有效检测通话都没有真实 CC 下行 PCM 增量时，上报异常；小于等于 0 关闭该检测 |
| `cc_media_reboot_on_error` | `true` | 检测到 `NO_MODEM_PCM` 异常后清理并重启恢复；设为 `false` 时保留异常上报，不自动重启 |

检测依据为本次真实接通媒体阶段 `cc.bridgePcmStats().dl_pushed` 的增量，早期媒体或上传静音不能代替该数据。统计未知的通话不会计入连续异常。

通话中还会输出 `RTP stats`、`RTP rate`、`codec timing` 和 `CC PCM stats`。双向通话时关注 RTP 收发计数是否持续增加；PCM 故障时结合 `PCM 故障快照`、`PCM 上传快照` 定位。听到本地文件播报只能证明对应播报路径可用，仍需完成双方讲话测试。

## 7. 常见问题

| 现象 / 日志 | 检查项 |
| --- | --- |
| 找不到 `config`、`netdrv_device`、`exsipproto` 等模块 | 是否按烧录清单加入脚本，子目录脚本是否保留文件名，公共库是否来自当前仓库 |
| `cc_unavailable`、`firmware_missing_bridge_pcm`、`firmware_missing_pcm_stats:...` | 配套固件是否包含 CC 纯 PCM 能力和所需统计字段 |
| `firmware_missing_voip_bridge`、`firmware_missing_voip_...` | 固件是否提供 VoIP 桥接及所选 codec；仅更改 Lua 配置不能增加底层能力 |
| `bridge_requires_20ms` | `ptime` 必须为数值 `20` |
| 没有 `IP_READY` 或 SIP 一直未注册 | SIM 数据 / Wi-Fi、网卡与 `adapter`、DNS、服务器地址、端口、transport 和账号参数 |
| SIP 已注册但呼叫不通 | SIP 服务器路由、对端是否在线、两个自动处理开关及固定目标号码是否正确 |
| 蜂窝拨号失败或一直不能接通 | SIM 语音与 VoLTE、蜂窝信号、号码格式、SIM 是否能正常呼入呼出 |
| SIP 来电后手机未响铃 | 是否完成 `183` 和 VoIP 媒体启动；检查双方 codec / SDP、媒体启动错误和 CC 拨号日志 |
| `CC 音频通道启动超时` | CC 已报告接通但 PCM 未就绪；检查配套固件、底层 PCM 支持及故障快照 |
| MP3 未播放或 `远端音频提交失败` | 资源是否烧录为 `/luadb/Time_travel_8k.mp3`、固件播报能力、两侧媒体是否就绪；G729/G722 跳过播报为当前设计 |
| 刚接通时双方讲话听不到 | 默认播报前延时和播放阶段会静音桥接语音；观察播报结束与恢复日志 |
| 注册成功但单向 / 双向无声 | RTP 地址、端口、网络可达性、收发计数、CC PCM 状态，以及播报是否结束 |
| 出现 `CC_BRIDGE_MEDIA_ANOMALY NO_MODEM_PCM` 后重启 | 默认连续缺少真实下行 PCM 的恢复机制触发；查看统计，调试时可关闭自动重启保留现场日志 |
| `Busy Here` 或短时间重拨失败 | 当前只支持单通桥接；等待旧通话和媒体释放后重试 |

## 8. 可选：TLS 信令

需要 TLS 时，在 `sip_cc/config.lua` 中修改对应项，例如：

```lua
sip_transport = "tls",
sip_server_port = 5061, -- 示例，按服务器实际 TLS 监听端口填写
sip_tls = {ca_cert = io.readFile("/luadb/sip-ca.pem")},
media_encryption = "none",
```

将与服务器证书链匹配的 CA 证书以 `sip-ca.pem` 文件名烧录，确保板端路径与配置一致。本目录附带的证书需先核对是否适用于实际服务器，不能直接假定其能够验证任意 SIP 服务。

TLS 启动前应用会进行网络校时，等待 `NTP_UPDATE`；10 秒内未成功会打印 `TLS 校时失败，停止启动` 并结束启动流程。出现 `tls_ca_required` 时检查资源和 `ca_cert` 内容。SIP 服务器域名需与证书匹配。

`media_encryption = "none"` 时，TLS 只保护 SIP 信令。若还需启用 `"sdes"` 或 `"dtls-srtp"`，固件和服务端需同时具备相应 SRTP 能力，并保持 TLS 信令配置。
