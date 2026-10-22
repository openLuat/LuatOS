# Air8783H SIP / 蜂窝通话桥接工程（SIP_CC_BRIDGE_PCM）

基于 Air8783H 的 SIP 与蜂窝语音双向桥接工程，实现「SIP 终端 → 网络信令与 RTP → 设备内 PCM 桥接 → 蜂窝语音 → 手机」，同时接入 AirCloud，支持远程查看通话状态、修改 SIP 账号及维护手机号与 SIP 对端映射。

- 项目名（PROJECT）：`SIP_CC_BRIDGE_PCM`
- 项目版本（VERSION）：`1.1.18`，与 [main.lua](main.lua) 一致
- 默认联网：4G；可手动切换 WiFi STA
- SIP 信令：UDP / TCP / TLS，工程默认 UDP
- 音频编码：PCMA / PCMU / G729 / G722，工程默认 PCMA，固定 20 ms 帧长
- 云服务：AirCloud，使用本地 `excloud.lua` 和独立 TCP 兼容适配层
- 配置存储：fskv，Air8783H 使用键 `aircloud_pcm_v1`
- 外部看门狗：Air153C，默认 GPIO23，180 秒喂狗

**使用前必须修改 `sip_cc/config.lua` 中的 `target_phone_number`。当前值 `1xxxxxxxxxx` 是占位符，不能用于实际拨号，也不符合云端手机号校验规则。** SIP 账号、密码及对端账号同样需要与实际服务器匹配。

本文参照 Air8301 出厂工程说明的组织方式，按功能、硬件、配置、指令和测试展开。当前 `sip_cc_web` 目录提供设备侧桥接与 AirCloud 协议，未包含 HTML 页面、HTTP 服务或本地网页访问地址；网页管理端如需控制设备，应对接本文的 AirCloud 协议。

## 阅读顺序

- 首次烧录：第二节准备硬件 → 第三、四节配置 → 第五节烧录 → 第六节通话验证。
- 云端联调：第七节指令与示例 → 第八节状态字段和分片 → 第九节配置生效规则。
- 遇到问题：第十节超时与保护机制 → 第十一节故障排查。

---

## 一、功能模块介绍

### 1.1 目录结构与烧录路径

```text
sip_cc_web/
├── main.lua                      PROJECT / VERSION、配置加载、模块启动
├── sip_cc/
│   ├── config.lua                SIP、手机号、网卡、媒体、看门狗配置
│   ├── sip_cc_app.lua            等待网络、TLS 校时、CC / SIP 初始化
│   ├── sip_main.lua              SIP 注册与呼叫状态、消息请求处理
│   ├── cc_main.lua               蜂窝通话、PCM 生命周期与故障统计
│   ├── pcm_sip.lua               exsipclient 信令与 voip 媒体适配
│   ├── bridge.lua                双向呼叫、挂断清理、等待与恢复
│   └── air153c_wdt.lua           Air153C 看门狗初始化
├── cloud/
│   ├── aircloud_app.lua          桥接状态查询、空闲判定、云协议启动
│   ├── aircloud_protocol.lua     指令分发、响应队列、周期上报、重启调度
│   ├── aircloud_settings.lua     配置校验、持久化、能力表、生效判断
│   ├── sos_config.lua            号码及 SIP 映射的规范化和 JSON 编码
│   └── aircloud_tcp_adapter.lua  动态加载 excloud、TCP 收发兼容
├── netdrv/
│   ├── netdrv_device.lua         选择 4G 或 WiFi 驱动
│   ├── netdrv_4g.lua             4G IP 事件及 DNS 配置
│   └── netdrv_wifi.lua           WiFi STA 连接及 IP 事件
├── lib/
│   └── excloud.lua               工程随附的 AirCloud 扩展库
├── audio/
│   └── Time_travel_8k.mp3        通话提示音测试资源
├── certs/
│   └── sip-ca.pem                SIP TLS 使用的 CA 资源
└── README.md                     本说明，不烧录
```

子目录只用于电脑端分类，脚本和资源烧录后按文件原名放入 `/luadb`。例如：

| 电脑端文件 | 设备侧文件 / 使用方式 |
| --- | --- |
| `sip_cc/config.lua` | `/luadb/config.lua` 或编译后的 `.luac`，通过 `require "config"` 加载 |
| `cloud/aircloud_settings.lua` | 通过 `require "aircloud_settings"` 加载 |
| `lib/excloud.lua` | `/luadb/excloud.lua` 或 `/luadb/excloud.luac`，由 TCP 适配层加载 |
| `audio/Time_travel_8k.mp3` | `/luadb/Time_travel_8k.mp3` |
| `certs/sip-ca.pem` | `/luadb/sip-ca.pem` |

不要把运行时路径改成 `/luadb/sip_cc/config.lua`，也不要把模块名改成 `sip_cc.config`。不同目录中的文件平铺后不得重名。

### 1.2 各模块职责

| 模块 | 主要工作 | 联调时关注 |
| --- | --- | --- |
| `main.lua` | 定义版本，先加载持久化配置，再启动看门狗、网络、桥接和云服务 | 开机版本是否正确，保存过的配置是否覆盖默认值 |
| `sip_cc_app.lua` | 最长等待网络 10 秒；TLS 模式先校时；CC 成功后再初始化 SIP | 网络超时、TLS 校时失败、CC 初始化失败 |
| `sip_main.lua` | 将 SIP 注册、信令及媒体回调转换为业务消息 | 注册成功不等于通话接通，信令接通也需等待媒体 |
| `cc_main.lua` | 初始化 PCM 桥接模式，拨号 / 接听 / 挂断，检查音频启动和实际下行 PCM | CC 状态、会话号、拨号错误、SDK 未释放 |
| `pcm_sip.lua` | 配置编码与传输，启动 exsipclient、VoIP，传递媒体会话身份 | 编码能力、桥接接口、RTP、网络丢失 |
| `bridge.lua` | 连接两侧状态机，避免旧通话事件干扰新通话 | 等待、清理、冷却、恢复状态 |
| `aircloud_app.lua` | 提供状态快照和可否重启的空闲判断 | `cleanup_pending`、`recovering`、媒体是否空闲 |
| `aircloud_protocol.lua` | 收发 JSON 指令，去重、分片、上报及重启安排 | 请求 ID、响应队列、响应提交后延迟重启 |
| `aircloud_settings.lua` | 校验字段、写入 fskv、判断热生效与重启 | `reboot_pending`、`reboot_reason`、兼容保存字段 |
| `sos_config.lua` | 校验号码和账号数组，生成映射 | 数组长度、号码格式、多个表示之间的一致性 |
| `aircloud_tcp_adapter.lua` | 隔离加载 excloud，处理 TCP 包边界及相关兼容 | 缺库、字节码不兼容、断线和发送失败 |

### 1.3 启动顺序

```text
main.lua
  → 加载 sys / sysplus
  → 读取 config.lua，并加载 aircloud_pcm_v1 持久化配置
  → 初始化 Air153C 看门狗
  → 加载选定的网络驱动
  → 加载桥接协调器和 AirCloud 应用，启动各自任务
  → 桥接任务等待 IP_READY（最多 10 秒）
  → TLS 模式：SNTP 校时，等待 NTP_UPDATE（最多 10 秒）
  → cc_main.init() 成功
  → sip_main.init()，启动注册
  → SIP 注册成功后进行双向通话验证
```

