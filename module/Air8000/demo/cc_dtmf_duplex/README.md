# Air8000 普通通话与 DTMF 双向收发

单只 Air8000 与一部手机通话，使用开发板板载 ES8311 连接麦克风和扬声器。在正常双向说话期间，模组可以主动发送网络 DTMF，也能接收手机通话键盘产生的网络 DTMF 按键和结束时长。

## 硬件与下载

- 当前音频配置为 Air8000 开发板：`I2C0`、`PA=GPIO162`、`DAC=GPIO164`。其他板型需要按实际硬件调整 `audio_drv.lua`。
- 下载本目录的 `main.lua`、`audio_drv.lua`，同时下载匹配版本的 `script/libs/exaudio.lua` 和 `script/libs/es8311.lua`；Luatools 中只选一套入口脚本。
- 固件必须同时包含 `cc.sendDtmf` 和新增加的普通通话 `cc.dtmfRx` 接口。此前 `air8000_dtmf_tx_20261016` 的发送测试固件不能仅换脚本完成本次接收功能。
- 自行编译时，在配套 EC7xx 语音固件中开启 `LUAT_USE_CC_DTMF_RX`；本模式无需开启 `LUAT_USE_CC_UART_BRIDGE`。需要同时更新两仓库的共享解析器、普通 CC 绑定、平台接收适配和 socket 链接配置。
- 本 demo 使用普通 `cc.init(0)`，不调用 `ccuart`，不使用另一只 4G 模组，不挂载 SD 卡，不保存录音。

ES8311 与 VB7014F / Air1103 是两种不同的本地音频前端。本目录当前提供 ES8311 配置，不能只把 `model` 改成 `air1103` 就假定普通通话的上下行音频会自动接通；VB7014F 的通话音频接入需配套独立适配。

## 快速选择运行方式

在 `main.lua` 顶部选择配置：

| 目的 | 配置 |
| --- | --- |
| 等待手机呼入并自动接听 | `dial_string = ""` |
| 只拨打 10086，听通话声音 | `dial_string = "10086"` |
| 拨通 10086 后暂停 2 秒，再发送 `2` | `dial_string = "10086,2"` |
| 手机呼入后暂停 2 秒，再向手机发送 `2` | `incoming_postdial = ",2"` |
| 手机呼入后只通话、接收按键，不自动发键 | `incoming_postdial = ""` |

表中的 2 秒对应 `pause_ms = 2000`。`incoming_postdial` 只用于呼入，外呼使用 `dial_string` 逗号后的序列。时间单位、发送范围和各状态含义已写在脚本对应位置。日志中的 `COMPLETE` 只表示自动发键序列执行完，通话和接收仍继续。

## 手机呼入模组

将 `main.lua` 中的 `dial_string` 设置为 `""`。

1. 手机拨打模组 SIM 卡号码，模组自动接听。
2. 确认真正开始通话后，两端可正常双向说话。
3. 模组等待 2 秒，通过 `cc.sendDtmf(0, "2", 300)` 向手机发送一次按键 `2`。`CC_DTMF_TX` 日志表示 SDK 确认，不单独证明手机应用已处理按键。
4. 在手机通话键盘依次按 `1`、`2`、`3`，观察模组日志。
5. 手机挂断后，模组回到 `IDLE`；再次拨入可重复测试，每通重新发送一次 `2`。

手机按键的预期日志：

```text
DTMF_RX digit 1
DTMF_RX_END digit 1 duration_ms ... duration_ticks ... clock_hz ... complete true
```

即时 `dtmf` 用于尽早获得按键；`dtmf_end` 表示收到有效结束事件后的持续时间。两个事件属于同一次按键，不应当成两次按键执行业务。`complete=false` 时表示持续时间不完整；没有收到有效结束包时，不会伪造按键结束。时长是网络事件时长，不保证与手指实际按住键盘的时间严格一致。

默认从拨号或接听开始，120 秒后自动挂断。需要长时间通话时修改 `call_limit_ms`。如不希望接听后自动发送按键，将 `incoming_postdial` 改为 `""`。

## 主动拨出并发送按键

把 `main.lua` 顶部改为：

```lua
local dial_string = "10086,2"
```

模组在 `CC_IND("READY")` 后仅主动拨出一次；接到真实 `AUDIO_START` 后处理逗号，等待 2 秒，再发送按键 `2`。根据实际菜单等待时间，可改为 `"10086,,,2"`。`cc.dial()` 仅接收主号码，逗号和后续按键由脚本处理。也可以填写自己的测试手机号码加 `,2`，让手机接听后测试双向说话和手机按键接收。脚本不打印真实号码。

10086 发送能力以实际听到菜单切换为准，`DTMF_SDK_ACCEPTED` 或 `POSTDIAL_COMPLETE` 日志只表示本地请求进度。发送完成后仍保持通话并继续接收对端按键。

## 接收接口

初始化顺序为：配置音频设备，`cc.init(0)`，等待 `CC_IND("READY")`，调用 `cc.dtmfRx(true)` 并确认成功后打印 `RX_ENABLED`，随后才允许拨号或接听。不能在 IMS / 通话系统尚未就绪时提前开启接收；重复 `READY` 不重复初始化。接收监听：

```lua
sys.subscribe("CC_DTMF_RX", function(event)
    if event.event == "dtmf" then
        log.info("key", event.digit)
    elseif event.event == "dtmf_end" then
        log.info("key_end", event.digit, event.duration_ms, event.complete)
    end
end)
```

接收利用 VoLTE 协商的网络按键事件，独立于 ES8311 的语音 PCM，不要求手机把按键音混入语音，也不通过麦克风识别声学测试音。普通音频接收与已有 UART 桥接接收分别由对应通话模式管理。

## 真机验收

需用配套新固件完成实测：正常双向说话、按键 `1→1→2→3` 的顺序与次数、按键结束时长、重复挂断重拨，以及拨打 10086 后发送 `2` 的实际菜单切换。仅编译通过或收到 SDK 发送确认不能替代这些验收。
