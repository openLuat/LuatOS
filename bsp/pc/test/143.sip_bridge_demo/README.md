# SIP-VoLTE 音频桥接测试 Demo

本 Demo 用于验证 Air8000/4G 模组作为 SIP 和 VoLTE/CC 之间的音频网关。当前重点覆盖两条链路：

- SIP 客户端拨入 4G 模组 SIP 账号，模组再拨手机号码，并在手机未接听前把 CC/VoLTE 侧彩铃、忙音、无人接听提示、运营商失败播报通过 RTP 送回 SIP 客户端。
- 手机拨打 4G 模组号码，模组再拨 SIP 客户端；SIP 客户端接听后，模组再接听手机来电并建立双向桥接。

## 当前配置

配置位于 `scripts/sip_bridge_agent.lua` 的 `CONFIG`。

| 参数 | 当前值 | 说明 |
| --- | --- | --- |
| `sip_server_addr` | `180.152.6.34` | SIP 服务器地址 |
| `sip_server_port` | `8910` | SIP 服务器端口 |
| `sip_username` | `1903CFC1` | 4G 模组 SIP 账号 |
| `remote_sip_uri` | `sip:195544F0@180.152.6.34` | 手机来电转拨的 SIP 客户端 |
| `target_phone_number` | `15057721363` | SIP 呼入时模组拨打的手机号 |
| `codec` | `PCMU` | 当前主测 G.711 PCMU/8k |
| `auto_answer_sip` | `true` | SIP 来电自动进入早期媒体并拨手机 |
| `auto_handle_mobile_incoming` | `true` | 手机来电自动转拨 SIP 客户端 |
| `auto_answer_mobile_incoming` | `true` | 不转 SIP 时可自动接听手机来电；转 SIP 时等 SIP 接听后再接手机 |
| `outgoing_early_timeout` | `90` 秒 | SIP->CC 早期拨号最大等待时间 |
| `outgoing_failure_prompt_grace` | `6` 秒 | CC 未接通失败时，保留运营商失败播报的 RTP 窗口 |

## 文件说明

```text
bsp/pc/test/143.sip_bridge_demo/
├── README.md
└── scripts/
    ├── main.lua                # Demo 入口和 UDP 控制命令
    ├── sip_bridge_agent.lua    # 核心 SIP/CC 状态机
    ├── audio_drv.lua           # 真机音频初始化
    ├── cc_stub_pc.lua          # PC 模拟器 CC stub
    └── test_controller.py      # PC UDP 控制脚本
```

## 最终实现需求

### 1. SIP 客户端 -> 4G 模组 -> 手机

目标：SIP 客户端拨入模组后，在手机侧未接听前也能听到真实 CC/VoLTE 下行媒体，包括彩铃、忙音、无人接听提示和“对方正在通话中，请稍后再拨”等运营商语音播报；手机接听后继续无缝进入双向通话。

最终流程：

```text
SIP 客户端         4G 模组/SIP              4G 模组/CC              手机/运营商
    | INVITE           |                        |                        |
    |----------------->|                        |                        |
    | 100 Trying       |                        |                        |
    |<-----------------|                        |                        |
    | 183 + SDP        |                        |                        |
    |<-----------------|                        |                        |
    | RTP ready        | cc.dial(number)        |                        |
    |<================>|----------------------->| 拨号/彩铃/提示音         |
    | 听到 CC 下行媒体  |<=======================|                        |
    |                  |                        | CONNECTED/AUDIO_START  |
    | 200 OK + SDP     |                        |<-----------------------|
    |<-----------------|                        |                        |
    | ACK              |                        |                        |
    |----------------->|                        |                        |
    | 双向 RTP/PCM 桥接 |<======================>| 双向 CC 语音             |
```

关键点：