网络等待超时会打印警告并继续尝试初始化；TLS 校时超时则直接结束本次桥接启动任务。`SIP 启动完成` 仅代表启动调用成功，注册成功应以 `sip_main` 的 `event register ok` 或云端 `registered=true` 为准。

---

## 二、硬件配置与演示环境

### 2.1 准备清单

| 物品 | 数量 | 用途 / 要求 |
| --- | --- | --- |
| Air8783H 设备及配套供电 | 1 套 | 运行本工程，供电及接线按实际硬件设计 |
| SIM 卡 | 1 张 | 正常蜂窝通话需要语音业务；默认 4G 联网还需数据业务 |
| 普通手机 | 1 部 | 接听设备拨出的电话，以及拨打设备 SIM 号码 |
| SIP 终端 | 1 个 | 注册对端账号，可使用已有 SIP 终端或软电话 |
| SIP 服务 | 1 套 | 账号、密码、域、端口、传输方式与两端配置对应 |
| 电脑及下载连接线 | 1 套 | Luatools 烧录、查看启动与通话日志 |
| 2.4 GHz WiFi 热点 | 可选 | 切换 WiFi STA 时使用 |
| Air153C 看门狗 | 按硬件配置 | 默认软件启用 GPIO23 喂狗，需与实物一致 |

两侧通话音频由固件的 CC / VoIP PCM 接口交换，本工程未配置本地麦克风、扬声器或 LCD。手机和 SIP 对端负责收听与讲话；不能照搬 Air8301 工程的 LCD、485、继电器引脚。

### 2.2 固件接口要求

本目录不包含底层固件，也没有可直接据此确认的最低固件版本号。应选择适配 Air8783H 且提供本工程接口的固件，初始化失败时根据以下错误定位：

| 检查项 | 用途 / 典型错误 |
| --- | --- |
| `cc.init` | 缺少时返回 `cc_unavailable` |
| `cc.AUDIO_MODE_BRIDGE_PCM` | 选择纯 PCM 模式；缺少时报 `firmware_missing_bridge_pcm` |
| `mcu.ticks2(1)` | 单调时间；无有效返回时报 `firmware_missing_monotonic_clock` |
| `cc.bridgePcmStats()` | 提供会话、PCM 队列及 SDK 状态；不符合要求时报 `firmware_missing_pcm_stats:<字段>` |
| `cc.bridgeAudioStop()` | 停止当前通话媒体；缺少时报 `firmware_missing_bridge_audio_stop` |
| `voip.setAudioMode`、`voip.AUDIO_MODE_BRIDGE`、`voip.pcmIn`、`voip.pcmOut` | VoIP 桥接模式及 PCM 输入输出 |
| `voip.PCMA` / `PCMU` / `G729` / `G722` | 选用编码对应的固件能力；缺少时报 `firmware_missing_voip_<编码>` |
| `fskv` | 持久化配置，入口即初始化；不可用时无法正常加载配置模块 |

`cc.bridgePcmStats()` 至少需要 `selected` 布尔值，以及 `session`、`active`、`media_ready`、`fault`、`dl_pushed`、`dl_queued`、`ul_queued`、`sdk_active`、`sdk_pending`、`sdk_stop_waiting`、`sdk_fault`、`sdk_stop_timeout` 等非负整数字段。只有库名存在、但统计字段不匹配的固件也无法通过初始化。

### 2.3 看门狗配置

```lua
config.WDT_CONFIG = {
    ENABLE = true,
    FEED_PIN = 23,
    FEED_INTERVAL = 180, -- 秒
}
```

`air153c_wdt.lua` 调用 `exair153x_wdt.init`，将 GPIO 和周期传入扩展库。未使用该硬件时，可将 `ENABLE` 改为 `false`；更换引脚时同步修改 `FEED_PIN`。初始化成功日志包含喂狗引脚和周期；缺库或初始化失败会打印错误。

---

## 三、网络配置

### 3.1 默认 4G 联网

`netdrv/netdrv_device.lua` 默认只启用 4G：

```lua
require "netdrv_4g"
-- require "netdrv_wifi"
```

`sip_cc/config.lua` 对应配置：

```lua
adapter = socket.LWIP_GP,
```

插入具备所需业务的 SIM 卡，观察 `netdrv_4g.ip_ready_func` 的 `IP_READY` 日志，再查看 SIP 注册结果。网络就绪只代表获得数据网络，不能证明 SIM 支持语音。

### 3.2 切换 WiFi STA

需要同时修改三个位置：

1. `netdrv_device.lua` 注释 `require "netdrv_4g"`，启用 `require "netdrv_wifi"`。
2. `netdrv_wifi.lua` 填写实际热点信息：

```lua
WIFI = {
    ssid = "YOUR_WIFI_SSID",
    password = "YOUR_WIFI_PASSWORD"
}
```

3. `config.lua` 将网卡改为：

```lua
adapter = socket.LWIP_STA,
```

使用 2.4 GHz 热点，下载列表中包含 `exnetif` 及其依赖。查看 `WLAN_STA_INC` 和 WiFi `IP_READY` 日志，再检查 `pcm_sip` 打印的实际网卡。

WiFi 承载 SIP 数据连接时，手机侧通话仍使用设备 SIM 的蜂窝语音业务。当前驱动选择入口按单网络配置使用，没有在本工程中提供网页切换网络或 4G / WiFi 自动切换界面。

**AirCloud 还存在独立的 4G 就绪条件：** 当前 `aircloud_protocol.lua` 每轮检查 `socket.adapter(socket.LWIP_GP)`，4G 网卡未就绪时关闭或不建立云连接。因此仅把 SIP 切到 WiFi，并不能保证纯 WiFi 条件下云服务可用。WiFi 联调时应分别验证 SIP 与 AirCloud，不要把“WiFi 已获得 IP”当作云连接的充分条件。

云库创建连接时使用系统默认网卡 `socket.dft()`，并不读取 SIP 的 `config.adapter`。4G 就绪检查和实际云连接网卡选择是两个条件，现场需要分别核对。

### 3.3 DNS 与不同服务的传输方式

| 项目 | 配置位置 | 当前行为 |
| --- | --- | --- |
| 4G / WiFi DNS | 各自 `netdrv_*.lua` | 获得 IP 后配置 `223.5.5.5`、`114.114.114.114` |
| SIP 信令 | `config.sip_transport` | 默认 `udp`，也支持 `tcp` / `tls` |
| RTP 媒体端口 | `config.rtp_port` | 默认 `40000`，实际对端由媒体协商确定 |
| AirCloud | `aircloud_protocol.lua` | TCP，`use_getip=true`，由云协议处理重连 |
| TLS 启动校时 | `sip_cc_app.lua` | 调用 `socket.sntp()`，等待 `NTP_UPDATE` |

专网卡或国外网络按驱动注释调整 DNS。修改 SIP 传输不会改变 AirCloud 的 TCP 传输；SIP 注册成功也不能代替 AirCloud 登录成功的验证。

---

## 四、SIP 账号、号码与音频配置

### 4.1 区分设备账号、SIP 对端和手机号码

| 名称 | 作用 | 默认 / 示例 |
| --- | --- | --- |
| 设备 SIP 账号 | Air8783H 向服务器注册使用，SIP 终端呼叫它 | `hmeta.devid() .. "0"` |
| SIP 对端账号 | 手机呼入设备后，设备转呼的 SIP 终端 | 默认设备 ID 后加 `1` |
| `remote_sip_uri` | SIP 对端的完整 URI | `sip:<设备ID>1@cc.luatos.com` |
| `target_phone_number` | SIP 呼入设备后，设备拨打的手机号码 | 当前为占位符 `1xxxxxxxxxx`，必须替换 |
| 设备 SIM 号码 | 手机发起呼入时拨打的号码 | 由实际 SIM 卡决定，与目标手机号码不同 |

