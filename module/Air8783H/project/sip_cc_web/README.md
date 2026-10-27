# Air8783H SIP / 蜂窝语音桥接与云端配置

本项目在 Air8783H 上通过 PCM 桥接 SIP 通话与蜂窝语音通话（CC），并通过 AirCloud TCP 接收 Web 平台下发的配置、状态查询和远程升级指令。

当前入口为 `main.lua`，项目名为 `Air8783H_Factory`，脚本版本为 `001.000.002`。`sip_cc_web` 提供设备端业务与云端协议，本目录不包含 Web 前端页面或本地 HTTP 配置服务。

## 功能与通话流程

- **SIP 呼入转手机**：收到 SIP 来电后，等待旧会话释放，发送 SIP 183；确认早期媒体启动后拨打配置的手机号，手机接通后完成两侧通话桥接。
- **手机呼入转 SIP**：SIM 卡收到来电后，设备呼叫配置的 SIP URI；SIP 侧接通后再接听蜂窝来电。
- **统一收尾**：一侧挂断或失败时协调另一侧释放，检查媒体和底层资源，再进入下一次呼叫。当前只处理一组桥接通话，不支持并发通话。
- **云端管理**：查询状态与配置、保存 SIP 参数和一组手机号/SIP 对端映射、空闲重启应用配置、请求 FOTA 检查。
- **运行保护**：支持 Air153C 外部看门狗、媒体启动超时检测及连续通话缺少下行 PCM 的异常检测。

AirCloud 固定使用 TCP，SIP 信令独立支持 UDP、TCP、TLS。云端配置仅支持 `sip_cc` 模式和一个手机号对应一个 SIP 对端；不支持本机音量设置、按键 SOS 外呼、电池查询、定位或云端 TTS 播报。

## 目录结构

| 路径 | 用途 |
| --- | --- |
| `main.lua` | 定义项目、版本和升级项目 Key，依次加载配置、看门狗、网络、桥接及云端模块 |
| `sip_cc/config.lua` | SIP、目标号码、编解码、媒体检测与看门狗默认配置 |
| `sip_cc/sip_cc_app.lua` | 等待网络；TLS 模式先校时，再按 CC → SIP 顺序初始化 |
| `sip_cc/bridge.lua` | 两侧呼叫协调、清理、冷却与异常恢复 |
| `sip_cc/sip_main.lua`、`sip_cc/pcm_sip.lua` | SIP 会话与 VoIP PCM 媒体管理 |
| `sip_cc/cc_main.lua` | 蜂窝通话及 PCM 生命周期管理 |
| `sip_cc/air153c_wdt.lua` | Air153C 看门狗初始化 |
| `cloud/aircloud_app.lua` | 汇总通话状态，提供配置重启和升级使用的空闲判断 |
| `cloud/aircloud_protocol.lua` | 云端指令、去重、回执、分片、状态上报及重启调度 |
| `cloud/aircloud_settings.lua`、`cloud/sos_config.lua` | 配置校验、持久化、能力声明与号码映射 |
| `cloud/aircloud_tcp_adapter.lua` | 原版 `excloud` 的 TCP 适配，处理半包、粘包及回复流水号 |
| `netdrv/` | 网络接入；当前启用 4G，Wi-Fi 文件未启用 |
| `ota/update.lua` | 基于原版 `libfota3` 的升级接入 |
| `lib/httpplus.lua` | 本项目随附的 HTTP 扩展库 |
| `audio/Time_travel_8k.mp3` | 预留通话提示音资源 |
| `certs/sip-ca.pem` | SIP TLS CA 证书资源 |

## 运行准备与烧录

### 硬件和固件

1. 准备 Air8783H 设备、天线、稳定供电，以及支持数据业务和语音通话的 SIM 卡。仅有数据能力的卡无法完成蜂窝语音桥接。
2. 使用适配 Air8783H、包含本项目 PCM 桥接接口的底层固件；本目录不提供底层固件。固件需支持 `cc`、`voip`、`socket`、`mobile`、`fskv` 等功能，不能只以 SIP 注册成功判断桥接接口齐全。
3. 重点核对 CC 的 `bridgePcmStats`、`bridgeAudioStop`，以及 VoIP 的 `setAudioMode`、`AUDIO_MODE_BRIDGE`、`pcmIn`、`pcmOut` 等接口。
4. 默认启用 Air153C 看门狗，喂狗引脚为 GPIO 23、周期为 180 秒。烧录前按实际硬件核对 `config.WDT_CONFIG`。

