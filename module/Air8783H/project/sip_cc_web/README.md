# Air8783H 出厂工程：SIP / 蜂窝通话 PCM 桥接（Air8783H_Factory）

基于 Air8783H 的纯 PCM 语音桥接工程，实现「SIP 终端 ↔ SIP 信令 / RTP ↔ 设备 PCM 桥接 ↔ 蜂窝通话（CC）↔ 手机」，并通过 AirCloud 提供状态查询、SIP 参数配置、手机号与 SIP 对端映射，以及合宙 IoT 平台 FOTA 升级。

- 项目名（PROJECT）：`Air8783H_Factory`
- 项目版本（VERSION）：`001.000.001`
- 版本依据：[main.lua](main.lua)
- 默认网络：4G；可选 WiFi STA
- SIP 信令：UDP / TCP / TLS，当前默认 UDP
- 媒体编码：PCMA / PCMU / G729 / G722，当前默认 PCMA，固定 20 ms 帧长
- 云服务：AirCloud TCP，标准 `excloud` 库与项目 TCP 适配层
- 升级：标准 `libfota3`，自动检测周期 8 小时，支持云端手动触发
- 外部看门狗：Air153C，GPIO23，180 秒喂狗

**当前实现范围：** `sip_cc_web` 是设备端脚本工程，目录中没有 HTML 页面、HTTP 服务端或屏幕 UI。本文“云端指令”指通过 AirCloud TLV 通道下发的业务内容，不是访问设备 IP 的 REST 接口。FOTA 使用平台升级包；云指令不直接接收下载 URL。

## 使用顺序

1. 首次使用先看第二节硬件和固件要求。
2. 按第三、四节配置网络、SIP 账号和实际接听号码。
3. 按第五节收集脚本、标准库与资源，烧录并检查日志。
4. 按第六节验证两个方向的通话，再进行云端配置和升级。
5. 云端联调看第七至九节；FOTA 看第十节；失败排查看第十一、十二节。

---

## 一、功能模块介绍

### 1.1 目录结构

```text
sip_cc_web/
├── main.lua                      PROJECT / VERSION / PRODUCT_KEY 与启动入口
├── sip_cc/
│   ├── config.lua                SIP、号码、网卡、媒体、看门狗默认值
│   ├── sip_cc_app.lua            等待网络、TLS 校时、CC / SIP 初始化
│   ├── sip_main.lua              SIP 注册和呼叫状态、业务事件
│   ├── cc_main.lua               蜂窝呼叫、PCM 启停、释放与异常统计
│   ├── pcm_sip.lua               exsipclient 信令与 VoIP 媒体适配
│   ├── bridge.lua                双向通话协调、清理、等待、冷却、恢复
│   └── air153c_wdt.lua           Air153C 外部看门狗封装
├── cloud/
│   ├── aircloud_app.lua          状态汇总、空闲判断、升级和云服务启动
│   ├── aircloud_protocol.lua     指令、响应、分片、上报和配置重启
│   ├── aircloud_settings.lua     参数校验、fskv 保存、能力及生效判断
│   ├── sos_config.lua            号码 / SIP 对端映射及协议格式
│   └── aircloud_tcp_adapter.lua  隔离加载 excloud 与 TCP 兼容
├── ota/
│   └── update.lua                libfota3 配置、手动检查、下载和重启确认
├── netdrv/
│   ├── netdrv_device.lua         网络选择入口
│   ├── netdrv_4g.lua             4G IP 事件、DNS
│   └── netdrv_wifi.lua           WiFi STA 配置、事件和 DNS
├── lib/
│   └── httpplus.lua              项目保留的 HTTP 扩展库版本
├── audio/
│   └── Time_travel_8k.mp3        通话提示音测试资源
├── certs/
│   └── sip-ca.pem                SIP TLS CA 资源
└── README.md                     本说明，不烧录
```

目录用于电脑端分类，设备端按文件名平铺加载。模块内 `require "config"`、`require "update"` 不带子目录。资源也按原名放入脚本区：

| 电脑端文件 | 设备端用途 / 路径 |
| --- | --- |
| `main.lua` | 启动入口 |
| `sip_cc/config.lua` | `require "config"` |
| `ota/update.lua` | `require "update"` |
| 仓库标准 `excloud.lua` | `/luadb/excloud.lua` 或 `/luadb/excloud.luac`，由适配层加载 |
| `audio/Time_travel_8k.mp3` | `/luadb/Time_travel_8k.mp3` |
| `certs/sip-ca.pem` | `/luadb/sip-ca.pem` |

不要把资源只放到 `/luadb/audio/`、`/luadb/certs/`，当前配置使用的是上表中的平铺路径。不同来源的同名库只能保留一个明确版本。

### 1.2 模块职责与排查入口

| 文件 | 主要工作 | 重点关注 |
| --- | --- | --- |
| `main.lua` | 加载系统库和已保存配置，启动看门狗、网络、桥接和云服务 | 项目名、版本、PRODUCT_KEY、配置加载顺序 |
| `config.lua` | 提供首次运行的默认值 | 已保存配置可能覆盖默认 SIP 参数 |
| `sip_cc_app.lua` | 等网络，TLS 时先校时，再依次初始化 CC / SIP | 不能把 SIP 初始化成功当成注册成功 |
| `sip_main.lua` | 将信令与媒体事件组合为可用的通话状态 | 同时确认信令和媒体就绪 |
| `pcm_sip.lua` | 注册、SDP 媒体参数、VoIP 启停及 RTP 统计 | 会话身份、编解码、网络丢失、停止确认 |
| `cc_main.lua` | 蜂窝拨号 / 接听 / 挂断，PCM 状态与 SDK 释放 | `cc.dial` 错误、音频启动超时、释放超时 |
| `bridge.lua` | 协调双侧，防止旧通话干扰新通话 | 等待、清理、冷却、NO_MODEM_PCM 恢复 |
| `aircloud_app.lua` | 汇总桥接状态，提供共享空闲检查 | 配置重启和 FOTA 都使用该检查 |
| `aircloud_protocol.lua` | 命令、请求去重、队列、分片、定期上报 | ID 重用、回包分片、响应后重启 |
| `aircloud_settings.lua` | 校验并保存配置，生成能力表 | 保存不等于当前连接已应用 |
| `sos_config.lua` | 统一号码数组、映射和镜像字段 | 一组手机号对应一个 SIP 对端 |
| `aircloud_tcp_adapter.lua` | 隔离加载标准 excloud，处理 TCP 收包和兼容 | 缺库、字节码、连接与发送错误 |
| `update.lua` | 配置标准升级库，并在关键阶段确认空闲 | 请求检查、下载、重启、升级结果是不同阶段 |

### 1.3 启动顺序

```text
main.lua
  → 定义 PROJECT / VERSION / PRODUCT_KEY
  → 加载 sys、sysplus
  → aircloud_settings.init("8783H", config)，合并已保存配置
  → 初始化 Air153C 看门狗
  → 加载网络驱动
  → 加载 SIP / CC / bridge，注册事件并创建启动任务
  → 加载 aircloud_app，初始化 update，再启动云协议
  → sys.run()

桥接启动任务：
等待 IP_READY，最多 10 秒
  → TLS 模式等待 NTP_UPDATE，最多 10 秒
  → cc_main.init()
  → sip_main.init()
  → 等待实际注册成功后进行通话
```