假设服务器为设备和终端分配的账号分别是 `device001` 和 `operator001`，则设备配置 `sip_username="device001"`，SIP 对端使用 `operator001` 注册；设备的 `remote_sip_uri` 填 `sip:operator001@<实际域名>`。不要把 `remote_sip_uri` 填成设备自己的账号。

### 4.2 SIP 基础参数表

默认值来自 [sip_cc/config.lua](sip_cc/config.lua)。

| 参数 | 当前值 | 说明 |
| --- | --- | --- |
| `sip_server_addr` | `cc.luatos.com` | SIP 服务器地址 |
| `sip_server_port` | `8910` | 当前示例服务端口；换服务器时按实际监听端口填写 |
| `sip_domain` | `cc.luatos.com` | SIP 域；空字符串时回退服务器地址 |
| `sip_username` | `hmeta.devid() .. "0"` | 注册账号，须在服务端可用 |
| `sip_password` | `123456` | 当前示例密码，按实际账号填写 |
| `sip_transport` | `udp` | `udp` / `tcp` / `tls` |
| `sip_tls` | 默认未启用 | TLS 参数，示例从 `/luadb/sip-ca.pem` 读取 CA |
| `media_encryption` | 默认未显式设置，媒体层默认 `none` | 按服务端及固件能力配置 |
| `remote_sip_uri` | `sip:` + 设备 ID + `1@cc.luatos.com` | 手机来电时呼叫的 SIP 对端 |
| `target_phone_number` | `1xxxxxxxxxx` | SIP 来电时呼叫的手机 |
| `adapter` | `socket.LWIP_GP` | 与网络驱动选择一致 |
| `auto_answer_sip` | `true` | 自动推进 SIP 来电桥接流程，先 183，手机接通后再正式应答 |
| `auto_handle_mobile_incoming` | `true` | 手机呼入后自动呼叫 SIP 对端 |

将两个自动流程开关设为 `false` 不会出现手动接听界面；本工程未提供本地 UI。正常演示保留默认值。

### 4.3 编码与帧长

| 配置 | 默认值 | 约束 / 行为 |
| --- | --- | --- |
| `codec` | `PCMA` | 单一编码 |
| `codecs` | 默认注释 | 非空列表启用时，`sip_main.lua` 优先传递该列表 |
| `ptime` | `20` | 本桥接仅接受 20 ms，其他值返回 `bridge_requires_20ms` |
| `rtp_port` | `40000` | 本地 RTP 端口配置 |
| `cc_audio_start_timeout_ms` | `3000` | 蜂窝接通但 PCM 未就绪时的等待上限；不大于 0 时不启动此超时定时器 |
| `cc_media_min_connected_ms` | `2000` | 接通后当前媒体阶段达到此时长才参与无 PCM 异常计数 |
| `cc_media_missing_call_limit` | `3` | 满足统计条件的连续无真实下行 PCM 通话阈值 |
| `cc_media_reboot_on_error` | `true` | 达到无 PCM 异常条件后进行清理并重启恢复 |

| 编码 | 媒体 PCM 采样率 | 备注 |
| --- | --- | --- |
| PCMA | 8 kHz | 当前默认 |
| PCMU | 8 kHz | 可用于对端兼容测试 |
| G729 | 8 kHz | 支持 `G.729` 别名，需配套固件编码能力 |
| G722 | 16 kHz | 支持 `G.722` 别名，仍为 20 ms 帧长 |

多编码示例，放入 `config` 表内：

```lua
codecs = {"PCMU", "PCMA", "G729", "G722"},
ptime = 20,
```

媒体封装内部默认 `expires=600`、`call_timeout=30`；当前 `sip_main.lua` 未从 `config.lua` 透传这两个字段，不能只在配置表中增加同名字段就认为生效。

### 4.4 TLS 配置步骤

1. 先用当前可用传输验证账号、域、目标及基础通话。
2. 将 `sip_transport` 改为 `tls`，端口改为服务端实际 TLS 监听端口。
3. 核对 CA 与服务器证书链匹配，将证书加入烧录列表。
4. 在 `config` 表启用：

```lua
sip_tls = {ca_cert = io.readFile("/luadb/sip-ca.pem")},
media_encryption = "none",
```

5. 开机确认 TLS 校时完成，再检查注册。`TLS 校时失败，停止启动` 表示尚未进入 CC / SIP 初始化。
6. 需要媒体加密时，按服务器及固件实际能力配置 `sdes` 或 `dtls-srtp` 并另行验收。TLS 保护信令，不能据此认定 RTP 已加密。

云端只能提交本文第七节列出的 SIP 连接字段，不能直接上传 CA 或修改 `sip_tls`、`media_encryption`；这些内容需在本地配置和资源中准备。

---

## 五、Luatools 烧录与首次启动

### 5.1 烧录前检查

- 修改手机号占位符，核对 SIP 服务、设备账号、对端账号及密码。
- 确认网络驱动和 `adapter` 一致；WiFi 模式填写热点信息。
- 确认看门狗启用状态与硬件一致。
- TLS 模式确认服务器端口、CA 文件及联网校时条件。
- 使用符合第二节接口要求的底层固件；本工程目录只有脚本与资源。

### 5.2 添加文件

1. 在 Luatools 中选择匹配硬件的底层固件。
2. 添加根目录 `main.lua`。
3. 添加 `sip_cc/`、`cloud/`、`netdrv/` 中的 Lua 文件。
4. **单独核对下载列表中有 `lib/excloud.lua`。** 仅电脑目录存在该文件不代表会下载到设备。
5. 添加 `audio/Time_travel_8k.mp3` 和 `certs/sip-ca.pem`。
6. 使用自动依赖收集，并核对下表；缺少时从仓库对应目录手动补齐。
7. 取消勾选 `README.md`，检查平铺后的文件名无重复，再开始烧录。

| 依赖 | 本工程使用位置 | 来源 / 备注 |
| --- | --- | --- |
| `sys`、`sysplus` | 入口、任务和消息 | 仓库 `script/corelib/` |
| `exsipclient`、`exsipproto` | SIP 信令和协议处理 | 仓库 `script/libs/`，同时收集其依赖 |
| `excloud` | AirCloud | 使用工程随附 `lib/excloud.lua`，不要重复添加不同版本 |
| `exair153x_wdt` | 看门狗 | 仓库 `script/libs/` |
| `exnetif` | WiFi STA | WiFi 模式需要，仓库 `script/libs/` |

### 5.3 1.1.18 的 excloud 依赖说明

TCP 适配层使用 `loadfile` 在隔离环境中加载 excloud。Luatools 依赖扫描通常根据字面量 `require` 识别依赖，因此 `1.1.18` 增加了仅供扫描识别的声明：

```lua
if false then
    require "excloud"
end
```

该声明不会执行第二个 excloud 实例。升级时重新添加最新脚本并收集依赖，不要直接复用漏库的旧下载列表。适配层会尝试 `/luadb/excloud.luac`、`/luadb/excloud.lua` 等位置；若报 `excloud missing or incompatible`，优先核对实际烧录文件及字节码兼容性。