### 配置与下载步骤

1. 修改 `sip_cc/config.lua` 中的 SIP 服务器、账号、密码、目标手机号及远端 SIP URI，确认服务器允许相应编解码和传输方式。
2. 核对 `main.lua` 的 `PROJECT`、`VERSION` 和 `PRODUCT_KEY`，使其与实际设备及升级项目一致。不要直接沿用示例账号或其他项目的 Key。
3. 在 Luatools 中添加 `main.lua` 和各功能子目录内的 Lua 文件。电脑端子目录用于分类，设备端按文件原名加载，例如 `/luadb/excloud.luac`；不要让脚本只能通过功能子目录路径访问。
4. 添加资源文件；使用 TLS 时须烧录对应 CA 证书，启用文件提示音时须烧录 MP3。
5. 使用 Luatools 自动添加依赖，并检查下载清单。标准扩展库来自仓库 `script/libs/`，至少核对 `exsipclient.lua`、`exsipproto.lua`、`excloud.lua`、`exmtn.lua`、`libfota3.lua`；启用外部看门狗还需 `exair153x_wdt.lua`。同时确保 `sys`、`sysplus` 及其余自动解析的依赖齐全。
6. `httpplus.lua` 使用本目录 `lib/` 内的文件，避免添加同名库造成覆盖。`excloud.lua` 与 `libfota3.lua` 使用上游原版，不需要修改；TCP 兼容逻辑由项目适配层处理。
7. 烧录后检查开机日志中的 `Air8783H_Factory 001.000.002`、网络就绪日志和 `SIP/CC 桥接应用启动成功`，再检查 SIP 注册与云端鉴权状态。

`README.md` 不需要烧录。本目录没有旧文档所述的 `prepare_download.py` 同步脚本，直接以本目录当前源码组织下载文件。

## 本地配置

主要配置位于 `sip_cc/config.lua`：

| 参数 | 作用 / 当前默认值 |
| --- | --- |
| `sip_server_addr`、`sip_server_port` | SIP 服务器地址与端口；端口默认 `8910` |
| `sip_domain` | SIP 域；空字符串时使用服务器地址 |
| `sip_username`、`sip_password` | SIP 注册账号和密码，按实际部署填写 |
| `sip_transport` | 默认 `udp`，可选 `tcp`、`tls` |
| `remote_sip_uri` | 蜂窝来电时呼叫的 SIP 对端，格式为 `sip:账号@域` |
| `target_phone_number` | SIP 来电时拨打的手机号 |
| `adapter` | 默认 `socket.LWIP_GP`，对应当前 4G 网络 |
| `rtp_port` | 默认 `40000` |
| `codec` / `codecs` | 默认 `PCMA`；支持 PCMA、PCMU、G729、G722，可用 `codecs` 配置协商顺序 |
| `ptime` | 固定 `20` ms；G722 使用 16 kHz PCM，其余支持的编解码使用 8 kHz PCM |
| `auto_answer_sip` | 默认 `true`，启动 SIP 呼入桥接流程 |
| `auto_handle_mobile_incoming` | 默认 `true`，蜂窝来电时自动呼叫 SIP 对端 |
| `cc_audio_start_timeout_ms` | 默认 `3000` ms，媒体启动超时 |
| `cc_media_min_connected_ms` | 默认 `2000` ms，参与缺少下行 PCM 统计的最短接通媒体阶段 |
| `cc_media_missing_call_limit` | 默认 `3`，连续达到指定次数触发媒体异常；小于等于 0 关闭统计 |
| `cc_media_reboot_on_error` | 默认 `true`，媒体异常允许触发恢复重启 |

### 网络与 TLS