- `exsip.progress()` 发送 `183 Session Progress + SDP`，不是等手机接通后才回 `200 OK`。
- `voip` 在 early media 阶段已经启动，CC 下行 PCM 通过 `voip_bridge_pcm_in()` 送给 SIP/RTP。
- 手机接通后才 `exsip.accept()` 发送最终 `200 OK`。
- CC 失败/忙线时，不马上关闭 SIP early dialog，而是保留 `outgoing_failure_prompt_grace` 秒让运营商语音播报完整传给 SIP 客户端。

### 2. 手机 -> 4G 模组 -> SIP 客户端

目标：手机拨打模组手机号时，模组先拨 SIP 客户端；只有 SIP 客户端接听后，模组才接听手机侧来电，避免 SIP 不在线时误接手机电话。

最终流程：

```text
手机/运营商         4G 模组/CC              4G 模组/SIP             SIP 客户端
    | 来电             |                        |                       |
    |----------------->| INCOMINGCALL           |                       |
    |                  | 保持 cc_ringing        | INVITE                |
    |                  |----------------------->|---------------------->|
    |                  |                        | 180 Ringing           |
    |                  |                        |<----------------------|
    |                  |                        | 200 OK                |
    |                  |                        |<----------------------|
    |                  | cc.accept(0)           | ACK                   |
    |                  |<-----------------------|---------------------->|
    | 接通             | ANSWER_CALL_DONE       |                       |
    |<---------------->|<======================>| 双向 RTP/PCM          |
```

关键点：

- `auto_handle_mobile_incoming = true` 时，手机来电自动转拨 `remote_sip_uri`。
- 转 SIP 模式下不会立即 `cc.accept(0)`，而是在 SIP `connected/established` 后才接听手机。
- 某些模组会在同一通未接来电振铃期间重复上报 `INCOMINGCALL`。状态机已经把 `g_call_direction == "incoming"` 且 `CC=cc_ringing` 时的重复 `INCOMINGCALL` 当作重复指示忽略，不再误调用 `cc.hangUp()`。

## 音频桥接架构

底层使用 VoIP bridge 模式：

- `voip.setAudioMode(voip.AUDIO_MODE_BRIDGE)` 必须在 `exsip.start()` 前调用。
- `voip` 只处理 RTP、编解码和 bridge PCM FIFO，不直接控制 I2S。
- `cc` 独占手机侧音频通道，并在 C 层完成 PCM 双向交换。
- CC 下行/早期媒体：`play_save_fifo -> voip_bridge_pcm_in() -> RTP -> SIP 客户端`。
- SIP 上行：`RTP -> voip_bridge_pcm_out() -> _cc_codec_encode() -> 手机侧`。
- bridge 模式下禁用 AEC/降噪，日志应看到 `Bridge mode: AEC disabled`。

## UDP 控制命令

PC 模拟器运行时可通过 UDP 命令控制：

```powershell
cd E:\Air_LuatOS\LuatOS\bsp\pc\test\143.sip_bridge_demo\scripts

python test_controller.py status
python test_controller.py dial
python test_controller.py dial 13800138000
python test_controller.py dial_sip
python test_controller.py incoming 13900139000
python test_controller.py answer
python test_controller.py answer_mobile
python test_controller.py hangup
python test_controller.py audio on
python test_controller.py audio off
python test_controller.py auto on
python test_controller.py auto off
python test_controller.py mobile_auto on
python test_controller.py mobile_auto off
```

说明：

- `auto on/off` 控制手机来电是否自动转拨 SIP。
- `mobile_auto on/off` 控制在不转 SIP 时是否自动接听手机来电。
- `status` 会显示 SIP/CC 状态、本地音频开关、手机来电自动桥接和自动接听状态。

## 真机测试要点

1. 上电后等待：

```text
SIP 注册成功
SIP 服务已就绪
CC 系统就绪
voip 已设置为桥接模式（AUDIO_MODE_BRIDGE）
```

2. SIP->CC 呼出早期媒体：

```text
SIP事件: call incoming
自动启动 SIP 早期媒体
send early media 183
早期媒体已建立，开始拨打手机
VoIP 状态: started
CC bridge downlink PCM bytes=640
```

3. 手机接通后：