### 5.4 开机验收

按顺序观察以下日志关键词；具体时间及参数以设备输出为准：

| 阶段 | 关键词 / 状态 | 说明 |
| --- | --- | --- |
| 入口 | `SIP_CC_BRIDGE_PCM`、`1.1.18` | 确认当前脚本版本 |
| 看门狗 | `Air153C 看门狗初始化成功` 或 `看门狗未开启` | 与配置一致 |
| 网络 | `IP_READY` | 对应启用网卡获得 IP |
| CC | `CC 初始化完成 bridge_pcm` | PCM 模式初始化成功 |
| SIP 参数 | `SIP registration target`、`SIP codecs` | 核对服务器、账号、传输和编码 |
| SIP 启动 | `SIP/CC 桥接应用启动成功` | 初始化完成，仍需等待注册 |
| SIP 注册 | `event register ok` / 云端 `registered=true` | 可继续通话测试 |
| AirCloud | 收到 `boot` / `status` 快照或查询响应 | 单独确认云端链路 |

若已经配置过设备，先查询云端 `get_sip_config` 再判断参数是否正确；持久化值可能覆盖新烧录脚本的默认连接参数。

---

## 六、双向通话流程与操作测试

### 6.1 SIP 终端呼叫手机

前提：设备和 SIP 对端均完成注册，`target_phone_number` 为可接听手机，SIM 具备语音能力。

1. SIP 对端呼叫**设备的 SIP 账号**。
2. 设备收到来电，记录本通的目标手机号码，检查旧通话是否释放。
3. 空闲后发送 SIP 183；同时等待 VoIP 媒体真实启动。
4. 两项都确认后才发起 `CC_DIAL_REQ`，手机应开始振铃。
5. 手机接听，CC 接通且 PCM 就绪后，设备请求 SIP 正式应答。
6. SIP 信令与媒体都就绪后，`in_call=true`，双方进行语音测试。
7. 任一端挂断，另一侧随之结束；等待清理完成后再次呼叫。

```text
SIP 来电
  → 旧资源释放 + 冷却结束
  → SIP 183 + VoIP started
  → 拨打 target_phone_number
  → 手机接通 + CC PCM 就绪
  → SIP 正式应答 + SIP 媒体就绪
  → 双向通话
```

关键日志：`SIP 来电` → `旧通话已释放，启动 SIP 183` → `183 和 VoIP started 已确认，拨打手机` → `CC 已接通且 PCM 通道就绪`。

如果有 SIP 来电但手机不响，应先确认是否到达第三条日志。未到达时检查 SIP 183 / 媒体初始化；到达但拨号失败时检查 CC、SIM 和手机号。

### 6.2 手机呼叫 SIP 终端

前提：手机知道设备 SIM 号码，`remote_sip_uri` 指向已注册对端，`auto_handle_mobile_incoming=true`。

1. 手机拨打**设备 SIM 号码**。
2. 设备收到蜂窝来电，等待桥接资源可用。
3. 设备向 `remote_sip_uri` 发起 SIP 呼叫，SIP 对端应振铃。
4. SIP 对端接听，信令和 SIP 媒体就绪后，设备才请求接听蜂窝侧。
5. CC 接通及 PCM 就绪后进入双向通话。
6. 分别测试手机挂断、SIP 对端挂断，确认两侧结束并能再次拨入。

```text
手机拨打设备 SIM
  → CC 来电
  → 拨打 remote_sip_uri
  → SIP 对端接听 + SIP 媒体就绪
  → 接听 CC
  → CC PCM 就绪
  → 双向通话
```

关键日志：`手机来电，等待桥接可用` → `呼入场景：拨打 SIP` → `执行接听` → `CC 已接通且 PCM 通道就绪`。

### 6.3 忙线、取消和连续呼叫

| 场景 | 当前行为 / 验收点 |
| --- | --- |
| 正在通话时另一 SIP 呼叫进入 | 返回 `486 Busy Here`；恢复中则返回 `480 Temporarily Unavailable` |
| 新来电遇到旧通话清理 | 最多等待 3 秒；超时的 SIP 来电返回 480，蜂窝等待来电请求挂断 |
| SIP 呼叫尚未转接完成就取消 | 结束对应通话，不得继续拨打或干扰下一通 |
| 一端主动挂断 | 另一端应收尾，同时等待 PCM / SDK 真实释放 |
| 挂断后立即重拨 | 清理后有 500 ms 冷却，不能仅看到 `cc_idle` 就认定所有资源已释放 |
| 手机拒接或不可达 | 检查终结事件及清理日志，随后再次发起正常呼叫 |

### 6.4 通话提示音当前状态

`bridge.lua` 中保留以下参数：

| 参数 | 值 | 含义 |
| --- | --- | --- |
| `CALL_NOTICE_TARGET` | `both` | 播报目标：SIP、CC 或两端 |
| `CALL_NOTICE_FILE` | `/luadb/Time_travel_8k.mp3` | 计划使用的文件；设为 `nil` 时走 TTS 分支 |
| `CALL_NOTICE_TEXT` | `通话已建立，本段进行TTS播报测试` | TTS 文本 |
| `CALL_NOTICE_DELAY_MS` | `500` | 两侧就绪后的延时 |

**当前文件播放和 TTS 调用均被注释，默认不会提交实际播报。** 代码仍可能先静音、等待 500 ms，随后打印 `远端音频提交失败` 并恢复双向语音；这与网络注册失败不同。按 `config.codec` 判断为 G729 / G722 时会跳过提示流程。

若后续启用播报，需要恢复相应调用并验证固件 `voip.playFile` / `playTTS`、`bridgeMute`、播放状态及停止能力；仅烧录 MP3 或修改文件名不能启用功能。云端 `play_tts` 指令在本工程仍返回不支持。

---

## 七、AirCloud 指令汇总与操作示例

### 7.1 指令格式与传输入口

下面的 JSON 是 **AirCloud TLV 数据字段中的业务内容**，不是 HTTP 请求，也不是串口 AT 指令。通过设备对应的云下行通道发送，依据请求 ID 关联响应。

```json
{"id":"request-001","cmd":"get_sip_status"}
```

| 字段 | 要求 |
| --- | --- |
| `id` | 字符串，1～64 字节，不含控制字符；每次新操作使用新 ID |
| `cmd` | 字符串，取值见指令表 |
| `params` | `set_config` 必填非空对象；查询指令不需要 |
| 完整 JSON | 原始内容最大 1396 字节 |

| 下发字段 | 响应字段 | 说明 |
| --- | --- | --- |
| `19` | `20` | 响应使用 `data_type=3` |
| `1281` | `1281` | 响应使用 `data_type=5` |

有效的云协议序列号会用于响应，业务请求仍通过 `id` 匹配。设备缓存最近 32 个请求 ID 的响应；重复 ID 即使携带不同参数，也会重放旧响应而不重新执行。调试时修改内容必须同时修改 ID。

### 7.2 支持指令

| 指令 | 功能 | 主要返回内容 |
| --- | --- | --- |
| `get_sip_status` | 查询当前注册、桥接及配置待生效状态 | 通话状态、`sos_status`、`capabilities` |
| `get_sip_config` | 查询已保存配置 | SIP 参数（不含密码）、号码映射、待重启状态 |
| `get_status` | 分区查询综合状态 | 四个响应：`sip`、`battery`、`location`、`audio` |
| `set_config` | 校验、保存配置并安排生效 | 保存后的公开配置、`reboot_pending`、`reboot_reason` |
| `get_location` | 当前不支持 | `unsupported_feature` |
| `speak_battery` | 当前不支持 | `unsupported_feature` |
| `play_tts` | 当前不支持 | `unsupported_feature` |
| 其他命令 | 未定义 | `unknown_command` |