`netdrv/netdrv_device.lua` 当前只加载 `netdrv_4g`。4G 网络就绪时会设置公共 DNS；专网卡或境外网络应按实际环境调整 `netdrv_4g.lua` 的 DNS 配置。

若改用 Wi-Fi，需要同时核对网络驱动、SIP 的 `adapter` 和云端逻辑：当前云端连接检查固定使用 `socket.LWIP_GP`，不能只取消 Wi-Fi 模块的注释就认为整套业务已完成切换。

使用 TLS 时，设置 `sip_transport = "tls"`，配置匹配服务器的端口与 `sip_tls.ca_cert`，并烧录证书。启动任务会先进行 SNTP 校时；10 秒内未收到校时成功事件会停止通话业务启动。TLS 信令和媒体加密分别配置；`media_encryption` 应与服务器及固件能力匹配。

### 持久化配置优先级

启动时从 `fskv` 的 `aircloud_pcm_v1` 记录加载配置，已保存的云端配置会覆盖对应源码默认值。因此，设备已有保存记录时，仅修改 `config.lua` 不一定改变实际运行参数；应先通过云端查询当前配置，再按需更新。

## 云端指令

### 请求与回复

JSON 请求包含 `id`、`cmd`，配置指令另带 `params`。`id` 必须为 1～64 字节的非空字符串且不含控制字符；整条指令不能超过 1396 字节。

| 输入 | 回复 |
| --- | --- |
| Tag19 JSON 指令 | Tag20，数据类型 3，JSON 回执 |
| Tag1281 JSON 指令 | Tag1281，数据类型 5，JSON 回执 |
| Tag19 裸文本 `version` | Tag1027，数据类型 3，纯文本 `Air8783H_Factory_001.000.002` |

回复保留有效的请求流水号。`version` 忽略大小写及首尾空白，不额外返回 Tag20，通话中也可查询。

设备缓存最近 32 个请求 ID 的结果；缓存命中时返回原回执，不再次执行。缓存仅在当前运行期有效，新操作和失败后的重试应使用新 ID。

| `cmd` | 用途 |
| --- | --- |
| `get_sip_status` | SIP 注册、桥接状态、配置待生效状态及能力 |
| `get_sip_config` | 已保存配置及待重启状态；不返回 SIP 密码 |
| `get_status` | 分别返回 `sip`、`battery`、`location`、`audio` 四个 section；后三项在本项目返回不支持 |
| `set_config` | 校验并持久化配置，返回 `reboot_pending`、`reboot_reason` |
| `update` / `fota` | 请求远程升级检查 |

`get_location`、`speak_battery`、`play_tts` 返回 `unsupported_feature`，其他未知指令返回 `unknown_command`。

### 示例

查询状态和配置：

```json
{"id":"status-001","cmd":"get_sip_status"}
{"id":"config-001","cmd":"get_sip_config"}
```

修改 SIP 参数（示例值须替换为实际部署参数）：

```json
{
  "id": "config-002",
  "cmd": "set_config",
  "params": {
    "sip": {
      "sip_server_addr": "sip.example.com",
      "sip_server_port": 5060,
      "sip_domain": "sip.example.com",
      "sip_username": "device001",
      "sip_password": "<填写实际密码>",
      "sip_transport": "udp"
    }
  }
}
```

保存一组桥接映射（手机号为格式示例，使用时替换）：

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

`sos_sip_cc_peers` 填 SIP 账号部分，不填完整 URI。设备使用 SIP 域（为空时使用服务器地址）生成远端 URI。修改映射时应同时提交模式、号码列表和对端列表；本项目只接受一组映射。

### 配置生效与自动重启

