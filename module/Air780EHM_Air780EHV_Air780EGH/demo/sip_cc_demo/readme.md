# Air780EHV SIP-CC 音频桥接 Demo

本项目将 SIP 通话与 Air780EHV 的 VoLTE/CC 通话进行双向音频桥接。SIP 协议由 `exsip` 处理，手机通话由 `cc` 处理，底层使用 `voip.AUDIO_MODE_BRIDGE` 交换 PCM 数据。

## 功能

- SIP 客户端拨打模组 SIP 账号后，模组自动拨打配置的手机号码。
- 模组收到手机来电后，自动呼叫配置的远程 SIP 客户端。
- SIP 与 CC 均接通后建立双向音频桥接。
- 任意一侧挂断或失败时，同步释放另一侧通话。

## 文件结构

```text
sip_cc_demo/
├── main.lua                 程序入口
├── config.lua               SIP、号码、网络和行为配置
├── audio_drv.lua            Air780EHV/ES8311 音频初始化
├── sip_main.lua             exsip 初始化及 SIP 状态机
├── cc_main.lua              cc 初始化及 VoLTE 状态机
├── bridge.lua               SIP/CC 桥接协调器
├── netdrv_device.lua         网卡选择入口，当前默认 4G
└── netdrv/
    ├── netdrv_4g.lua          4G 网卡
    ├── netdrv_eth_spi.lua     SPI 以太网
    └── netdrv_multiple.lua    多网卡优先级
```

`sip_main.lua` 会自动加载 `bridge.lua`。模块间通过 `sys.publish` / `sys.subscribe` 通信。

## 烧录前配置

在 `config.lua` 中按实际环境修改：

| 参数 | 当前值 | 说明 |
| --- | --- | --- |
| `sip_server_addr` | `180.152.6.34` | SIP 服务器地址 |
| `sip_server_port` | `8910` | SIP 服务器端口 |
| `sip_domain` | `180.152.6.34` | SIP 域 |
| `sip_transport` | `udp` | SIP 传输方式 |
| `sip_username` | `11234561` | 模组 SIP 用户名 |
| `sip_password` | `Air.123456` | SIP 密码 |
| `remote_sip_uri` | `sip:11234560@180.152.6.34` | 手机来电时呼叫的 SIP URI |
| `target_phone_number` | `15057721363` | SIP 来电时拨打的手机号码 |
| `rtp_port` | `40000` | 本地 RTP 端口 |
| `codec` | `PCMU` | RTP 编解码 |
| `ptime` | `20` | RTP 打包时长，单位 ms |
| `adapter` | `socket.LWIP_GP` | 默认 4G 网卡 |
| `auto_answer_sip` | `true` | 自动处理 SIP 来电 |
| `auto_handle_mobile_incoming` | `true` | 手机来电时自动呼叫 SIP |
| `local_audio_default` | `false` | 仅桥接，本地麦克风/扬声器静音 |

切换网卡时，必须同步修改 `netdrv_device.lua` 和 `config.adapter`。

## 通话流程

### SIP 呼入、手机呼出

1. SIP 客户端拨打模组的 `sip_username`。
2. `sip_main` 收到 INVITE，发布 `SIP_INCOMING`。
3. `bridge` 请求 SIP 183 Session Progress，建立早期媒体。
4. 183 成功后，`bridge` 请求 CC 拨打 `target_phone_number`。
5. CC 接通或音频通道启动后，`bridge` 才请求 SIP 返回 200 OK。
6. SIP 和 CC 都进入 connected 状态后，双向音频桥接建立。

当前 `exsip.init` 的关键桥接配置为：

```lua
cc_sip_bridge = true
auto_answer = false
early_media = true
early_media_response = 183
```

`cc_sip_bridge` 使 SIP 仅运行 RTP/PCM 桥接，避免 SIP 和 CC 同时争用 I2S/音频设备。不要改为“先接听 SIP，再拨打 CC”。

### 手机呼入、SIP 呼出

1. Air780EHV 收到手机来电，`cc_main` 发布 `CC_INCOMING`。
2. `bridge` 请求 SIP 拨打 `remote_sip_uri`。
3. 远程 SIP 客户端接听后，`sip_main` 发布 `SIP_CONNECTED`。
4. `bridge` 请求 CC 接听手机来电。
5. CC 建立后启动双向音频桥接。

## 内部消息

SIP 事件：`SIP_INCOMING(from, uri, to)`、`SIP_PROGRESSING`、`SIP_CONNECTED`、`SIP_DISCONNECTED(reason)`、`SIP_FAILED(reason)`。

CC 事件：`CC_INCOMING(number)`、`CC_CONNECTED`、`CC_DISCONNECTED(reason)`、`CC_FAILED(reason)`。

请求消息：`SIP_DIAL_REQ(uri)`、`SIP_PROGRESS_REQ`、`SIP_ACCEPT_REQ`、`SIP_HANGUP_REQ`、`CC_DIAL_REQ(number)`、`CC_ACCEPT_REQ`、`CC_HANGUP_REQ`。

## 烧录与验证

1. 确认固件包含 `exsip`、`voip`、`cc`、`exaudio` 和 `audio_v2` 支持。
2. 确认 SIM 卡已开通 VoLTE，并能正常注册 4G 网络。
3. 修改 `config.lua` 中的 SIP 账号、密码、SIP URI 和手机号码。
4. 将本目录下的 Lua 文件及 `netdrv` 子目录一起烧录。
5. 上电后确认日志中出现网络就绪、音频初始化成功、VoIP 桥接模式设置成功、SIP 注册成功和 CC 初始化完成。

SIP 呼入测试时，关键日志顺序应为：

```text
启动 SIP 183 早期媒体
早期媒体已建立，拨打手机
CC 已连接
CC 已接通，现在接听 SIP
SIP 已连接
```

## 故障排查

- **启动后无后续日志**：保留从开机到异常前的完整串口日志，检查最后一条 `main`、`audio_drv`、`sip_main` 或 `cc_main` 日志。
- **SIP 不注册**：检查账号、密码、服务器、端口和默认网卡。
- **SIP 接通但未拨打手机**：检查 `SIP_PROGRESSING` 及 `CC_DIAL_REQ` 相关日志。
- **CC 接通但 SIP 未 connected**：检查 `exsip.accept()` 返回值及 SIP 200 OK 交互。
- **通话无声音**：确认固件支持 `AUDIO_MODE_BRIDGE` 和 CC PCM 桥接，并检查 ES8311/I2S 配置。
- **切换网卡后失败**：确认网卡驱动与 `config.adapter` 一致。

## 注意事项

- 不要删除 `cc_sip_bridge = true`，也不要在收到 INVITE 后立即返回 SIP 200 OK。
- `local_audio_default = false` 只关闭本地扬声器和麦克风，不会关闭 SIP↔CC PCM 桥接。
- `main.lua` 网络等待最长为 10 秒；超时后仍会尝试初始化 SIP，需通过日志确认网络是否实际就绪。
- `sys.run()` 之后不要添加业务代码。
