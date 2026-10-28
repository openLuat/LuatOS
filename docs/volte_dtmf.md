# VoLTE 网络 DTMF 接收与发送

此文档整理接收 VoLTE RTP telephone-event 并识别按键、上报事件持续时间，以及模组主动发送网络 DTMF。按键接收和主动发送已由用户实测；新增时长上报已完成主机回归，仍需真机验证。LuatOS 通用代码与 `../luatos-soc-2024` 的 EC7xx 平台适配需要配套使用。

## 当前能力与验收

| 方向 | 当前实现 | 验收记录 |
| --- | --- | --- |
| 接收 | 根据 SIP/SDP 协商的 PT、clock、事件集合及当前 RTP 对端解析按键，向 Lua 发 `dtmf` 事件 | 用户确认真实手机按键与日志一致；分机 1、2 外呼和双向通话通过 |
| 持续时间 | 保留原有即时 `dtmf`，另以 `dtmf_end` 上报结束时长、协商时钟、媒体代次和完整性标志；支持长事件连续分段累计 | 主机解析、平台适配、通知与 Lua 绑定回归通过；新增时长待真机验收 |
| 发送 | `cc.sendDtmf` 异步向 IMS 提交一个按键和指定毫秒时长 | 2026-10-16 用户确认拨打 10086 后发送 `2` 可以切换对应业务 |

40 ms 是接收按键的确认门限，达到门限就可触发分机选择。最终时长来自有效结束包的 RFC4733 `duration` 字段，按本次协商的 `clock_hz` 换算为整数毫秒并向下取整，不能固定假设 8000 或 16000。这是发送端报告的网络按键事件时长；有些手机发送固定长度事件，因此它不一定等于手指实际按住屏幕的时间。

收到有效 E=1 结束包后只上报一次 `dtmf_end`；重复结束包不重复上报。长事件在相同源、相同按键、无新起始标志且前段达到 65535 ticks、时间戳严格连续时累计分段。无法确认连续性的同键分段只报告可确认的尾段，并置 `complete=false`。未收到有效结束包时不补造结束时间；只有 `complete=true` 才能把时长作为当前已确认网络事件的完整值。

## 接收路径

接收有两个独立入口，共用 SIP/SDP 和 RFC4733 解析器：`LUAT_USE_CC_UART_BRIDGE` 用于原双板分机业务的 A 侧；`LUAT_USE_CC_DTMF_RX` 用于普通 codec 单模组通话。普通模式保留 ES8311 麦克风和扬声器通路，不初始化 UART 桥接、媒体上传或存储组件。两种入口不能同时占用同一个接收器。

主要源码：

- `components/cc/cc_bridge/uart/luat_cc_uart_sip.[ch]`：SIP/SDP 解析，当前会话、对端和 telephone-event 协商信息；解析临时区在各上下文内，避免占满 SDK 接收任务栈。
- `components/cc/cc_bridge/uart/luat_cc_uart_rfc4733.[ch]`：RTP 头、扩展、填充、事件集合、时间戳和持续时间校验，按住及重复结束包去重。
- `../luatos-soc-2024/project/luatos/src/luat_cc_uart_dtmf_rx_ec7xx.c`：通过公开 socket ABI 观察当前 SIP/SDP 和 RTP，将真实接收的按键交付任务队列。
- `components/cc/cc_bridge/uart/luat_cc_uart_bridge.c`、同目录 `luat_lib_ccuart.c`：会话、媒体门禁和 Lua 事件交付。

当前 SDK 真机验证的是明文 TCP SIP 观察路径；不据此承诺加密 SIP 或 SDK 内部绕过已包装公开入口的路径可用。PT 和 clock 来自协商，不能把某次测试的 PT96/16000 写成固定协议参数。

Lua 通知形状：

```lua
ccuart.on(function(event)
    if event.event == "dtmf" then
        log.info("received_key", event.data.digit)
    elseif event.event == "dtmf_end" then
        local d = event.data
        log.info("key_duration", d.digit, d.duration_ms, d.duration_ticks,
            d.clock_hz, d.epoch, d.complete)
    end
end)
-- 正确 setup、begin 和真实 media_ready 后：
-- ccuart.dtmf(session, true)
```

`dtmf_end.data` 包含 `digit`、`duration_ticks`、`duration_ms`、`clock_hz`、`epoch` 和布尔值 `complete`。两个时长使用 64 位累计；可由当前 Lua 整数精确表示时交付整数，超过 `LUA_MAXINTEGER` 时交付精确十进制字符串，避免 32 位 Lua 截断或浮点精度损失。新固件以 `ccuart.DTMF_END_VERSION == 1` 标示接口能力。

识别须保持启用直至结束包。原分机业务仍可收到早期 `dtmf` 就立即拨号并关闭识别；这种用法不等待 `dtmf_end`，也不会因新增结束通知重复拨号。使用时长接口须配套包含该能力的新固件，并保持接收启用至结束通知。

UART 桥接接收依赖 `ccuart` 的平台、上传、媒体和存储组件。即使无 SD 运行模式不录音，桥接绑定仍引用这些函数，因此该模式构建仍需保留必要源码依赖。Codec、SIP PCM 和 UART PCM 音频后端选择互斥。

### 普通 codec 通话接收