Air8783H 的 `get_status` 中，SIP 分区正常返回；电池、定位、本机音频分区返回不支持，不代表 SIP 通话功能失败。

### 7.3 查询注册与通话状态

请求：

```json
{"id":"status-001","cmd":"get_sip_status"}
```

以下是**注册成功、空闲时的部分响应字段示意**，不是完整抓包；时间、设备 ID、能力表等公共字段未展开：

```json
{
  "version": 1,
  "type": "response",
  "id": "status-001",
  "cmd": "get_sip_status",
  "ok": true,
  "result": {
    "registered": true,
    "connected": false,
    "in_call": false,
    "sip_state": "sip_idle",
    "cc_state": "cc_idle",
    "state": "sip_idle",
    "waiting": false,
    "cleanup_pending": false,
    "cooldown_remaining_ms": 0,
    "recovering": false,
    "config_pending": false,
    "reboot_pending": false
  }
}
```

判断可否继续测试时，除了 `registered`，还要检查 `waiting`、`cleanup_pending`、`recovering` 及冷却时间。`connected` 表示 SIP / CC 两端均连接，不表示 AirCloud 连接状态。

### 7.4 查询已保存配置

```json
{"id":"config-read-001","cmd":"get_sip_config"}
```

重点检查 `result.sip`、`sos_mode`、`sos_sip_cc_numbers`、`sos_sip_cc_peers` 和 `reboot_pending`。响应会移除 `sip_password`，不会通过查询返回明文密码；保存成功后的查询值不一定已被当前运行中的 SIP 连接使用，需结合第九节判断。

### 7.5 修改 SIP 连接参数

将下面的服务器、账号、密码替换为实际配置，再通过云端下发：

```json
{
  "id": "sip-config-001",
  "cmd": "set_config",
  "params": {
    "sip": {
      "sip_server_addr": "sip.example.com",
      "sip_server_port": 5060,
      "sip_domain": "sip.example.com",
      "sip_username": "device001",
      "sip_password": "replace_with_actual_password",
      "sip_transport": "udp"
    }
  }
}
```

支持只提交需要修改的 SIP 字段，其他字段保留。但**提交任一 SIP 连接字段，即使值与原来相同，也会请求空闲重启**。成功响应中 `reboot_pending=true`，原因通常为 `sip_settings_submitted`。

首次使用时先确认已存在有效的 `sip_cc` 映射。若默认手机号仍为占位符且没有保存过有效配置，模式可能为空，单独提交 SIP 参数会因模式不支持而被拒绝。可先按 7.6 节保存有效映射，或在同一 `params` 中同时提交 `sip` 对象和完整映射字段。

| 可写字段 | 类型与校验 |
| --- | --- |
| `sip.sip_server_addr` | 非空 UTF-8 字符串，最多 253 字节，不含控制字符 |
| `sip.sip_domain` | UTF-8 字符串，最多 253 字节，可为空，不含控制字符 |
| `sip.sip_username` | 非空 UTF-8 字符串，最多 128 字节，不含控制字符 |
| `sip.sip_password` | 非空 UTF-8 字符串，最多 128 字节，不含控制字符 |
| `sip.sip_server_port` | 整数，1～65535；不能使用字符串形式端口 |
| `sip.sip_transport` | 严格为小写 `udp` / `tcp` / `tls` |
| `sip.auto_answer` | 布尔值，**仅兼容保存** |
| `sip.delay_auto_answer` | 0～20 的整数，**仅兼容保存** |

`codec`、`codecs`、`rtp_port`、`adapter`、`sip_tls`、`media_encryption` 和看门狗参数不在该云写入接口支持范围内。向 `params.sip` 添加这些字段会导致更新被拒绝，应修改对应本地代码配置。

### 7.6 修改手机号与 SIP 对端映射

当前 Air8783H 仅允许一组映射。下面示例中的手机号仅演示格式，必须替换为现场号码；`operator001` 替换为实际 SIP 对端账号：

```json
{
  "id": "mapping-001",
  "cmd": "set_config",
  "params": {
    "sos_mode": "sip_cc",
    "sos_sip_cc_numbers": ["13800138000"],
    "sos_sip_cc_peers": ["operator001"]
  }
}
```

| 字段 | 作用与规则 |
| --- | --- |
| `sos_mode` | 本项目只支持 `sip_cc`；建议显式提供 |
| `sos_sip_cc_numbers` | 手机号字符串数组，Air8783H 当前恰好一项；不能传数字类型 |
| `sos_sip_cc_peers` | 与号码数组等长的 SIP 账号数组；填账号，不填完整 URI |
| `sos_numbers` | 当前模式号码的镜像，可省略；提供时必须与号码数组一致 |
| `sos_sip_cc_map` | 按 SIP 对端分组的派生映射，可省略；提供时必须与两个数组一致 |
| `sos_sip_numbers`、`sos_cc_numbers` | 属于其他模式，当前配置中省略或传空数组 |

手机号最长 32 字节，仅允许可选的前导 `+` 和数字。SIP 对端账号最长 64 字节，允许字母、数字及 `+ * # _ . -`，不能写成 `sip:operator001@example.com`。

修改手机号时仍需同时提交当前 SIP 对端数组，不能只发 `sos_sip_cc_numbers`。若需要包含派生表示，示例如下：

```json
{
  "id": "mapping-002",
  "cmd": "set_config",
  "params": {
    "sos_mode": "sip_cc",
    "sos_sip_cc_numbers": ["13800138000"],
    "sos_sip_cc_peers": ["operator001"],
    "sos_numbers": ["13800138000"],
    "sos_sip_cc_map": [
      {"peer_sip": "operator001", "numbers": ["13800138000"]}
    ]
  }
}
```

设备启动时会使用保存的对端账号，结合保存的 SIP 域（空域时用服务器地址）生成 `remote_sip_uri`。这里的 SOS 字段是共用云协议中的映射配置；本工程能力为 `keys=false`、`outgoing_sos=false`，不能据此认为已实现物理 SOS 按键外呼。

### 7.7 兼容接听偏好

```json
{
  "id": "answer-settings-001",
  "cmd": "set_config",
  "params": {"sip": {"auto_answer": true, "delay_auto_answer": 3}}
}
```

此请求只保存偏好，当前 PCM 桥接仍执行第六节描述的接听时序，不会改成延迟 3 秒自动接听。响应能力表包含 `compatibility_only_fields` 和说明信息；云端界面应展示这个限制。

### 7.8 成功与失败响应判读

`set_config` 保存成功的部分响应示意：

```json
{
  "type": "response",
  "id": "sip-config-001",
  "cmd": "set_config",
  "ok": true,
  "result": {
    "reboot_pending": true,
    "reboot_reason": "sip_settings_submitted"
  }
}
```

以上省略了公共字段、保存后的 `config`、`sos_status`、`audio_status` 和 `apply`。`ok=true` 表示本次配置保存成功，不能单独据此认定服务器重新注册成功。

以下不支持的请求可用于检查错误处理：

```json
{"id":"unsupported-001","cmd":"play_tts"}
```

部分响应：