网络等待超时只打印警告并继续尝试初始化。TLS 校时超时则结束该启动任务；CC 或 SIP 初始化失败也停止后续桥接启动。云服务和升级任务有各自的执行流程，不能用其中一个任务启动成功代替其他服务验收。

---

## 二、硬件配置与固件要求

### 2.1 演示准备

| 项目 | 数量 | 要求 |
| --- | --- | --- |
| Air8783H 设备及匹配供电 | 1 套 | 使用实际硬件配套的底层固件 |
| SIM 卡 | 1 张 | 蜂窝通话需语音业务；默认 4G 联网还需数据业务 |
| 手机 | 1 部 | 接听目标外呼、拨打设备 SIM 号码 |
| SIP 终端 | 1 个 | 可向设备账号发起呼叫，也可接听设备呼叫 |
| SIP 服务 | 1 套 | 为设备和对端提供可用账号，端口、域和传输方式一致 |
| 电脑及下载连接 | 1 套 | Luatools 烧录及完整日志采集 |
| 2.4 GHz WiFi 热点 | 可选 | 切换 SIP 至 WiFi STA 时使用 |
| Air153C 看门狗 | 按整机配置 | 默认喂狗引脚 GPIO23 |
| 合宙 IoT 平台升级项目 | FOTA 时需要 | 项目 Key、设备、基础包、目标包及升级任务对应 |

本工程使用固件内 CC / VoIP PCM 通路交换音频，没有本地 LCD、触摸、麦克风驱动或扬声器播放界面。音频是否正常应在手机和 SIP 对端分别验收。

### 2.2 必要固件接口

目录未提供底层固件，也未指定可确认的最低固件版本号。应根据初始化错误核对配套接口：

| 接口 / 能力 | 用途 | 典型错误 |
| --- | --- | --- |
| `cc.init` | 蜂窝初始化 | `cc_unavailable` |
| `cc.AUDIO_MODE_BRIDGE_PCM` | 纯 PCM 模式 | `firmware_missing_bridge_pcm` |
| `mcu.ticks2(1)` | 单调时间及会话计时 | `firmware_missing_monotonic_clock` |
| `cc.bridgePcmStats()` | PCM、队列与 SDK 状态 | `firmware_missing_pcm_stats:<字段>` |
| `cc.bridgeAudioStop()` | 停止当前媒体 | `firmware_missing_bridge_audio_stop` |
| `voip.setAudioMode` / `AUDIO_MODE_BRIDGE` / `pcmIn` / `pcmOut` | VoIP 桥接 | `firmware_missing_voip_bridge` |
| `voip.PCMA/PCMU/G729/G722` | 所选编码 | `firmware_missing_voip_<编码>` |
| `fskv` | 持久化配置 | 配置初始化和保存失败 |
| HTTP / FOTA 相关能力 | 平台检查、下载及写入 | 结合 libfota3 日志判断 |

`cc.bridgePcmStats()` 需包含布尔值 `selected`，以及有效非负整数 `session`、`active`、`media_ready`、`fault`、`dl_pushed`、`dl_queued`、`ul_queued`、`sdk_active`、`sdk_pending`、`sdk_stop_waiting`、`sdk_fault`、`sdk_stop_timeout`。有同名 API 但返回结构不兼容也会初始化失败。

### 2.3 外部看门狗

```lua
config.WDT_CONFIG = {
    ENABLE = true,
    FEED_PIN = 23,
    FEED_INTERVAL = 180, -- 秒
}
```

封装调用 `exair153x_wdt.init`，将 GPIO 与周期传给扩展库。硬件未接此看门狗时可设 `ENABLE=false`；实际引脚变化时修改 `FEED_PIN`。日志应显示初始化成功及周期，或明确显示未启用。外部看门狗不替代桥接资源清理与媒体异常检测。

---

## 三、网络配置

### 3.1 默认 4G

`netdrv/netdrv_device.lua`：

```lua
require "netdrv_4g"
-- require "netdrv_wifi"
```

`config.lua` 对应：

```lua
adapter = socket.LWIP_GP,
```

确认设备获得 4G IP，再检查 SIP 注册和 AirCloud 登录。数据网已连接不代表 SIM 已开通语音业务。

### 3.2 切换 WiFi STA

同时修改三个位置：

1. `netdrv_device.lua` 只启用 `require "netdrv_wifi"`。
2. 在 `netdrv_wifi.lua` 填实际热点：

```lua
WIFI = {
    ssid = "YOUR_WIFI_SSID",
    password = "YOUR_WIFI_PASSWORD"
}
```

3. `config.lua` 设置：

```lua
adapter = socket.LWIP_STA,
```

使用 2.4 GHz 热点，添加 `exnetif` 及其依赖。查看 WiFi `IP_READY` 和 `pcm_sip` 实际网卡日志。WiFi 承载 SIP 数据时，手机侧通话仍依赖 SIM 语音业务。

**云端限制：** 当前 `aircloud_protocol.lua` 固定检查 `socket.adapter(socket.LWIP_GP)`，4G 未就绪时不会正常推进云连接。标准 excloud 创建连接使用系统默认网卡，不读取 SIP 的 `config.adapter`。仅把 SIP 改成 WiFi 不能证明纯 WiFi 条件下 AirCloud 可用，需分别验证。

### 3.3 DNS、传输和时间

| 项目 | 当前设置 | 配置位置 |
| --- | --- | --- |
| DNS | `223.5.5.5`、`114.114.114.114` | 两份网络驱动，获得对应 IP 后设置 |
| SIP 信令 | 默认 UDP，可选 TCP / TLS | `config.sip_transport` |
| RTP 本地端口 | `40000` | `config.rtp_port` |
| AirCloud | TCP，与 SIP 传输独立 | `aircloud_protocol.lua` |
| TLS 启动校时 | SNTP，等待 NTP_UPDATE 最多 10 秒 | `sip_cc_app.lua` |
| FOTA 时间同步 | 标准升级库管理 | `libfota3` |

专网卡或国外网络按驱动注释调整公共 DNS。SIP 注册成功、AirCloud 在线和升级服务可达是三项独立检查。

---

## 四、SIP 账号、号码与音频配置

### 4.1 四个号码 / 账号不要混淆

| 名称 | 用途 |
| --- | --- |
| 设备 SIP 账号 `sip_username` | 设备注册使用，SIP 对端呼叫此账号 |
| SIP 对端 `remote_sip_uri` | 手机拨入设备后，设备呼叫的目标 SIP 终端 |
| `target_phone_number` | SIP 来电后，设备拨出的手机号码 |
| 设备 SIM 号码 | 手机主动呼入时实际拨打的号码，不是目标手机号码 |

例如设备账号为 `device001`、对端为 `operator001`，则设备注册使用前者，转呼 URI 使用 `sip:operator001@<实际域名>`。目标手机号须改成现场接听手机；当前代码已填测试号码，不能直接用于其他设备部署。本文不复制该具体号码。

### 4.2 默认连接参数