```text
CC事件: CONNECTED 或 AUDIO_START
手机侧音频已启动，发送 SIP 200 OK
Bridge mode: AEC disabled
```

4. 手机忙线/拒接/未接提示：

```text
CC 通话已断开 或 CC 拨号失败
延迟结束 SIP 早期媒体，保留 CC 失败播报: 6 秒
```

5. 手机来电转 SIP：

```text
CC事件: INCOMINGCALL
呼入场景：自动拨打 SIP 到 ...
SIP 响铃中
SIP 通话已建立
SIP 已建立，接听手机来电
CC事件: ANSWER_CALL_DONE
```

## 两天调试问题记录

### 1. SIP 客户端听不到手机未接听前的彩铃/提示音

现象：SIP 客户端拨入模组后，手机未接听前 SIP 侧没有彩铃，也听不到忙音、无人接听提示等运营商媒体。

原因：原流程是 SIP 最终 `200 OK` 后才启动 VoIP/CC 桥接，SIP early dialog 阶段没有 RTP 媒体。

处理：

- SIP INVITE 后先返回 `100 Trying`。
- 由桥接层调用 `exsip.progress()` 发送 `183 Session Progress + SDP`。
- `media ready` 来源为 `incoming_early_media` 时也启动 `voip.start()`。
- 先启动 RTP/bridge，再 `cc.dial()`。
- 手机接通后再 `exsip.accept()` 发送最终 `200 OK`。

### 2. 手机未接听时仍听不到真实 CC 下行

现象：早期媒体 RTP 建立后，SIP 客户端仍听不到手机侧彩铃或运营商提示音。

原因：CC 下行 PCM 没有持续送入 VoIP bridge，或只有占位 tone，没有真实 CC 下行。

处理：

- `components/cc/luat_lib_cc_v2.c` 中增加 bridge downlink drain，把 `play_save_fifo` 中的 CC 下行 PCM 周期性送入 `voip_bridge_pcm_in()`。
- 真实 CC 下行出现时停止占位 tone，避免 tone 和真实媒体混音。
- `PLAY 0` 不再被简单当作“真实 early media 结束”，避免无人接听/忙线播报前突然静音。

### 3. 彩铃从“嘟~嘟~”变成持续“嘟~~~~”

现象：第一次通话时 SIP 侧听到的彩铃不是正常间断彩铃，而是持续音；后续又出现卡顿。

原因：Lua/C 两层占位 tone 和真实 CC 下行时机混在一起，且下行 drain 早期节奏不稳定。

处理：

- 保留占位 tone 只作为“真实 CC 下行还没来之前”的兜底。
- 一旦真实 CC 下行 PCM 到达，立即停止 bridge tone。
- downlink drain 每 20ms 读取固定帧，避免一次读取过大导致卡顿或任务压力。

### 4. 手机拒接/挂断后模块没有及时关闭 SIP

现象：手机未接听主动挂断后，SIP 端还保持连接或前几次 SIP 通道未关闭，后续拨入失败。

原因：CC 某些失败路径没有稳定上报最终断开，Lua 状态机也没有在 `HANGUP_CALL_DONE` 后完整恢复 `cc_idle`。

处理：

- 增加 `outgoing_early_timeout`，早期拨号长时间无结果时主动释放 SIP early dialog 和 CC。
- `HANGUP_CALL_DONE` 后明确设置 `g_cc_state = cc_idle`，清理 `g_call_start_time/g_call_direction`。
- VoIP 若在 SIP 已 idle/disconnecting 时仍启动，立即 `voip.stop()`。

### 5. SIP 上行语音到手机侧时有丢失、忽大忽小、越通话越差

现象：手机接听后，SIP 客户端 mic 传到手机侧的声音时有时无，通话越久越差。

原因：SIP RTP 到 CC uplink 的 bridge RX FIFO 缓冲策略不稳定，出现欠采样、积压、PLC 过多或读写节奏漂移。

处理：