```json
{
  "type": "response",
  "id": "unsupported-001",
  "cmd": "play_tts",
  "ok": false,
  "error": "unsupported_feature",
  "result": {
    "message": "当前项目不支持该功能",
    "unsupported_fields": ["play_tts"]
  }
}
```

### 7.9 常见错误码

| 错误码 | 触发条件 / 处理 |
| --- | --- |
| `command_too_large` | 原始指令超过 1396 字节，缩减内容 |
| `invalid_command` | 已识别命令但 ID 或命令字段类型等不合法 |
| `unknown_command` | 未定义的命令名 |
| `empty_config` | `params` 缺失或为空对象 |
| `invalid_sip` | `sip` 不是非空对象 |
| `invalid_sip_server_addr` / `invalid_sip_domain` | 字符串长度、UTF-8 或内容不合法 |
| `invalid_sip_username` / `invalid_sip_password` | 账号密码为空或不符合字符串约束 |
| `invalid_sip_server_port` / `invalid_transport` | 端口范围或传输值错误 |
| `invalid_auto_answer` / `invalid_delay_auto_answer` | 兼容字段类型或范围错误 |
| `invalid_sos_mode` / `ambiguous_sos_mode` | 模式无效，或无法从多个非空列表唯一推断 |
| `invalid_sos_sip_cc_numbers` / `invalid_sos_sip_cc_peers` | 号码 / 对端数组结构或长度不合法 |
| `invalid_sos_number` / `invalid_sos_peer` | 号码或账号格式不合法，或号码重复 |
| `conflicting_sos_fields` | 同时提供冲突的模式字段 |
| `sos_mirror_mismatch` | `sos_numbers` 与主列表不一致 |
| `invalid_sos_map` / `sos_map_mismatch` | 派生映射结构错误或与数组不一致 |
| `invalid_audio` | 音频配置对象格式错误；合法音频字段在本项目仍不支持 |
| `unsupported_feature` | 多组映射、不支持的模式 / 字段 / 功能；查看 `unsupported_fields` |
| `storage_failed` | fskv 保存失败，不能按成功应用处理 |

不能解析的 JSON 或没有 `cmd` 的 JSON 不保证收到错误响应。先检查下发内容、TLV 字段与设备日志，再判断云链路是否故障。

---

## 八、状态上报、能力描述与分片

### 8.1 上报节奏和字段

AirCloud 认证完成后发送启动快照 `boot`，随后约每 30 秒安排 `status` 快照。发送受网络和队列影响，不是严格实时的通话事件推送；需要即时状态时主动发 `get_sip_status`。

| TLV 字段 | 内容 | 说明 |
| --- | --- | --- |
| `1281` | JSON 启动 / 状态快照 | 可能分片 |
| `265` | 工作状态整数 | 双端通话接通时为 `2`，否则为 `1`；不能代替详细状态字段 |
| `1280` | Unix 时间戳 | 仅时间有效时随主动上报附带 |
| `20` | 从字段 19 下发的命令响应 | 可能分片 |

公共 JSON 信封：

| 字段 | 含义 |
| --- | --- |
| `version` | 普通消息为 1；`get_status` 分区响应为 2 |
| `type` | `boot`、`status` 或 `response` |
| `device_id` | `hmeta.devid()` |
| `timestamp` | 当前 Unix 时间戳 |
| `report_id` | 时间戳与本地递增序号组成的标识 |
| `beijing_time` | UTC+8 格式化时间 |
| `time_valid` | 当前代码按时间戳不早于 2025-01-01 判断 |
| `timezone` | `UTC+08:00` |
| `project` / `project_version` | 项目名及 `1.1.18` 版本 |
| `id` / `cmd` / `ok` | 响应中关联请求及执行结果 |

`time_valid=true` 是时间范围判定，不等于独立证明本次 SNTP 已成功。当前桥接启动任务仅在 TLS 模式显式校时。

### 8.2 通话状态字段

| 字段 | 含义 / 判断方法 |
| --- | --- |
| `registered` | SIP 注册是否成功 |
| `in_call` / `connected` | 当前 SIP 和 CC 两侧是否均已接通 |
| `sip_state` | `sip_idle`、`sip_incoming`、`sip_progressing`、`sip_dialing`、`sip_connected`、`sip_disconnecting` 等 |
| `cc_state` | `cc_idle`、`cc_dialing`、`cc_ringing`、`cc_connected`、`cc_disconnecting`、`cc_release_error` |
| `call_direction` | `outgoing` 表示 SIP 来电转拨手机；`incoming` 表示手机来电转拨 SIP |
| `call_duration` | 双侧接通后的时长，单位秒 |
| `waiting` | 是否有来电在等待资源可用 |
| `cleanup_pending` | 是否有旧通话尚未清理完 |
| `cooldown_remaining_ms` | 清理后的冷却剩余时间，毫秒 |
| `recovering` | 是否处于无真实 PCM 的恢复流程 |
| `current_call_id` / `pending_call_id` | 当前 / 等待的 SIP Call-ID；没有时字段可能省略 |
| `state` | 通话时为 `CONNECTED`，等待时为 `WAITING`，否则使用 SIP 状态 |
| `cc_dial_error` | 最近一次直接拨号失败详情，含原因及 PCM 前后快照；可能在通话结束后仍保留 |
| `error` | 最近直接拨号错误的简要标记，不是所有故障的统一列表 |
| `config_pending` / `reboot_pending` | 是否有配置等待通过重启生效 |
| `reboot_reason` | 通常为 `sip_settings_submitted` 或 `configuration_changed` |

### 8.3 能力描述

| 能力 | Air8783H 当前值 / 含义 |
| --- | --- |
| `modes` | `["sip_cc"]` |
| `max_targets` | `1` |
| `max_sip_peers` | `1` |
| `keys` / `outgoing_sos` | `false`，未提供按键主动 SOS 流程 |
| `audio` | `false`，不提供本机音量 / 麦克风配置 |
| `battery` / `location` / `tts` | `false` |
| `writable_fields` | 允许写入的 SIP 与 SOS 字段 |
| `compatibility_only_fields` | `sip.auto_answer`、`sip.delay_auto_answer`，只保存 |
| `migration_warning` | 旧配置或默认桥接映射不能完整转换时的提示 |

当前手机号占位符不能通过号码规范化；首次使用应先填有效号码，或在云端提交完整有效映射。若看到 `migration_warning`，应核对并重新保存映射，而不是忽略该字段。

### 8.4 get_status 的四段响应

```json
{"id":"all-status-001","cmd":"get_status"}
```

设备生成四个同 ID 的响应，均含 `version=2`、`sections=4`，分别由 `section` 标记为 `sip`、`battery`、`location`、`audio`。云端应按请求 ID 和 section 收集，不能收到第一段就认定整个请求结束，也不能把不支持分区的 `ok=false` 覆盖 SIP 分区结果。

### 8.5 大消息分片与组装

设备先将非 ASCII 内容转换为 Unicode 转义。编码后不超过 1100 字节的 JSON 直接发送；更长的内容按每片最多 500 字节拆分，片段字节转换为十六进制字符串。

| 分片字段 | 含义 |
| --- | --- |
| `type` | 固定 `fragment` |
| `report_id` | 分片组标识；分区响应会附加 `:section` 区分组 |
| `id` | 对应请求 ID，主动上报可能没有 |
| `part` / `parts` | 当前片序号（从 1 开始）/ 总片数 |
| `encoding` | 固定 `hex` |
| `payload` | 本片原始 JSON 字节的十六进制表示 |