| 参数 | 当前值 / 规则 |
| --- | --- |
| `sip_server_addr` | `cc.luatos.com` |
| `sip_server_port` | `8910`，换服务器时按实际监听端口填写 |
| `sip_domain` | `cc.luatos.com`；空字符串时回退服务器地址 |
| `sip_username` | `hmeta.devid() .. "0"` |
| `sip_password` | 当前示例值 `123456`，按服务端账号配置 |
| `sip_transport` | `udp`；支持 `tcp` / `tls` |
| `remote_sip_uri` | `sip:` + 设备 ID + `1@cc.luatos.com` |
| `target_phone_number` | 当前测试号码，部署前替换 |
| `adapter` | `socket.LWIP_GP` |
| `auto_answer_sip` | `true`，推进 SIP 来电桥接流程 |
| `auto_handle_mobile_incoming` | `true`，手机来电后自动转呼 SIP |

这两个自动流程开关与云端的 `sip.auto_answer` / `sip.delay_auto_answer` 不是同一组控制项。关闭本地自动流程后不会出现手动接听 UI。

### 4.3 编码与媒体参数

| 参数 | 默认值 | 实际作用 |
| --- | --- | --- |
| `codec` | `PCMA` | 默认单编码 |
| `codecs` | 注释状态 | 非空列表启用后优先于 `codec` 传入 SIP |
| `ptime` | `20` | 只接受 20 ms，其他值报 `bridge_requires_20ms` |
| `rtp_port` | `40000` | 本地媒体端口 |
| `cc_audio_start_timeout_ms` | `3000` | CC 接通后媒体启动等待；不大于 0 时不启动该超时 |
| `cc_media_min_connected_ms` | `2000` | 当前接通媒体阶段达到此时长才计入无 PCM 统计 |
| `cc_media_missing_call_limit` | `3` | 连续无真实下行 PCM 通话阈值 |
| `cc_media_reboot_on_error` | `true` | 达到异常条件后进行恢复重启 |

| 编码 | 媒体 PCM 采样率 | 别名 |
| --- | --- | --- |
| PCMA | 8 kHz | PCMA |
| PCMU | 8 kHz | PCMU |
| G729 | 8 kHz | 支持 G.729 |
| G722 | 16 kHz | 支持 G.722 |

多编码示例，放在 `config` 表内：

```lua
codecs = {"PCMU", "PCMA", "G729", "G722"},
ptime = 20,
```

`pcm_sip.lua` 内部默认注册有效期 600 秒、呼叫超时 30 秒。当前 `sip_main.lua` 没有透传 `config.expires` / `config.call_timeout`，只在配置中增加同名字段不会改变内部默认值。

### 4.4 TLS 与媒体加密

1. 将 `sip_transport` 改成 `tls`，端口改为服务器实际 TLS 端口。
2. 核对 CA 与服务器证书链匹配，并烧录证书。
3. 启用配置：

```lua
sip_tls = {ca_cert = io.readFile("/luadb/sip-ca.pem")},
media_encryption = "none",
```

4. 开机确认网络校时完成，再检查注册。
5. 需要加密媒体时，按服务端与固件能力配置 `sdes` 或 `dtls-srtp`，另行验证音频链路。

TLS 信令成功不代表 RTP 已加密。云端当前不支持直接上传证书，也不支持写入 `sip_tls`、`media_encryption`、编码和 RTP 端口，这些需通过本地配置及升级包维护。

---

## 五、Luatools 烧录与启动验收

### 5.1 必须添加的文件

1. 选择适配硬件和 PCM 桥接 API 的底层固件。
2. 添加根目录 `main.lua`。
3. 添加 `sip_cc/`、`cloud/`、`netdrv/`、`ota/` 下全部 Lua 文件。
4. 添加项目 `lib/httpplus.lua`，避免再添加其他同名版本覆盖。
5. 添加音频及证书资源，核对平铺后的名称。
6. 收集标准扩展库，并按下表人工检查关键依赖。
7. 排除 `README.md`，确认没有重名文件后烧录。

| 依赖 | 来源 | 说明 |
| --- | --- | --- |
| `sys`、`sysplus` | 仓库 `script/corelib/` | 任务与消息 |
| `exsipclient`、`exsipproto` | 仓库 `script/libs/` | 同时收集其下级依赖 |
| `excloud` | 仓库 `script/libs/excloud.lua` | **当前项目 lib 下已没有该文件，必须补入下载列表** |
| `libfota3` | 仓库 `script/libs/libfota3.lua` | `ota/update.lua` 直接 require，不能因暂不升级就漏掉 |
| `exair153x_wdt` | 仓库 `script/libs/` | 看门狗 |
| `exnetif` | 仓库 `script/libs/` | WiFi 驱动使用 |
| `httpplus` | 当前工程 `lib/httpplus.lua` | 保留项目版本，不重复导入同名库 |

标准 excloud 与 libfota3 使用原版库；项目兼容和升级控制分别放在 `aircloud_tcp_adapter.lua`、`ota/update.lua`。

### 5.2 excloud 动态加载的注意事项

TCP 适配层通过 `loadfile` 隔离加载 excloud，同时保留供 Luatools 扫描识别的静态声明：

```lua
if false then
    require "excloud"
end
```

该声明不执行第二个实例。更换脚本后重新添加依赖，不要复用漏库的旧列表。适配层尝试 `/luadb/excloud.luac`、`/luadb/excloud.lua` 等路径；出现 `excloud missing or incompatible` 时，核对实际下载列表、平铺路径和字节码兼容。

### 5.3 开机核对

| 阶段 | 日志 / 状态 | 结论 |
| --- | --- | --- |
| 入口 | `Air8783H_Factory`、`001.000.001` | 当前脚本版本 |
| 看门狗 | 初始化成功或明确未开启 | 配置与硬件一致 |
| 网络 | 对应网卡 `IP_READY` | 获得数据网络 |
| CC | `CC 初始化完成 bridge_pcm` | CC PCM 初始化成功 |
| SIP 参数 | `SIP registration target`、`SIP codecs` | 核对运行时实际参数 |
| SIP 启动 | `SIP/CC 桥接应用启动成功` | 启动调用完成，还未证明注册 |
| SIP 注册 | `event register ok` 或 `registered=true` | 注册成功 |
| 云端 | `boot/status` 或查询响应 | AirCloud 单独验收通过 |
| 升级 | `fota` / `libfota3` 状态 | 与普通云连接独立核对 |

已有 fskv 配置时，新烧录的默认账号可能不会使用。通过 `get_sip_config` 核对保存值，不要只查看电脑上的 `config.lua`。

---

## 六、双向通话流程与测试

### 6.1 SIP 呼入转拨手机

前提：设备完成 SIP 注册，目标手机可接听，SIM 有语音业务，`auto_answer_sip=true`。

1. SIP 终端呼叫设备的注册账号。
2. 设备记录本通目标号码，等待旧通话资源释放及冷却结束。
3. 发送 SIP 183，并等待 VoIP 实际 started。
4. 两项均确认后才拨打 `target_phone_number`。
5. 手机接听；CC 接通且 PCM 就绪后，请求 SIP 正式应答。
6. SIP 信令与媒体都就绪，两端进入通话。
7. 任一端挂断，另一端随之收尾，待资源释放后再次呼叫。

```text
SIP INVITE
  → SIP 183 + VoIP started
  → CC 拨打目标手机
  → 手机接通 + CC PCM 就绪
  → SIP 正式应答 + 媒体就绪
  → 双向语音
```

观察日志：`SIP 来电` → `旧通话已释放，启动 SIP 183` → `183 和 VoIP started 已确认，拨打手机` → `CC 已接通且 PCM 通道就绪`。

有来电却不拨手机时，先判断是否到达“183 和 VoIP started 已确认”。未到达重点检查 SIP 媒体；已到达但拨号失败则看 SIM、号码和 CC 错误。