- 提交任意 SIP 连接字段，即使值未改变，也会请求空闲重启，原因是 `sip_settings_submitted`。
- 修改 SIP 对端等需要重新初始化的配置时，会标记 `configuration_changed`。
- 仅修改手机号，且 SIP 连接参数与对端仍与本次启动配置一致时，号码用于下一通来电；当前通话使用已保存的通话内号码。
- `sip.auto_answer`（布尔值）和 `sip.delay_auto_answer`（0～20 的整数）仅兼容保存，不改变当前 PCM 桥接接听行为，也不能替代本地的两个自动处理开关。
- 重启等待对应配置回执的全部分片提交发送，再等待 3 秒，并确认两侧通话、媒体、清理、恢复和冷却均已空闲。发送提交不代表平台已完成业务确认；设备忙或回执未提交时会继续等待。
- 后续仅修改号码或接听偏好，不会取消已经请求的 SIP 配置重启。

### 状态上报与分片

云端鉴权成功后上报启动快照，之后每 30 秒上报状态，使用 Tag1281。内容包含项目与版本、设备 ID、时间有效性、SIP/CC 状态、配置和能力信息。

JSON 序列化后超过 1100 字节时，按每片 500 字节拆分，再以十六进制编码包装为 `type="fragment"`。平台需按 `report_id` 分组、按 `part` 排序，完成 hex 解码与拼接后再解析原始 JSON；`parts` 表示总片数。`get_status` 的四个 section 还需分别处理。

## 远程升级

`ota/update.lua` 使用原版 `libfota3`，根据 `main.lua` 中的项目 Key、名称和版本发起自动检测，周期为 28800 秒（8 小时）。Key 为空时不启用升级，手动检查返回 `fota_not_configured`。

```json
{"id":"ota-001","cmd":"update"}
```

也可使用 `cmd="fota"`。Tag19 兼容裸文本 `fota` / `update`（忽略大小写及首尾空白），以及 `{"type":"update"}`、`{"command":"fota"}`、`{"op":"update"}` 入口。裸文本每次作为新请求处理；需要去重时使用带 ID 的标准 JSON 指令。

设备忙时手动检查返回 `device_busy`。接受请求后的 `stage="check_requested"` 只表示已请求检查，不表示已下载或升级成功。下载与重启确认还会再次检查空闲状态；这不是整个升级期间阻止新来电的互斥机制。

升级前在对应 IoT 项目准备匹配设备的基础包、目标包及测试设备配置。保持设备空闲，结合 `fota` 日志确认检查、下载、升级结果，再通过重启日志或 `version` 指令确认最终版本，并复测双向通话。失败后重新发起检查应使用新的请求 ID。

## 排查与验证

| 现象 | 核对内容 |
| --- | --- |
| `excloud missing or incompatible` | Luatools 下载清单是否实际包含原版 `excloud.lua`，设备端名称和加载位置是否正确 |
| CC 或 SIP 初始化失败 | 配套固件接口、账号参数、编解码及 PCM 桥接能力；以初始化日志中的原因定位 |
| SIP 已注册但无法拨打手机 | SIM 语音能力、目标号码、CC 拨号错误及释放状态；网络注册不代表语音可用 |
| 云端修改成功但暂未重启 | `reboot_pending`、`reboot_reason` 与 `aircloud` 的 `reboot waiting` 日志；检查回执发送、通话和媒体释放 |
| 修改源码后配置未变化 | 是否存在覆盖默认值的 `aircloud_pcm_v1` 持久化记录 |
| TLS 启动停止 | 校时是否成功、证书及服务器端口是否匹配 |
| 版本查询无回复 | 检查 TCP 鉴权和发送队列；出现 `VERSION_REPLY_QUEUE_FULL` 时稍后重试 |
| 接通后没有提示音 | 当前 `bridge.lua` 中 `voip.playFile` / `voip.playTTS` 调用已注释，资源存在不代表已启用播放 |

当前提示音流程仍会在部分编解码通话接通后短暂静音并调度播报；由于实际播放调用被注释，会记录提交失败并恢复桥接。G729/G722 跳过此提示流程。若需要提示音，应先完善并验证该流程。

建议在真机上依次验证：开机联网与注册、SIP 呼入转手机、手机呼入转 SIP、双向音频、任一侧挂断、拨号失败收尾、连续呼叫、云端查询与分片、号码修改、通话中保存配置后空闲重启，以及 FOTA 后恢复业务。本 README 按当前源码整理，不代表已完成这些真机验收。