- `luat_cc_bridge_get_uplink_pcm()` 增加目标水位、预缓冲、高水位丢弃和 PLC。
- 16k CC / 8k SIP 时做简单上采样。
- RX buffer 满时丢旧数据而不是拒绝新数据，避免延迟无限累积。
- 关键日志：`CC bridge uplink PCM got=... avail=... drop=... plc=... prebuf=...`。

### 6. 通话过程中死机

现象：通话中出现死机。

原因：downlink drain 一次处理过大缓冲，timer callback 栈压力和处理时间过长；部分临时 PCM 缓冲在栈上分配过大。

处理：

- 大 PCM 缓冲改为静态缓冲。
- downlink drain 每次最多处理小帧，避免 timer 回调中长时间阻塞。
- 正常日志中 `CC bridge downlink PCM bytes` 应为 `640` 或 `320`，不应长期出现超大帧。

### 7. 手机拨模块号码总提示正忙

现象：手机拨打 4G 模块手机号时，主叫听到正忙，但把 SIM 卡放手机里能正常通话。

原因：模组实际已经收到 `INCOMINGCALL`。脚本自动把手机来电转拨 SIP 客户端，但 SIP 被叫返回 `480 Temporarily Unavailable`，脚本随后挂断 CC，主叫侧表现为正忙。

处理：

- 增加并明确 `auto_handle_mobile_incoming` 和 `auto_answer_mobile_incoming` 两个开关。
- 若启用手机来电转 SIP，则按“先拨 SIP，SIP 接听后再接手机”的流程。
- 若不启用转 SIP，可由 `mobile_auto` 控制是否自动接听手机来电。

### 8. SIP 客户端未接听前 CC 被挂断

现象：手机来电转 SIP 时，SIP 客户端还没接听，CC 侧被脚本挂断。

原因：同一通手机来电振铃期间，模组重复上报 `INCOMINGCALL`。旧逻辑看到 `CC=cc_ringing` 就判定 CC 忙，并调用 `cc.hangUp()`，误挂断原呼叫。

处理：

- 当 `g_call_direction == "incoming"` 且 `g_cc_state == cc_ringing` 时，再收到 `INCOMINGCALL` 视为重复指示并忽略。
- 日志应看到：`忽略重复手机来电指示，继续等待 SIP 客户端接听`。

### 9. “对方正在通话中，请稍后再拨”语音播报变音/异常

现象：SIP->CC 呼出场景中，彩铃正常，但对方忙线后的运营商语音播报听起来失真、变音或尾段异常。

排查：

- 曾怀疑 16k -> 8k 下采样混叠，但前期同一路底层在未改呼入流程前播报正常。
- 结合日志发现 SIP 侧可能在失败播报期间 `CANCEL` 或 Lua 侧在 CC 失败事件后立即 `fail_sip_early()`，导致 RTP/CC 媒体过早清理。

处理：

- 不保留 CSDK 降采样实验改动，避免引入额外变量。
- Lua 层新增 `outgoing_failure_prompt_grace = 6`。
- SIP->CC early 阶段收到 `DISCONNECTED` 或 `MAKE_CALL_FAILED` 时，延迟结束 SIP early dialog，保留 CC 失败语音播报窗口。
- 正常日志应看到：`延迟结束 SIP 早期媒体，保留 CC 失败播报: 6 秒`。

## 构建验证

PC 非 GUI 增量构建：

```powershell
cd E:\Air_LuatOS\LuatOS\bsp\pc
cmd /c build_windows_32bit_msvc.bat
```

不要直接执行 `xmake -y`。只有脚本输出 `Build completed successfully` 时，才认为 PC 构建验证通过。

## 当前验收结论

截至本次整理：

- SIP->CC 呼出早期媒体已可听到真实彩铃。
- 手机忙线/拒接后的运营商语音播报可通过 RTP 播放到 SIP 客户端，且通过 Lua 层延迟清理后声音恢复正常。
- 手机接通后的双向语音桥接已可用。
- 手机来电转 SIP 已按“先拨 SIP，SIP 接听后再接手机”实现，并修复重复 `INCOMINGCALL` 误挂断问题。