### 6.2 手机呼入转拨 SIP

前提：`remote_sip_uri` 指向已注册对端，`auto_handle_mobile_incoming=true`。

1. 手机拨打设备的 SIM 号码。
2. CC 收到来电后等待桥接资源可用。
3. 设备呼叫 `remote_sip_uri`，SIP 对端应振铃。
4. SIP 对端接听且媒体就绪，设备才接听蜂窝来电。
5. CC PCM 就绪后建立双向语音。
6. 分别测试手机挂断和 SIP 对端挂断。

```text
手机来电 → 转呼 SIP → SIP 对端接听且媒体就绪
  → 接听 CC → CC PCM 就绪 → 双向语音
```

观察日志：`手机来电，等待桥接可用` → `呼入场景：拨打 SIP` → `执行接听` → `CC 已接通且 PCM 通道就绪`。

### 6.3 忙线、取消和第二通

| 场景 | 行为 |
| --- | --- |
| 已有活动 / 等待呼叫再来 SIP 呼叫 | 一般返回 486 Busy Here |
| 故障恢复中来 SIP 呼叫 | 480 Temporarily Unavailable |
| 新来电等待旧通话释放 | 最多 3 秒；超时拒绝 SIP 来电或请求挂断蜂窝等待来电 |
| 等待中的 SIP 来电取消 | 结束该等待，不改变旧通话清理过程 |
| 一端挂断 | 另一端停止，继续等待各自终结及媒体释放 |
| 清理完成 | 冷却 500 ms 后允许推进下一通 |

必须验证“再次呼叫成功”，不能只以第一通有声为验收结果。`cc_idle` 是业务状态，不能单独证明 PCM / SDK 队列已释放。

### 6.4 提示音当前行为

`bridge.lua` 设置目标 `both`、文件 `/luadb/Time_travel_8k.mp3`、延时 500 ms，并保留 TTS 文本。但当前 `voip.playFile` / `voip.playTTS` 调用均被注释。

默认可能执行“桥接静音 → 等待 500 ms → 远端音频提交失败 → 恢复双向语音”，不会实际播放 MP3。按 `config.codec` 判断为 G729 / G722 时跳过提示流程。只烧录音频文件或修改文件名不能开启播报，也不能把该日志当成 SIP 注册失败。

---

## 七、AirCloud 指令与配置示例

### 7.1 请求约定

普通业务请求格式：

```json
{"id":"status-001","cmd":"get_sip_status"}
```

| 项目 | 规则 |
| --- | --- |
| `id` | 字符串，1～64 字节，不含控制字符 |
| `cmd` | 字符串，命令见下表 |
| `params` | `set_config` 需要非空对象 |
| 长度 | 原始 JSON 最多 1396 字节 |
| 下发字段 19 | 响应字段 20，data_type=3 |
| 下发字段 1281 | 响应字段 1281，data_type=5 |
| 去重 | 最近 32 个 ID 缓存响应，重复 ID 不重新执行 |

修改参数或失败后重试，应使用新 ID。相同 ID 即使换参数仍会得到原响应。不是所有无效内容都返回错误：不能解析的普通 JSON、缺少 cmd 且非兼容升级指令的内容，可能直接不被业务处理。

### 7.2 命令汇总

| 命令 | 功能 | 返回重点 |
| --- | --- | --- |
| `get_sip_status` | 当前注册与桥接状态 | 通话、清理、待重启、能力 |
| `get_sip_config` | 已保存配置 | SIP、号码映射，不含密码 |
| `get_status` | 四分区综合查询 | SIP / battery / location / audio |
| `set_config` | 校验保存 SIP / 映射参数 | 保存值、是否需要重启 |
| `update` / `fota` | 请求平台升级检查 | ok、error、stage，见第十节 |
| `get_location` / `speak_battery` / `play_tts` | 当前不支持 | unsupported_feature |
| 其他命令 | 未定义 | unknown_command |

### 7.3 查询状态与配置

```json
{"id":"status-002","cmd":"get_sip_status"}
```

以下为注册成功且空闲时的**部分响应示意**，不是实际抓包，省略公共元数据和能力表：

```json
{
  "type": "response",
  "id": "status-002",
  "cmd": "get_sip_status",
  "ok": true,
  "result": {
    "registered": true,
    "connected": false,
    "in_call": false,
    "sip_state": "sip_idle",
    "cc_state": "cc_idle",
    "waiting": false,
    "cleanup_pending": false,
    "cooldown_remaining_ms": 0,
    "recovering": false,
    "reboot_pending": false
  }
}
```

配置查询：

```json
{"id":"config-001","cmd":"get_sip_config"}
```

返回值去除 `sip_password`。重点看保存的连接字段、`sos_sip_cc_numbers`、`sos_sip_cc_peers` 和 pending 状态；保存值不一定已应用于当前连接。

### 7.4 修改 SIP 连接

将示例地址和账号替换为现场配置后下发：

```json
{
  "id": "sip-save-001",
  "cmd": "set_config",
  "params": {
    "sip": {
      "sip_server_addr": "sip.example.com",
      "sip_server_port": 5060,
      "sip_domain": "sip.example.com",
      "sip_username": "device001",
      "sip_password": "YOUR_SIP_PASSWORD",
      "sip_transport": "udp"
    }
  }
}
```

| 可写字段 | 校验规则 |
| --- | --- |
| sip_server_addr | 非空 UTF-8 字符串，最多 253 字节，无控制字符 |
| sip_domain | UTF-8 字符串，最多 253 字节，可为空，无控制字符 |
| sip_username / sip_password | 非空 UTF-8 字符串，最多 128 字节，无控制字符 |
| sip_server_port | 整数 1～65535，不是数字字符串 |
| sip_transport | 小写 udp / tcp / tls |
| auto_answer | 布尔值，仅兼容保存 |
| delay_auto_answer | 整数 0～20，仅兼容保存 |

可只提交需修改的 SIP 字段，但提交任一连接字段，即使值没有变化，也会锁存空闲重启请求。`codec`、`adapter`、`rtp_port`、`sip_tls`、`media_encryption` 等不在此写接口内。

### 7.5 修改手机号与对端映射

本项目只支持一组手机号对应一个 SIP 对端。示例号码仅演示格式，使用时替换为现场号码：

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

| 字段 | 规则 |
| --- | --- |
| sos_mode | 仅支持 sip_cc，建议显式提供 |
| sos_sip_cc_numbers | 一项手机号字符串数组；最多 32 字节，可选前导 +，其余为数字 |
| sos_sip_cc_peers | 等长 SIP 账号数组；最多 64 字节，字母数字及 `+ * # _ . -` |
| sos_numbers | 当前号码的镜像，可省略；提供时必须一致 |
| sos_sip_cc_map | 派生映射，可省略；提供时必须一致 |
| 其他模式列表 | 省略或空数组，不要同时配置多个模式 |