云端处理顺序：

1. 解析外层 JSON，判断是否为 `fragment`。
2. 按 `report_id` 建立分片组，记录 `parts`，用 `part` 存放各片。
3. 收齐后按 1 到 `parts` 排序，将每片 `payload` 十六进制解码并拼接为完整字节串。
4. 最后解析拼接后的 JSON，再根据 `type`、`id`、`section` 处理业务。

不要单独解析某一片解码后的内容；片段边界可能落在 JSON 字符串或转义序列内部。重连时也要避免将不同 `report_id` 的片段混为一组。

---

## 九、配置保存、生效与空闲重启

### 9.1 配置来源优先级

```text
config.lua 默认值
  → aircloud_settings.init("8783H", config)
  → 若 aircloud_pcm_v1 中存在 unified 配置，加载已保存值
  → 覆盖 SIP 连接字段及有效桥接映射
  → 启动本次 SIP / CC 业务
```

因此，重新烧录 `config.lua` 不等于清空云端保存的配置。`get_sip_config` 返回已保存配置，修改默认值后发现服务器仍旧不变时，应先检查 fskv 配置来源。当前云协议没有提供通用恢复出厂 / 删除配置指令。

### 9.2 各类修改如何生效

| 修改内容 | 保存后的行为 |
| --- | --- |
| 任一 SIP 连接字段 | 锁存空闲重启请求，值未变化也会请求重启 |
| SIP 对端账号 | 与开机配置不同则等待重启 |
| 仅目标手机号 | SIP 连接参数和对端仍与开机配置一致时，更新运行时目标，下一次 SIP 来电使用 |
| 通话中修改目标手机号 | 已有通话持有自己的号码快照，不改变当前拨号 |
| 兼容接听偏好 | 只保存，不改变接听时序 |
| 不支持字段 / 不合法内容 | 拒绝本次更新，不按“部分成功”处理 |
| fskv 写入失败 | 返回 `storage_failed`，不切换到新配置 |

已经提交 SIP 字段产生的重启请求，不会被后续单独修改号码或接听偏好的请求取消。

### 9.3 重启的全部条件

1. 本次更新成功写入 fskv。
2. 对应配置版本的响应全部提交到云发送接口；分片响应要等全部片段提交。
3. 从响应提交完成起至少等待 3 秒。
4. 无等待来电、无旧通话清理、无恢复流程，冷却已结束。
5. SIP 状态和 CC 状态均为空闲。
6. SIP 媒体和 CC / SDK 媒体均确认空闲。
7. 执行 `rtos.reboot()`，启动后读取已保存配置。

“提交发送接口”不代表云端页面已经收到并处理；云连接不可用时设备可能一直等候，不能把 3 秒解释为保存后的固定重启倒计时。

| `reboot waiting` 日志原因 | 含义 |
| --- | --- |
| `response_not_submitted` | 当前配置响应尚未全部提交 |
| `response_grace_period` | 3 秒响应宽限期未结束 |
| `bridge_waiting` | 有来电等待桥接 |
| `cleanup_pending` | 旧通话尚未清理完 |
| `recovering` | 正在故障恢复 |
| `cooldown` | 冷却尚未结束 |
| `sip_busy` / `cc_busy` | 对应呼叫状态未空闲 |
| `sip_media_busy` / `cc_media_busy` | 媒体或 SDK 资源未释放 |

---

## 十、超时、资源释放与异常恢复

### 10.1 时间参数汇总

| 场景 | 默认值 | 位置 |
| --- | --- | --- |
| 启动等待 IP | 10 秒 | `sip_cc_app.lua` |
| TLS 等待校时 | 10 秒 | `sip_cc_app.lua` |
| 新来电等待旧资源 | 3 秒 | `bridge.lua` 的 `WAIT_MS` |
| 清理完成后冷却 | 500 ms | `bridge.lua` 的 `GAP_MS` |
| 清理 / 等待状态检查 | 100 ms | `bridge.lua` 的 `POLL_MS` |
| CC 接通后等待 PCM | 3 秒 | `config.cc_audio_start_timeout_ms` |
| CC 挂断释放确认 | 10 秒 | `cc_main.lua` |
| 无 PCM 异常恢复清理上限 | 3 秒 | `bridge.lua` 的 `RECOVERY_MS` |
| 配置响应提交后的重启宽限 | 至少 3 秒 | `aircloud_protocol.lua` |
| 云状态上报 | 约 30 秒 | `aircloud_protocol.lua` |
| 云连接 / 认证尝试上限 | 约 30 秒 | `aircloud_protocol.lua` |
| 云失败后重试间隔 | 约 10 秒 | `aircloud_protocol.lua` |
| TCP keepalive | 空闲 60 秒、间隔 10 秒、次数 3 | 云初始化参数 |

### 10.2 拨号失败与释放超时

- `cc.dial` 正常返回失败：记录 `dial_failed`、原因、初始化状态和拨号前后 PCM 快照，按明确失败路径收尾。
- `cc.dial` 抛出异常：无法证明底层未提交拨号，因此请求挂断并等待终结事件。
- 媒体启动超时或媒体故障：发起挂断，继续等待 CC 终结；不能直接改成空闲。
- 挂断后 10 秒仍未确认：状态变为 `cc_release_error`，打印 `CC_RELEASE_TIMEOUT`，发布 `CC_RELEASE_FAILED`。
- 收到匹配当前会话的真正终结事件后，才完成对应通话收尾；旧会话消息不应终结新会话。

### 10.3 为什么 cc_idle 之后还可能等待

业务通话状态与媒体资源释放是两层条件。`cc_main.is_media_idle()` 还检查 `active`、`media_ready`、`dl_queued`、`ul_queued`、`sdk_active`、`sdk_pending`、`sdk_stop_waiting` 均为零，且统计结构有效、PCM 模式已选中。

旧通话清理还需 SIP 侧终结并确认媒体停止。若只看到 `cc_idle` 就立即发起新拨号，可能忽略仍在释放中的媒体资源；应观察 `旧通话清理完成`、冷却结束和完整云状态。

### 10.4 连续无真实 PCM 的检测

统计对象是接通后当前媒体阶段的 `cc.bridgePcmStats().dl_pushed` 增量。早期媒体、上传静音或上一次通话的计数不能代替当前接通阶段的真实下行 PCM。

默认规则：当前接通媒体阶段至少持续 2000 ms，结束时仍未见真实下行增量，才计入连续异常；达到 3 通时发布 `CC_BRIDGE_MEDIA_ANOMALY`，原因为 `NO_MODEM_PCM`。统计未知或无效时不按缺 PCM 通话处理；看到有效增量会清除连续异常计数。

`cc_media_min_connected_ms` 或 `cc_media_missing_call_limit` 不大于 0 时关闭这项统计。`cc_media_reboot_on_error=false` 保留异常报告但不自动重启。默认开启恢复时先清理，清理完成或最多等待 3 秒后重启。

---

## 十一、常见故障与排查顺序

