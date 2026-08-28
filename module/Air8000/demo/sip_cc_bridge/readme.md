# SIP/CC 音频桥接 Demo

本项目在 LuatOS 上桥接 SIP RTP 音频与蜂窝语音（CC/VoLTE）音频。SIP 侧由 `exsip` 处理，蜂窝通话侧由 `cc` 处理，底层通过 `voip.AUDIO_MODE_BRIDGE` 交换 PCM 数据。

当前程序支持两个方向：

- SIP 客户端呼叫模组 SIP 账号，模组建立 183 早期媒体后拨打指定手机号码。
- 模组收到手机来电后，呼叫指定的远程 SIP URI；远程 SIP 接听后，模组接听手机来电。
- 任一侧断开或失败时，桥接协调器会请求挂断另一侧。

## 运行环境

- LuatOS 固件需要包含 `exsip`、`voip`、`cc`、`exaudio`、`audio_v2`、`sys` 和 `sysplus`。
- SIM 卡需要开通 VoLTE，并能正常注册蜂窝网络。
- 当前音频配置使用 ES8311、新音频框架、I2C0、PA GPIO162、DAC GPIO164；使用其他硬件时必须修改 `audio_drv.lua`。
- 当前默认使用 4G 网卡 `socket.LWIP_GP`。

> `main.lua` 中的项目说明沿用 Air780EHV Demo，而 `audio_drv.lua` 和可选网卡驱动使用 Air8000 引脚配置。烧录前请以实际开发板原理图核对音频及网卡引脚。

## 目录结构

```text
sip_cc_bridge/
├── main.lua                  程序入口和初始化任务
├── audio_drv.lua             ES8311 音频初始化
├── netdrv_device.lua         网卡选择入口，当前启用 4G
├── readme.md
├── sip_cc/
│   ├── config.lua            SIP、号码、网络及桥接配置
│   ├── sip_main.lua          SIP 初始化、状态机及事件转换
│   ├── cc_main.lua           CC 初始化、状态机及事件转换
│   ├── bridge.lua            SIP/CC 通话协调和挂断同步
│   └── sip_cc_app.lua        备用调度模块，当前 main.lua 未加载
└── netdrv/
    ├── netdrv_4g.lua          4G 网卡事件和 DNS 配置
    ├── netdrv_wifi.lua        Wi-Fi STA 驱动
    ├── netdrv_eth_spi.lua     CH390H SPI 以太网驱动
    └── netdrv_multiple.lua    多网卡优先级配置
```

LuatOS 烧录时需要保持上述目录结构，确保 `require "config"`、`require "bridge"` 等模块能够被找到。

## 启动流程

`main.lua` 的实际启动顺序如下：

1. 加载 `sys`、`sysplus` 和 `netdrv_device`。
2. 加载 `sip_main` 和 `cc_main`；`sip_main` 会自动加载 `bridge`。
3. 最多等待 10 秒的 `IP_READY` 消息。
4. 初始化 ES8311 音频。
5. 初始化并启动 SIP。
6. 初始化 CC。
7. 每 10 秒输出 SIP 状态、CC 状态、SIP 注册状态和 CC 就绪状态。

`sip_cc/sip_cc_app.lua` 是另一套调度实现，但当前入口没有 `require "sip_cc_app"`，因此不会执行。

## 烧录前配置

业务配置位于 `sip_cc/config.lua`。当前代码中的值如下：

| 参数 | 当前值 | 说明 |
| --- | --- | --- |
| `sip_server_addr` | `180.152.6.34` | SIP 服务器地址 |
| `sip_server_port` | `8910` | SIP 服务器端口 |
| `sip_domain` | `180.152.6.34` | SIP 域 |
| `sip_transport` | `udp` | SIP 传输方式 |
| `sip_username` | `12345670` | 模组 SIP 用户名 |
| `sip_password` | `Air.234567` | 模组 SIP 密码 |
| `remote_sip_uri` | `sip:12345671@180.152.6.34` | 手机来电时呼叫的 SIP URI |
| `target_phone_number` | `15057721363` | SIP 来电后拨打的手机号码 |
| `rtp_port` | `40000` | 本地 RTP 端口 |
| `codec` | `PCMU` | RTP 编解码格式 |
| `ptime` | `20` | RTP 打包时长，单位 ms |
| `adapter` | `socket.LWIP_GP` | SIP 使用的网络适配器 |
| `auto_answer_sip` | `true` | SIP 来电后自动启动 183 早期媒体 |
| `auto_handle_mobile_incoming` | `true` | 手机来电后自动呼叫远程 SIP URI |
| `local_audio_default` | `false` | 两侧接通后将本地扬声器和麦克风静音 |

请勿将真实生产账号和密码提交到公共仓库。

### 切换网卡

默认在 `netdrv_device.lua` 中加载：

```lua
require "netdrv_4g"
```

切换网络时，需要同时完成两项修改：

1. 在 `netdrv_device.lua` 中只启用需要的网卡驱动。
2. 将 `sip_cc/config.lua` 的 `adapter` 改为对应值：4G 使用 `socket.LWIP_GP`，Wi-Fi 使用 `socket.LWIP_STA`，以太网使用 `socket.LWIP_ETH`。

4G 驱动会设置 `223.5.5.5` 和 `114.114.114.114` 为 DNS。专网卡或海外网络不应直接使用这两个配置。