修改手机号仍需同时提交 peer；peer 填账号 `operator001`，不是完整 `sip:operator001@example.com`。完整派生表示示例：

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
      {"peer_sip":"operator001","numbers":["13800138000"]}
    ]
  }
}
```

启动时用 peer 和保存的 SIP 域生成远端 URI。SOS 字段属于共用云协议命名，不代表本机已提供物理 SOS 按键外呼。

### 7.6 接听兼容字段

```json
{
  "id": "answer-001",
  "cmd": "set_config",
  "params": {"sip":{"auto_answer":true,"delay_auto_answer":3}}
}
```

以上仅保存偏好，**不会改变当前 PCM 桥接的接听时序**。能力表会说明 `compatibility_only_fields`。不要将“保存成功”显示为已启用三秒自动接听。

### 7.7 错误码

| 错误 | 原因 / 处理 |
| --- | --- |
| command_too_large | 指令超过 1396 字节 |
| invalid_command | 已识别请求的 ID / cmd 类型或 ID 内容不合法 |
| unknown_command | 命令未实现 |
| empty_config / invalid_sip | params 或 sip 对象缺失、为空或类型错误 |
| invalid_sip_server_addr / invalid_sip_domain | 字符串内容、编码、长度不合法 |
| invalid_sip_username / invalid_sip_password | 账号密码约束不满足 |
| invalid_sip_server_port / invalid_transport | 端口或传输取值错误 |
| invalid_auto_answer / invalid_delay_auto_answer | 兼容字段类型 / 范围不合法 |
| invalid_sos_mode / ambiguous_sos_mode | 模式无效或无法唯一推断 |
| invalid_sos_sip_cc_numbers / invalid_sos_sip_cc_peers | 号码 / peer 数组无效或不匹配 |
| invalid_sos_number / invalid_sos_peer | 内容格式错误或号码重复 |
| conflicting_sos_fields | 不同模式字段冲突 |
| sos_mirror_mismatch | sos_numbers 与主号码列表不一致 |
| invalid_sos_map / sos_map_mismatch | 派生映射错误 |
| unsupported_feature | 多组映射、不支持字段 / 模式 / 功能，查看 unsupported_fields |
| storage_failed | 持久化失败，不能按已保存处理 |
| fota_not_configured / device_busy | 升级未配置或设备未空闲 |

若已有映射无法迁移，查询中可能出现 `migration_warning`。先提交有效完整映射；当保存模式为空时，仅提交 SIP 字段也可能因模式不支持被拒绝。

---

## 八、状态上报、能力与分片

### 8.1 主动上报

AirCloud 认证后发送 `boot` 快照，随后约每 30 秒安排 `status` 快照。发送受网络和队列影响，不能当作毫秒级通话事件推送。需要当前状态时主动查询 `get_sip_status`。

| TLV 字段 | 含义 |
| --- | --- |
| 1281 | 启动 / 状态 JSON，或经该字段下发的命令响应 |
| 265 | 主动上报工作状态：双端接通为 2，否则为 1 |
| 1280 | 时间有效时附带 Unix 时间戳 |
| 20 | 从字段 19 下发的命令响应 |

公共信封包含：

| 字段 | 含义 |
| --- | --- |
| version | 普通消息 1；get_status 分区响应 2 |
| type | boot / status / response |
| device_id | `hmeta.devid()` |
| timestamp | 当前 Unix 时间戳 |
| report_id | 时间戳及本地递增序号形成的标识 |
| beijing_time / timezone | UTC+8 格式化时间、`UTC+08:00` |
| time_valid | 时间戳是否不早于 2025-01-01，不是独立的 SNTP 成功证明 |
| project / project_version | `Air8783H_Factory` / `001.000.001` |
| id / cmd / ok / error | 响应关联及执行结果；没有值的字段可能省略 |

当前没有把升级进度加入 AirCloud 状态快照，升级细节见 `fota` 日志。

### 8.2 状态字段解释

| 字段 | 含义 / 注意 |
| --- | --- |
| registered | SIP 是否注册成功 |
| connected / in_call | SIP 和 CC 两侧均已接通，不是云连接状态 |
| sip_state | SIP 当前状态，包括 idle、incoming、progressing、dialing、connected、disconnecting 的 `sip_` 前缀值 |
| cc_state | `cc_idle/cc_dialing/cc_ringing/cc_connected/cc_disconnecting/cc_release_error` |
| call_direction | outgoing 为 SIP 来电转拨手机，incoming 为手机来电转 SIP |
| call_duration | 双端接通后的秒数 |
| waiting | 是否有来电等待桥接资源 |
| cleanup_pending | 是否有旧通话待清理 |
| cooldown_remaining_ms | 冷却剩余毫秒数 |
| recovering | 是否进入无真实 PCM 的恢复流程 |
| current_call_id / pending_call_id | 当前 / 等待的 SIP Call-ID，可能省略 |
| state | 通话时 CONNECTED，等待时 WAITING，否则使用 sip_state |
| cc_dial_error | 最近直接拨号失败详情，含原因与 PCM 前后快照 |
| error | 最近直接拨号错误的简要标记，不覆盖全部故障类型 |
| config_pending / reboot_pending | 是否有配置等待重启 |
| reboot_reason | sip_settings_submitted 或 configuration_changed 等 |

`cc_dial_error` 可能在呼叫结束后仍保留，不能仅依据这一历史字段认定当前仍在拨号。结合通话状态、日志时间与 generation 判断。

### 8.3 当前能力

| 能力 | 当前值 |
| --- | --- |
| modes | `["sip_cc"]` |
| max_targets / max_sip_peers | 1 / 1 |
| keys / outgoing_sos | false / false |
| audio | false，不提供本机音量和麦克风增益配置 |
| battery / location / tts | false |
| commands | 状态查询、配置及 update / fota |
| writable_fields | 可写 SIP 和 SOS 字段列表 |
| compatibility_only_fields | sip.auto_answer、sip.delay_auto_answer |
| migration_warning | 默认或旧映射无法完整转换时的提示 |

### 8.4 综合查询的四段响应

```json
{"id":"all-status-001","cmd":"get_status"}
```

产生四个同 ID 的响应，含 `version=2`、`sections=4`，以 `section` 区分：

| section | 当前结果 |
| --- | --- |
| sip | SIP 状态、配置、SOS 状态及能力 |
| battery | unsupported_feature |
| location | unsupported_feature |
| audio | unsupported_feature |

云端按 ID 和 section 收集。收到其中一个分区不代表整个查询结束；三个不支持分区也不代表 SIP 功能失败。

### 8.5 大消息分片

JSON 中的非 ASCII 内容先转为 Unicode 转义。编码后不超过 1100 字节直接发送，超过时按每片最多 500 字节拆分，并对片段做 hex 编码。

| 字段 | 含义 |
| --- | --- |
| type | fragment |
| report_id | 分片组标识，分区响应会附加 `:section` |
| id | 请求 ID；主动上报可能没有 |
| part | 从 1 开始的片序号 |
| parts | 总片数 |
| encoding | hex |
| payload | 本片原始字节的十六进制字符串 |

组装顺序：先按 report_id 分组，再按 part 排序，逐片 hex 解码并拼接字节，最后解析完整 JSON。不要单独解析片段正文，边界可能位于字符串或转义序列中。

---

## 九、持久化配置与生效规则

### 9.1 保存位置与优先级

Air8783H 的 fskv 键为 `aircloud_pcm_v1`。配置初始化先读取 Lua 默认值，若已保存 `unified` 配置则使用保存的 SIP 连接参数和映射；有效映射还会更新运行时手机号及远端 URI。

```text
config.lua 默认参数
  → aircloud_pcm_v1 中的已保存配置
  → 本次启动实际 SIP / 桥接参数