固件开启 `LUAT_USE_CC_DTMF_RX`，同时编译共享 SIP/SDP、RFC4733 解析器和 EC7xx 接收适配，并保留相应 socket linker wrappers。只使用普通通话时无需开启 `LUAT_USE_CC_UART_BRIDGE`。在普通 `cc.init(0)` 后，等待 `CC_IND("READY")` 再开启接收，随后才拨号或接听，以便 SDK 能确认当前呼叫空闲：

```lua
sys.subscribe("CC_DTMF_RX", function(e)
    if e.event == "dtmf" then
        log.info("key", e.digit, e.session)
    elseif e.event == "dtmf_end" then
        log.info("key_end", e.digit, e.duration_ms, e.complete)
    end
end)
sys.subscribe("CC_IND", function(status)
    if status == "READY" then assert(cc.dtmfRx(true)) end
end)
assert(cc.init(0))
```

随后通过 `cc.dial` 或 `cc.accept` 建立通话，每通分配独立接收 session。真实双向媒体开始后启用按键交付，早期彩铃不启用；挂断、外呼失败及本地停止会清空会话并丢弃已排队的旧通知。开启状态跨通话保留；`cc.dtmfRx(false)` 可关闭接收。不要在通话中首次开启接收。

`CC_DTMF_RX` 的参数是一个 table，包含 `event`、`digit`、`session`；`dtmf_end` 另含 `duration_ticks`、`duration_ms`、`clock_hz`、`complete`，精度规则与桥接接口相同。`cc.dtmfRxStats()` 提供协商及接收计数，不包含手机号、地址或 SIP 文本。新固件使用 `cc.DTMF_RX_VERSION == 1` 标示该接口。

普通模式支持手机呼入，以及在 `cc.dial` 前预留会话后绑定本地主动发出的初始 INVITE；两方向都校验 Call-ID、标签、信令 socket 和协商媒体端点。示例为 `module/Air8000/demo/cc_dtmf_duplex/`。普通 codec 收发组合及新增呼出接收路径仍需配套新固件真机验收，不能沿用原双模组实测结论。

## 发送路径与接口

```lua
sys.subscribe("CC_DTMF_TX", function(request_id, ok, code)
    log.info("dtmf_tx", request_id, ok, code)
end)
-- 成功初始化 cc 并真正接通后调用：
local ok, request_id_or_error = cc.sendDtmf(0, "2", 300)
```

SIM 目前仅支持 0，按键是单个 `0–9`、`*`、`#` 或 `A–D`；时长 100–1000 ms，默认 300 ms。返回 `true, request_id` 表示已进入发送任务，失败返回 `false, reason`。`CC_DTMF_TX` 是 SDK 请求确认，不证明远端业务已响应。

`components/cc/luat_lib_cc_v2.c` 包含参数校验、独立 4 KiB 发送任务、单请求占用、通话代次取消及结果发布；公共 C 声明在 `components/mobile/luat_mobile.h`。EC7xx 的 `interface/src/luat_mobile_ec7xx.c` 先检查唯一 ACTIVE 通话，再调用公开 `appSetVTSSync`。DTMF 由 IMS 媒体栈生成，不向 PCM 混入合成音调，也不手工指定 RTP PT。

SDK 的同步查询及发送等待没有可证明的有限超时上界，因此均在独立发送任务执行。请求未返回时禁止新 `dial/accept`，挂断任务保持独立。挂断可取消尚未执行的请求，进入 SDK 的操作不能撤回。应用的 15 秒等候超时不能强制终止 SDK 内部等待；如一直不返回，需要显式重启后再测。

## 后拨序列与配置

`10086,2` 应由应用拆成主号、暂停和按键：先调用 `cc.dial(0, "10086")`，等待真实接通和音频媒体就绪，再暂停所需时间并调用 `cc.sendDtmf(0, "2", 300)`。主号码通过呼叫信令拨出，不是由 DTMF 音频建立电话；`cc.dial` 本身只接收主号，没有增加逗号解析，双板 `routes` 也未改为接受后拨序列。

每个逗号暂停 2000 ms 可以作为应用约定，不是 VoLTE 固定规范。应用可根据 IVR 提示配置暂停时长，连续发送时须等待前一请求的 SDK 确认，并保留按键持续时间及键间间隔；媒体重建时暂停未发送步骤。真实菜单切换才是远端接收成功的依据，SDK 接受日志不能单独替代该结果。

配套固件可选 EC718HM、13 号 VOLTE、32 位 Lua，`lspd_mode=n / denoise_force=y`，固定 GCC 10.2.1；型号按实际 Air780EHM 或 Air8000 配置。需要 UART 桥接时在语音固件配置中显式定义 `LUAT_USE_CC_UART_BRIDGE`，本次源码集成不默认开启该宏；真机验收依据是 13 号。配置和构建集成改动后须按 SoC 仓库规范完整构建。

## 验收边界

用户已确认真实按键可用于分机 1、2 外呼及双向通话，拨打 10086 后主动发送 `2` 可切换对应业务。新增接收时长尚待真机验证：保持接收启用，在通话中按相同和不同数字、分别保持不同时间，核对键值、结束事件和时长，挂断重拨后再测。若手机发送固定时长，应以实际网络事件字段为准，不能只按手指停留时间判定。