## 桥接关键配置

`sip_main.lua` 调用 `exsip.init` 时固定使用：

```lua
cc_sip_bridge = true
auto_answer = false
early_media = true
early_media_response = 183
```

随后通过 `voip.setAudioMode(voip.AUDIO_MODE_BRIDGE)` 切换到桥接模式。设置失败时，代码会停止 VoIP、等待 500 ms 后再重试一次。

不要删除 `cc_sip_bridge = true`，也不要在 SIP INVITE 到达后立即返回 200 OK；当前流程需要先建立早期媒体并拨打手机。

## 通话流程

### SIP 呼入 → 手机呼出

1. SIP 客户端呼叫 `sip_username`。
2. `sip_main` 发布 `SIP_INCOMING`。
3. `bridge` 发布 `SIP_PROGRESS_REQ`，`sip_main` 调用 `exsip.progress()` 返回 183。
4. `sip_main` 发布 `SIP_PROGRESSING`，`bridge` 发布 `CC_DIAL_REQ`。
5. `cc_main` 调用 `cc.dial(0, target_phone_number)`。
6. CC 收到 `CONNECTED` 或 `AUDIO_START` 后发布 `CC_CONNECTED`。
7. `bridge` 发布 `SIP_ACCEPT_REQ`，`sip_main` 调用 `exsip.accept()` 返回 200 OK。
8. SIP 和 CC 均连接后开始桥接，并根据 `local_audio_default` 设置本地音量。

### 手机呼入 → SIP 呼出

1. CC 收到 `INCOMINGCALL` 后发布 `CC_INCOMING`。
2. `bridge` 发布 `SIP_DIAL_REQ`，呼叫 `remote_sip_uri`。
3. 远程 SIP 接听后，`sip_main` 发布 `SIP_CONNECTED`。
4. `bridge` 发布 `CC_ACCEPT_REQ`，`cc_main` 调用 `cc.accept(0)`。
5. CC 连接后开始双向音频桥接。

如果 `auto_answer_sip` 或 `auto_handle_mobile_incoming` 为 `false`，当前代码不会提供其他自动补偿流程，需要业务层主动发布对应请求消息。

## 内部消息

| 类型 | 消息 |
| --- | --- |
| SIP 事件 | `SIP_INCOMING(from, uri, to)`、`SIP_PROGRESSING`、`SIP_CONNECTED`、`SIP_DISCONNECTED(reason)`、`SIP_FAILED(reason)` |
| CC 事件 | `CC_INCOMING(number)`、`CC_CONNECTED`、`CC_DISCONNECTED`、`CC_FAILED(reason)` |
| SIP 请求 | `SIP_DIAL_REQ(uri)`、`SIP_PROGRESS_REQ`、`SIP_ACCEPT_REQ`、`SIP_HANGUP_REQ` |
| CC 请求 | `CC_DIAL_REQ(number)`、`CC_ACCEPT_REQ`、`CC_HANGUP_REQ` |

## 烧录与验证

1. 按实际环境修改 `sip_cc/config.lua`。
2. 核对 `audio_drv.lua` 中的 ES8311、I2C、PA 和 DAC 引脚。
3. 核对 `netdrv_device.lua` 与 `config.adapter` 使用同一种网卡。
4. 将根目录 Lua 文件以及 `sip_cc`、`netdrv` 子目录一起烧录。
5. 上电后检查网络、音频、SIP 和 CC 初始化日志。

正常启动至少应看到以下类型的日志：

```text
网络等待结束
exaudio.setup初始化成功
SIP 初始化开始
voip 已设置为桥接模式
SIP 启动完成
CC 初始化完成
```

SIP 呼入并转拨手机时，关键日志顺序为：

```text
启动 SIP 183 早期媒体
早期媒体已建立，拨打手机
CC 已连接
CC 已接通，现在接听 SIP
SIP 已连接
```

## 故障排查

- **SIP 不注册**：检查 SIP 地址、端口、域、账号、密码和 `config.adapter`，同时确认网络已获得 IP。
- **SIP 来电后未拨打手机**：检查 `exsip.progress()` 是否成功，以及是否出现 `SIP_PROGRESSING` 和 `CC_DIAL_REQ`。
- **手机来电后未呼叫 SIP**：确认 `auto_handle_mobile_incoming = true`，并检查 `remote_sip_uri`。
- **CC 已接通但 SIP 未连接**：检查 `CC_CONNECTED`、`SIP_ACCEPT_REQ` 和 `exsip.accept()` 的返回值。
- **通话无声**：确认固件支持 `cc_sip_bridge` 和 `AUDIO_MODE_BRIDGE`，并核对 ES8311、I2S、PA/DAC 引脚。
- **本地听不到声音**：`local_audio_default = false` 会在两侧接通后将扬声器和麦克风音量设为 0；桥接 PCM 本身仍保持工作。
- **切换网卡后无法注册**：确认网卡驱动、`config.adapter` 和硬件引脚三者一致。
- **网络等待超时**：程序仍会继续初始化 SIP；需通过后续日志确认网络是否真正可用。

## 注意事项

- `main.lua` 当前先初始化 SIP、再初始化 CC。
- `bridge.lua` 通过消息通信，不直接引用 `sip_main` 或 `cc_main`，以避免循环依赖。
- `sys.run()` 之后不要添加业务代码。