```

重新烧录默认文件不等于删除保存值。当前云协议没有通用恢复出厂 / 清除 fskv 指令，不能把 `update` 或 `set_config` 当作清空配置操作。

### 9.2 不同修改如何应用

| 修改 | 行为 |
| --- | --- |
| 提交任一 SIP 连接字段 | 无论值是否变化，锁存空闲重启请求 |
| 修改 SIP peer | 与开机配置不同时，等待重启应用 |
| 仅修改手机号，连接和 peer 与开机一致 | 更新下一次 SIP 来电使用的目标号码 |
| 通话期间修改手机号 | 当前呼叫使用创建时的号码快照，不改正在进行的呼叫 |
| 兼容接听偏好 | 保存但不改变 PCM 接听行为 |
| 参数错误 / 不支持字段 | 拒绝本次配置，不按部分成功处理 |
| fskv 写入失败 | 返回 storage_failed，不切换成新配置 |

之后仅保存手机号或接听偏好，不会撤销先前 SIP 连接字段触发的重启请求。

### 9.3 空闲重启条件

对于 `reboot_pending=true` 的配置更新，保存成功后，先等待对应配置响应的全部片段提交给发送接口；随后至少等待 3 秒，再执行完整空闲检查。无需重启的号码或兼容偏好更新不会仅因保存成功而重启：

1. 没有等待来电。
2. 没有旧通话清理。
3. 不在恢复流程。
4. 冷却结束。
5. SIP 与 CC 呼叫状态都为空闲。
6. SIP 原生媒体为空闲，CC PCM / SDK 资源也为空闲。
7. 符合条件后 `rtos.reboot()`，重新加载保存配置。

响应“提交发送接口”不是云端页面已收到的保证。网络不可用或通话未释放时可能继续等待，3 秒不是从点击保存起计算的固定重启倒计时。

| reboot waiting 原因 | 含义 |
| --- | --- |
| response_not_submitted | 配置响应尚未全部提交 |
| response_grace_period | 宽限期未结束 |
| bridge_waiting | 有来电等待 |
| cleanup_pending | 旧通话清理未完成 |
| recovering | 恢复中 |
| cooldown | 冷却未结束 |
| sip_busy / cc_busy | 对应呼叫状态不空闲 |
| sip_media_busy / cc_media_busy | 媒体资源仍占用 |

这些等待原因属于配置重启流程。FOTA 遇忙的行为不同，见下一节，不能假定也会一直排队等待。

---

## 十、FOTA 远程升级

### 10.1 接入位置与配置

`aircloud_app.lua` 在云协议启动前执行：

```lua
require("update").init({idle=idle})
```

`update.lua` 加载标准 `libfota3`，读取入口的 `PRODUCT_KEY`、`PROJECT`、`VERSION`。当前 `main.lua` 已填写项目 Key，本文不复制其值；部署时核对它与设备所属 IoT 项目一致。

| 参数 | 传入值 |
| --- | --- |
| project_key | PRODUCT_KEY |
| script_name | PROJECT，即 Air8783H_Factory |
| script_version | VERSION，即 001.000.001 |
| auto | true |
| interval | 28800 秒，即 8 小时 |
| on_status | 打印 fota 状态、说明和百分比 |
| on_confirm | 下载 / 重启确认时检查桥接空闲 |

Key 不是非空字符串时初始化返回 `fota_not_configured`，不会启动升级流程。但 `libfota3` 在模块顶部就被加载，所以即使暂不配置 Key，也必须添加该库依赖。

### 10.2 自动检测的真实时序

标准库先等待网络并执行时间同步，再根据保存的检测时间安排自动定时器。当前库网络等待最多约 60 秒，SNTP 等待约 30 秒；同步失败时不启动自动检测定时器。

- 首次运行或检测已经到期：可能立即触发检测。
- 距离上次检测尚不足 8 小时：等待剩余时间。
- 检测时间戳保存在 `/fota_timer_state.json`，重启后继续按已保存时间安排。
- 不能理解为每次开机都固定等 8 小时。
- 即使 SIP 使用 UDP，FOTA 也会独立调用 SNTP。

自动检测的 HTTP 查询本身没有由项目 idle 钩子统一拦截；下载和重启阶段再确认空闲。因此不能宣称“通话期间完全没有升级网络活动”。

### 10.3 推荐的手动命令

通过 Tag19 或 Tag1281 下发：

```json
{"id":"ota-001","cmd":"update"}
```

等效别名：

```json
{"id":"ota-002","cmd":"fota"}
```

不需要 params。命令只请求平台检查，不透传自定义 URL、版本或升级包；这些由平台任务决定。

成功回执的部分字段：

```json
{
  "type": "response",
  "id": "ota-001",
  "cmd": "update",
  "ok": true,
  "result": {"stage":"check_requested"}
}
```

忙时的部分回执：

```json
{
  "type": "response",
  "id": "ota-003",
  "cmd": "update",
  "ok": false,
  "error": "device_busy",
  "result": {"stage":"check_requested"}
}
```

**先判断 ok，再看 error。** 失败响应仍可能有 `stage=check_requested`，不能据此判断已受理；成功时也只代表请求检查，不代表有新版本、已开始下载或已升级。

### 10.4 手动触发的检查过程

```text
收到 update / fota
  → update 模块是否已初始化？否：fota_not_configured
  → 当前是否空闲？否：device_busy
  → 已有 1 秒延迟请求？是：返回已受理，不重复安排
  → 设置 1 秒定时器，给云回执入队留时间
  → 1 秒后再次检查空闲
  → 忙：记录 deferred_busy/check，结束本次请求
  → 空闲：调用 libfota3.check_update()