| 现象 / 日志 | 首先检查 | 下一步 |
| --- | --- | --- |
| 开机版本仍旧 | Luatools 实际下载列表和 `main.lua` | 重新添加最新脚本，确认 `1.1.18` |
| `excloud missing or incompatible` | 下载列表是否包含 excloud | 核对 `/luadb/excloud.lua` / `.luac`、平铺路径及固件字节码兼容 |
| `module ... not found` | 是否遗漏子目录脚本或标准库 | 重新收集依赖，避免只下载根目录 |
| 入口配置加载失败 | fskv 是否可用 | 核对固件能力及初始化日志 |
| `migration_warning` | 默认手机号仍为占位符，或旧映射无效 | 填有效号码并提交完整映射 |
| 一直无 IP | SIM 数据业务 / WiFi 热点 / 所选驱动 | 检查对应网卡日志及 DNS 条件 |
| `firmware_missing_*` | 固件接口或统计字段不匹配 | 按第二节具体错误选择配套固件 |
| `SIP 启动完成` 但未注册 | 实际服务器、域、账号、密码、端口、传输 | 看 `event register`，与保存配置对照 |
| 注册成功但 SIP 来电不拨手机 | 183 和 VoIP started 是否都确认 | 若未确认先查媒体；已确认再查 CC 拨号 |
| `cc.dial 失败` | 手机号、SIM 语音业务、CC 就绪 | 保留 `cc_dial_error` 及 `dial PCM before/after` 日志 |
| 手机来电但 SIP 对端不响 | `remote_sip_uri`、对端注册、自动处理开关 | 检查 `呼入场景：拨打 SIP` 和 SIP 拒绝 / 超时日志 |
| 手机拨入后迟迟不被接听 | SIP 对端是否真正接听且媒体就绪 | 该流程会先等 SIP，再接听 CC |
| `CC 音频通道启动超时` | 接通事件后 PCM 是否启动 | 查看 PCM 故障快照及 SDK 上传快照 |
| 双方接通但单向 / 无语音 | 实际协商编码、RTP、PCM 下行及上传状态 | 对照 `CC PCM stats`、媒体会话与网络条件 |
| `远端音频提交失败` | 当前播报调用本来被注释 | 确认随后恢复双向语音；不要先归因于注册失败 |
| G729 / G722 无提示音 | 当前配置会跳过提示流程 | 以实际双向语音验收编码 |
| `CC_RELEASE_TIMEOUT` | CC 未收到匹配的终结确认 | 保留会话号和 PCM / SDK 状态，不强制伪造空闲 |
| 第二通无法建立 | 清理、冷却、媒体 / SDK 队列是否仍占用 | 查询完整桥接状态，而非只查 registered |
| 保存配置后没有立即重启 | 响应发送、宽限期、忙线及媒体状态 | 对照第九节 `reboot waiting` 原因 |
| 修改 config.lua 后仍连旧服务器 | fskv 已保存值覆盖默认值 | 查询 `get_sip_config`，使用新请求 ID 更新配置 |
| 同一命令改值后没执行 | 是否复用了缓存中的 `id` | 每次新操作使用新 ID |
| get_status 收到三段失败 | battery / location / audio 在本项目不支持 | 分开检查 sip 分区 |
| 云端收到 hex 字符串而非完整 JSON | 收到大消息分片 | 按第八节先组装再解析 |
| 云端不能改音量或播放 TTS | 当前 `capabilities` 明确不支持 | 按能力表控制界面可操作项 |
| WiFi 下 SIP 正常但云不连接 | 云任务仍要求 `socket.LWIP_GP` 就绪 | 单独检查 4G 数据网卡；当前代码未提供纯 WiFi 云连接流程 |
| 接通多次后自动重启 | 是否 `NO_MODEM_PCM` | 查看逐通阶段时长、`dl_pushed` 增量和连续计数 |

提交问题时建议一起提供：项目 / 固件版本、所选网络、SIP 传输与编码、来电方向、从开机至故障的完整日志、`get_sip_status` 结果、最近是否修改云配置。仅一条“无声”或“拨号失败”日志通常无法区分注册、呼叫、媒体及释放阶段。

---

## 十二、真机验收清单

以下是建议执行的测试，不表示本次文档修改已经完成真机验收。

| 编号 | 操作 | 预期检查 |
| --- | --- | --- |
| T01 | 冷启动并检查版本 | `1.1.18`，无缺库，CC 初始化和 SIP 注册成功 |
| T02 | 查询云端状态 / 配置 | 能关联请求 ID，密码不回传，能力表符合当前设备 |
| T03 | SIP 呼叫手机并接听 | 先 183 / 媒体，再拨手机，接通后双向语音 |
| T04 | 手机拨入设备 SIM | SIP 对端振铃、接听后 CC 被接听，双向语音 |
| T05 | 分别由两端挂断并再次拨打 | 对端结束、资源释放、可继续建立下一通 |
| T06 | SIP 来电转接过程中取消 | 不残留错误外呼，不影响下一通 |
| T07 | 手机拒接 / 无语音业务卡拨号 | 错误上报和收尾符合实际终结条件 |
| T08 | 旧通话未清理时重拨、忙线时再呼入 | 等待 / 拒绝行为符合第六节，无串话 |
| T09 | 仅修改手机号并保持同一 SIP peer | 下一次 SIP 来电使用新号码，当前通话不变 |
| T10 | 通话中提交 SIP 配置 | 保存并回包，通话和媒体空闲后重启，重新注册 |
| T11 | 读取大配置和 get_status | 分片可组装，四分区响应不会互相覆盖 |
| T12 | 同 ID 重发，再用新 ID 修改 | 同 ID 复用响应，新 ID 执行新操作 |
| T13 | PCMA / PCMU / G729 / G722 分别通话 | 固件支持所选编码，双向语音及收尾正常 |
| T14 | 按需切换 WiFi / TLS | 网卡一致，TLS 校时与证书通过，SIP 和云分别验证 |
| T15 | `.luac` 烧录后冷启动 | 动态加载 excloud 和标准库无异常 |

建议记录每项使用的固件版本、网络、SIM 条件、编码、日志和结果，避免把一种编码或一种网络下的成功当成全部路径都已验证。

---

## 十三、版本与源码维护

### 13.1 当前版本要点

- `1.1.18` 增加 excloud 静态依赖声明，解决动态加载方式可能导致 Luatools 漏收库的问题；升级时必须重新核对下载列表。
- CC 明确拨号失败后进行收尾；无法确认释放时等待 10 秒并报告 `cc_release_error`，继续保留 PCM / SDK 释放检查。
- AirCloud 固定使用 TCP；SIP 的 UDP / TCP / TLS 独立配置。
- `lib/excloud.lua` 与 `cloud/aircloud_tcp_adapter.lua` 均需烧录，业务兼容逻辑集中在适配层。
- 当前无内置网页、产测串口命令、Modbus、屏幕 UI 或 FOTA 应用模块；这些功能不能从参考工程推定到本目录。

### 13.2 仓库与外部同步流程

本目录路径：`module/Air8783H/project/sip_cc_web/`。

原工程说明记录的外部源码路径为：

```text
D:\Air\Documents\SIP_web\8783H\sip_cc_bridge_pcm
```

原同步命令是在对应外部工作区执行：

```text
python 8783H/sip_cc_bridge_pcm/prepare_download.py
```

当前目录不包含该同步脚本。继续使用外部同步流程时，应先核对脚本实际存在及输出目标，再按原流程修改源代码、重新同步和校验烧录文件；不能把上面的相对命令直接视为本仓库可运行命令。原说明称同步会保留 README，实际以所用脚本行为为准。

修改后同步维护 `main.lua` 版本、默认配置、烧录清单及本文。当前文档基于目录中的代码核对，历史“桌面测试已通过”的说明不替代当前版本在 Air8783H 上的通话、字节码加载、云端与媒体释放验收。