```

这 1 秒不是“回执已送达”的保证。库本身已有流程运行时可能跳过本次执行。标准云 ID 去重同样适用于升级：若同一 ID 之前返回忙，空闲后重发同 ID 会复用旧结果，应换新 ID。

### 10.5 Tag19 旧入口兼容

仅 Tag19 额外接受以下形式：

```text
fota
update
```

裸文本忽略首尾空白及大小写，每次转换为新的内部请求 ID，重复发送不按同一个 ID 去重。也支持没有 cmd 的旧 JSON：

```json
{"type":"update"}
```

```json
{"command":"fota"}
```

```json
{"op":"update"}
```

旧 JSON 操作值使用小写。兼容请求响应走 Tag20，保留有效的 TCP 回复序列号。

| 写法 | Tag19 | Tag1281 |
| --- | --- | --- |
| 带 id 的标准 cmd 请求 | 支持 | 支持 |
| 裸文本 update / fota | 支持 | 不走该兼容入口 |
| 无 cmd 的 type / command / op 写法 | 支持 | 不走该兼容入口 |
| 只有 cmd、没有 id | invalid_command | invalid_command |

为了可追踪和去重，新集成优先使用标准 JSON。

### 10.6 下载确认与重启确认

升级库在准备下载和准备重启时分别调用项目 idle 钩子。检查条件与第九节的桥接空闲检查相同；忙时打印 `fota deferred_busy`，并回调 false。

这表示取消本轮确认，不是“自动等空闲后继续下载 / 重启”。设备空闲后用新 ID 再次发起检查，并查看日志。

当前没有从检查开始到升级结束全程禁止新来电的互斥机制。一次检查空闲后仍可能收到来电；因此升级验收应专门测试忙状态，并在正式单台升级时保持设备空闲。`activity` 钩子虽在封装中预留，当前调用只传 idle，未接入低功耗管理。

### 10.7 平台与设备的升级操作顺序

本目录不包含升级包；以下按现有工程说明中的 `.soc` 平台流程整理，不依赖特定控制台按钮名称：

1. 保存设备当前真正运行的项目名、脚本版本、底层固件信息和 IMEI。
2. 确认 PRODUCT_KEY 对应目标平台项目，脚本版本与设备日志一致。
3. 用匹配设备的底层固件和完整脚本资源制作当前基础 `.soc` 量产包，并保留。
4. 准备目标版本，修改入口 VERSION，打包全部脚本、标准依赖、证书和音频资源；不能只上传一个 Lua 文件当成量产包。
5. 在平台上传匹配的基础包和目标包，设置基础版本、目标版本及单台测试 IMEI，等待升级包生成完成。
6. 确认设备空闲、网络可用，查询当前注册和通话状态。
7. 用新 ID 下发 update，先检查回执 ok / error，再观察设备 fota 日志。
8. 下载和重启确认通过后等待设备重启，核对新版本及升级结果。
9. 升级后重新验证 SIP 注册、双向通话、AirCloud 配置查询和再次挂断拨号。

`Air8783H_Factory` 与旧 `SIP_CC_BRIDGE_PCM` 名称不同，版本格式也有变化；制作基础 / 目标包时以实际设备和当前入口为准，不能直接套用旧 README 的版本号。

### 10.8 升级日志与成功标准

| 状态 | 含义 / 判断 |
| --- | --- |
| not_configured | 项目 Key 未通过封装初始化检查 |
| checking | 正在查询平台 |
| new_version | 检测到升级信息 |
| no_new_version | 本次未发现适用新版本 |
| check_fail / network_fail | 查询或网络失败 |
| download_start / downloading | 下载开始 / 进度 |
| download_done | 下载完成，不等于设备已经运行新版本 |
| download_fail | 下载失败 |
| deferred_busy | 项目空闲检查未通过 |
| rebooting | 准备重启应用升级 |
| boot_report | 开机检查上次升级结果 |
| upgrade_success / upgrade_fail | 重启后的升级结果判断 |

最终以**重启后项目版本、升级结果日志和业务回归**共同验收。云端当前没有完整进度推送，也没有用成功回执代替重启验证的机制。本文不声明已完成真机 FOTA 验收。

---

## 十一、媒体释放、异常恢复与内部事件

### 11.1 为什么信令结束后仍需清理

SIP、CC、VoIP 和 SDK 不是同一个状态机。桥接记录 current、pending、cleanup，分别代表活动呼叫、等待呼叫、清理中的旧呼叫。消息带 Call-ID、generation、owner 和 PCM session，用于识别事件属于哪一通。

`cc_main.is_media_idle()` 还检查：

```text
selected == true
active == 0
media_ready == 0
dl_queued == 0
ul_queued == 0
sdk_active == 0
sdk_pending == 0
sdk_stop_waiting == 0
```

SIP 侧要求没有活动或待启动媒体记录，且原生 VoIP 状态为空闲。桥接清理需两侧终结并释放，再进入 500 ms 冷却。挂断请求返回、状态切到 idle 与真正资源可复用必须区分。

### 11.2 CC 失败与释放超时

| 情况 | 处理 |
| --- | --- |
| cc.dial 正常返回失败 | 记录原因及拨号前后 PCM 快照，按明确失败收尾 |
| cc.dial 抛出异常 | 不能证明未提交拨号，绑定会话并请求挂断，等待终结 |
| 接通后 PCM 未就绪 | 默认 3 秒后记录媒体快照，挂断并发布失败 |
| PCM 媒体错误 | 记录故障与上传快照，进入挂断 |
| 请求挂断后 10 秒未确认 | cc_release_error、CC_RELEASE_TIMEOUT、CC_RELEASE_FAILED |
| 匹配的真实终结事件到达 | 完成该会话收尾；旧 session 不得结束新通话 |

`cc.hangUp` 的 nil 返回不代表失败，也不证明挂断完成。不要为放行下一通而直接伪造空闲状态。

### 11.3 连续无真实下行 PCM

统计使用本通真实接通后当前媒体阶段的 `bridgePcmStats.dl_pushed` 增量。早期媒体和上传静音不能替代真实下行。

默认当前阶段持续至少 2000 ms，结束时仍未见增量，才计入连续异常；达到 3 通发布 `CC_BRIDGE_MEDIA_ANOMALY` / `NO_MODEM_PCM`。有有效增量会清除连续计数；统计未知或不合法时不按无 PCM 计入。

两个统计阈值任一个不大于 0 可关闭该统计。`cc_media_reboot_on_error=false` 时只报告；默认开启时先清理，清理完成或最多 3 秒后重启恢复。

### 11.4 关键消息

| 消息 | 作用 |
| --- | --- |
| IP_READY / IP_LOSE | 网络状态 |
| SIP_INCOMING / SIP_CALL_BOUND | SIP 来电与身份绑定 |
| SIP_PROGRESS_REQ / SIP_PROGRESSING | 请求和确认早期媒体阶段 |
| SIP_DIAL_REQ / SIP_ACCEPT_REQ | 请求拨号 / 应答 |
| SIP_HANGUP_REQ / SIP_FAIL_REQ | 请求挂断 / 失败应答 |
| SIP_CONNECTED / SIP_DISCONNECTED / SIP_FAILED | SIP 业务终态和连接状态 |
| SIP_MEDIA_STATE | 媒体状态变化，唤醒清理检查 |
| CC_DIAL_REQ / CC_ACCEPT_REQ / CC_HANGUP_REQ | 蜂窝操作请求 |
| CC_STATE_CHANGED / CC_CONNECTED | 蜂窝状态及媒体就绪后的连接 |
| CC_DISCONNECTED / CC_FAILED / CC_DIAL_REJECTED | 蜂窝结束、失败或拒绝拨号 |
| CC_RELEASE_FAILED | 释放确认超时 |
| CC_BRIDGE_MEDIA_ERROR / CC_BRIDGE_MEDIA_ANOMALY | 媒体故障 / 连续异常 |

这些是内部 Lua 消息，不是对外串口产测指令。业务调用应保留会话身份匹配，不可随意用旧通话消息控制新通话。

### 11.5 超时与周期汇总

| 场景 | 当前值 |
| --- | --- |
| 桥接启动等待 IP | 10 秒 |
| SIP TLS 等待校时 | 10 秒 |
| 等待旧资源 | 3 秒 |
| 清理后冷却 | 500 ms |
| 清理 / 等待轮询 | 100 ms |
| CC 音频启动 | 默认 3 秒，可配置 |
| CC 释放确认 | 10 秒 |
| 无 PCM 恢复清理 | 最多 3 秒 |
| 云协议循环 | 100 ms |
| 云连接 / 认证尝试 | 约 30 秒 |
| 云失败重试 | 约 10 秒 |
| 云状态上报 | 约 30 秒 |
| 云 TCP keepalive | 空闲 60 秒、间隔 10 秒、次数 3 |
| 配置响应后重启宽限 | 至少 3 秒 |
| 手动升级延迟再确认 | 1 秒 |
| 自动升级检测 | 8 小时，按保存时间延续 |

---

## 十二、故障排查

### 12.1 按链路定位

```text
入口 / 缺库
  → 固件 API 与统计结构
  → 网卡 IP / DNS
  → SIP 注册
  → SIP 信令与媒体
  → CC 拨号 / 接听
  → 双向 PCM / RTP
  → 挂断及资源释放

云服务另外检查：AirCloud 登录 → 指令ID → 响应 → 分片组装 → 配置生效
升级另外检查：Key / 版本 / 平台包 → 检查回执 → 下载确认 → 重启 → 结果
```

### 12.2 常见现象对照

| 现象 | 首先检查 | 下一步 |
| --- | --- | --- |
| 日志项目名 / 版本与预期不符 | 实际烧录 main.lua | 不要沿用旧下载列表或旧文档版本 |
| module not found | 子目录脚本和标准依赖 | 特别检查 update、libfota3、excloud |
| excloud missing or incompatible | 实际下载文件和字节码 | 检查 /luadb 平铺路径 |
| 配置入口失败 | fskv 与固件能力 | 确认初始化返回和保存结构 |
| firmware_missing_* | 固件接口不匹配 | 按第二节精确错误定位 |
| 无 IP | SIM 数据业务 / 热点 / 驱动选择 | 校对 adapter 和 DNS |
| SIP 启动完成但未注册 | 运行时服务器、账号、端口、传输 | 查 register 事件，核对持久化值 |
| SIP 来电但手机不响 | 是否确认 183 和 VoIP started | 然后看 CC 拨号结果 |
| cc.dial 失败 | 号码、SIM 语音业务、CC 状态 | 保留 dial PCM before/after 与 reason |
| 手机来电不转 SIP | 远端 URI、对端注册、自动处理开关 | 查看 SIP_DIAL_REQ 后日志 |
| 手机来电一直未接听 | SIP 对端是否已接听且媒体就绪 | 当前流程先接通 SIP 再接 CC |
| 接通后无声 / 单向 | 协商编码、RTP、PCM、SDK 上传 | 对照 RTP stats、codec timing、CC PCM stats |
| 远端音频提交失败 | 播报调用当前被注释 | 看是否恢复桥接语音，非注册失败 |
| 第二通无法建立 | cleanup、cooldown、媒体队列 | 不能只看 registered 或 cc_idle |
| CC_RELEASE_TIMEOUT | 没有真实释放确认 | 保存 session、generation 和 SDK 状态 |
| 连续通话后重启 | NO_MODEM_PCM | 检查阶段时长和 dl_pushed 增量 |
| 改默认值仍连旧服务 | fskv 保存配置覆盖 | 查询并用新 ID 保存配置 |
| 保存后没立即重启 | 响应提交、宽限期和空闲条件 | 看 reboot waiting 原因 |
| 同 ID 改值不执行 | 命中缓存 | 新操作使用新 ID |
| get_status 部分失败 | 三个分区当前不支持 | 单独检查 sip 分区 |
| 收到 fragment / hex | 大消息分片 | 先组装再解析完整 JSON |
| WiFi SIP 正常但云离线 | 固定 GP 就绪检查和默认网卡 | 分开检查 4G 数据与云连接 |
| FOTA 返回 device_busy | 等待 / 通话 / 清理 / 媒体未空闲 | 空闲后换新 ID 重试 |
| FOTA 返回成功但无下载 | 只受理检查，可能无新版、再次忙或库已运行 | 查 fota / libfota3 日志 |
| FOTA 没有按期自动检测 | 校时及保存时间 | 检查同步失败或剩余间隔 |
| 下载后没有重启 | 重启确认时设备忙 | 查 deferred_busy，空闲后重新检查 |
| 升级后版本未变 | 平台基础包、目标包、设备身份和版本 | 结合 boot_report、upgrade_fail 核对 |

### 12.3 建议附带的诊断信息

保留项目 / 脚本版本、底层固件版本、SIM 业务条件、网络类型、SIP 传输与编码、呼叫方向、从启动到故障的完整日志、云请求 ID 及完整响应。通话失败另附 Call-ID、CC generation / PCM session、媒体统计；升级失败另附平台基础 / 目标版本、各阶段日志及重启后版本。

---

## 十三、真机验收清单

以下用于实际执行和记录，不代表本次 README 修改已完成硬件测试。

| 编号 | 操作 | 验收重点 |
| --- | --- | --- |
| T01 | 冷启动 | 项目名、版本、缺库和固件接口检查通过 |
| T02 | 默认 4G 注册 | IP、SIP register ok、AirCloud 分别通过 |
| T03 | SIP 呼手机 | 183 / 媒体后拨号，接通后双向语音 |
| T04 | 手机呼 SIP | SIP 接听后 CC 接听，双向语音 |
| T05 | 两端分别主动挂断 | 对端结束、资源释放、第二通可建立 |
| T06 | 呼叫中取消 / 拒接 / 忙线 | 不遗留外呼，不干扰后续呼叫 |
| T07 | 无语音业务卡或拨号失败 | 错误详情和释放逻辑可核对 |
| T08 | 快速连续拨号 | 等待、冷却及会话身份正确 |
| T09 | 四种编码分别测试 | 固件支持、双向媒体和收尾正常 |
| T10 | 仅修改目标号码 | 下一通使用新号码，当前通话不改 |
| T11 | 通话中保存 SIP 参数 | 回包后等完整空闲再重启，重新注册 |
| T12 | get_status 和大配置 | 四分区与 hex 分片正确组装 |
| T13 | 重复请求 ID | 重放响应；新 ID 能执行新操作 |
| T14 | WiFi / TLS 按需测试 | 网卡、校时、证书、SIP、云分别核对 |
| T15 | .luac 烧录 | excloud 动态加载和标准库正常 |
| T16 | 空闲时手动 update | 回执、平台检查及日志阶段清楚 |
| T17 | 通话中 update / 确认时来电 | busy / deferred_busy 符合代码，不能误报成功 |
| T18 | 单设备实际升级 | 新版本、结果日志和 SIP / CC 回归通过 |
| T19 | Tag19 旧入口 | 支持格式及 Tag20 序列号正确 |
| T20 | 重启后自动升级周期 | 保存时间延续，校时与定时器行为可核对 |

建议按固件版本、网络、编码和升级目标分别记录结果，不要把一次成功扩大为全部组合都已验证。

---

## 十四、源码维护与同步

当前仓库路径为 `module/Air8783H/project/sip_cc_web/`。只修改业务源码后再打包，发布时同步维护入口 PROJECT / VERSION、平台升级版本和本文。

旧说明记录的外部源码位置：

```text
D:\Air\Documents\SIP_web\8783H\sip_cc_bridge_pcm
```

旧同步命令为在对应外部工作区执行：

```text
python 8783H/sip_cc_bridge_pcm/prepare_download.py
```

本目录没有 `prepare_download.py`。继续使用该外部流程前，应核对脚本真实位置、输入与输出目录，不能直接把相对命令当作本仓库可运行命令。原说明称同步保留 README，实际需检查所用脚本，避免同步后文档又回到短版或旧版本。

当前标准 excloud 不再保存在项目 lib 中，依赖清单是打包的一部分。不要为了“只复制目录即可运行”而混入多个同名库；修改上游库前先确认项目保留版本与兼容层职责。

本工程没有继电器 / Modbus、屏幕 UI、本地网页及产测串口命令，Air8301 参考文档中的对应硬件和接口不能直接套用。本文依据当前目录源码及标准升级库核对，真实语音与 FOTA 结果仍需按验收清单在设备上确认。
