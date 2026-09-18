# Air8000 CC ↔ SIP：bridge_pcm 专用 Demo

本目录用于没有外置 codec 的 Air8000，支持 SIP 呼入转手机、手机呼入转 SIP、双向语音、早期媒体/彩铃与挂断同步。
CC 固定调用 `cc.init(0, cc.AUDIO_MODE_BRIDGE_PCM)`，VoIP 固定使用 `voip.AUDIO_MODE_BRIDGE`。
SIP 仅支持 PCMA/PCMU、8 kHz、20 ms；蜂窝侧支持 8/16 kHz PCM。

本 demo 不初始化 codec、I2S、DAC、UART 音频或 Audio V2 音频请求，不提供本地听筒、麦克风、录音及通话中切换后端。
固件仍保留 Audio V2，供其他应用使用。`sip_cc/pcm_sip.lua` 处理本 demo 的 SIP 媒体控制；本目录不需要 `exsip.lua`、`exaudio.lua` 或 `audio_drv.lua`。

## 固件与烧录

1. 使用已包含 CC 纯 PCM 后端和配套 SDK PCM 接口的 Air8000 13 号固件。
   原 V2050、未集成该功能的普通固件不能仅通过更新脚本获得该能力；版本号本身不能作为判断依据。
   脚本检查 `cc.AUDIO_MODE_BRIDGE_PCM`、`bridgePcmStats()` 必需字段和单调时钟，能力不足或 CC 初始化失败时停止启动。
2. 在 Luatools 新建脚本项目，添加**`main.lua`、`netdrv/` 下的 3 个脚本和 `sip_cc/` 下的 6 个脚本，共 10 个 `.lua` 文件**。
   添加子目录中的脚本时保留文件名，`require` 名称无需增加目录前缀。唯一入口为 `main.lua`。请移除项目中旧 demo 和诊断脚本的选择。
3. 从本仓库的 [script/libs](../../../../script/libs) 目录直接添加以下公共库文件，保留原文件名：
   `exsipclient.lua`、`exsipproto.lua`、`exnetif.lua`、`dnsproxy.lua`、`dhcpsrv.lua`、`httpdns.lua`、`udpsrv.lua`。
   这些文件包含 Wi-Fi 驱动的间接依赖，可满足 Luatools 对脚本中 `require` 的合并检查；不需要复制到 demo 目录。
   `sys`、`sysplus` 使用固件内置库。
4. 启动后应看到 `SIP_CC_BRIDGE_PCM 1.1.0`、`CC 初始化完成 bridge_pcm` 和 `SIP 注册成功`。

## 配置

`sip_cc/config.lua` 和 `netdrv/netdrv_wifi.lua` 使用示例占位值。**烧录前必须填写实际参数**，占位值不能用于注册或拨号。

| 文件/参数 | 设置内容 |
| --- | --- |
| `sip_cc/config.lua` 的 `sip_server_addr`、`sip_server_port`、`sip_domain` | SIP 服务器地址、端口及域；示例为 `sip.example.com:5060` |
| `sip_username`、`sip_password`、`sip_transport` | 模组 SIP 账号、密码和传输协议 |
| `target_phone_number` | 未能从 SIP Request-URI、To 提取号码时使用的默认手机号 |
| `remote_sip_uri` | 手机来电后拨打的 SIP 客户端 URI |
| `codec`、`ptime` | PCMU 或 PCMA，20 ms |
| `cc_audio_start_timeout_ms` | 蜂窝业务接通后等待 PCM 就绪的超时，默认 **3000 ms**；重复事件不续期 |
| `cc_media_min_connected_ms` | 原始 CONNECTED/CONNECTED_NUMBER 接通至少 **2000 ms** 才可计作缺 PCM；<=0 关闭统计 |
| `cc_media_missing_call_limit` | 连续 **3** 通符合条件且无真实 PCM 时发布异常；<=0 关闭统计 |
| `cc_media_reboot_on_error` | 默认 **true**，异常后清理并重启；false 仅观察异常事件 |
| `netdrv/netdrv_device.lua`、`config.adapter` | 网卡驱动与 SIP/RTP 网卡必须一致 |

默认使用 4G：启用 `require "netdrv_4g"`，`adapter=socket.LWIP_GP`。
使用 Wi-Fi 时改为启用 `require "netdrv_wifi"`，设置 `adapter=socket.LWIP_STA`，并填写 `netdrv/netdrv_wifi.lua` 中的热点名称和密码。
两种驱动只启用一种。Wi-Fi 脚本通过 `require "exnetif"` 使用公共库；其 DNS/DHCP/UDP 依赖也统一来自 `script/libs`。

## 呼叫保护

旧 CC 收到终结事件、VoIP 收到停止确认且原生状态 idle、PCM/SDK 释放后，再等待 **500 ms** 启动下一通。间隔从释放完成开始计算，没有新来电时也会计时；第一通不加间隔。

清理或间隔期间最多等待一通 SIP 来电，维持 `100 Trying`，不会提前发送 183、启动媒体或拨 CC。等待从新来电到达起最多 **3000 ms**，超时对该 Call-ID 回复 480；真实占线仍回复 486。等待中取消只移除该来电，不再次挂断旧 CC，也不重置旧通话的间隔。手机呼入同样等待释放和间隔，期间保持响铃；手机提前挂断不再拨 SIP。

PCM 释放检查要求 `active`、`media_ready`、`dl_queued`、`ul_queued`、`sdk_active`、`sdk_pending`、`sdk_stop_waiting` 为整数零。手机新来电已由 C 层建立新 session 时，只允许该待接来电自身的 `active=1`；其余字段仍须为零，不能因旧 SDK pending 尚未归还而提前拨 SIP。检查仅在清理或等待阶段每 100 ms 执行，不持续打印统计。

业务命令、定时器和转发事件带 Call-ID/本地代次；183 已发送且 VoIP 真正 `started` 后才拨 CC。停止媒体覆盖 STARTING，同一实例只请求停止一次；re-INVITE 更换媒体要先等旧实例释放。公共 `exsipclient.lua` 直接使用本仓库版本，保留 200 重传、ACK 截止、旧对话后台收尾及每通 RTP 端口隔离。

号码优先从 Request-URI 提取，其次 To，最后使用 `target_phone_number`。保留 PCMA/PCMU、8 kHz/20 ms 和原有双向 PCM 通道，不接入外置音频驱动。

## 无真实 PCM 事件与恢复

每通只以匹配 `bridgePcmStats().session` 的 `dl_pushed > 0` 作为真实 HAL 下行 PCM 证据，静音 PCM 同样有效。RTP 包、SDK 启动、上传静音和队列非空不能替代这个证据。

统计以原始 `CONNECTED`/`CONNECTED_NUMBER` 开始计时，主动挂断以首次请求时刻截止。`ANSWER_CALL_DONE` 保留业务接通用途，不单独启动监测计时。未接通、取消或不足 2 秒不增加计数，收到真实 PCM 清零；统计 session 已被覆盖则视为未知并打断连续计数。每通终结只结算一次。

达到阈值后发布一次 Lua 业务事件，可供其他业务订阅：

```lua
sys.subscribe("CC_BRIDGE_MEDIA_ANOMALY", function(reason, detail)
    -- reason == "NO_MODEM_PCM"
    log.warn("pcm_monitor", reason, detail.generation, detail.session,
        detail.missing_calls, detail.connected_ms)
end)
```

启用默认恢复时，停止接收新桥接，清理 SIP/CC/VoIP；实际释放后立即重启，最多等待 **3000 ms**。`cc_media_reboot_on_error=false` 仅观察，不进入恢复状态。原生 `CC_BRIDGE_MEDIA_ERROR(reason, session)` 继续按该 session 的 SDK 故障结束通话，不直接转换成三通无 PCM 异常。

这项 Lua 统计是缓解与诊断措施，不代表已修复底层长期压测故障，也不能与原 C 监测完全等同。普通 CC 原生终结消息没有 session，统计被覆盖或原生事件丢失时不能保证识别；有过真实 PCM 后的中途断流不属于本判据。

## 实机测试

1. 按上述清单烧录 **10 个 demo 文件和 7 个当前公共依赖**，确认启动修复标识。旧客户目录保留，勿把其同名 `bridge.lua`、`cc_main.lua`、`sip_main.lua` 或旧媒体库混入此项目。
2. SIP 呼入转手机、手机呼入转 SIP 分别测试 PCMA/PCMU、响铃延迟接听和两侧挂断；检查真实彩铃、接通后的双向语音，分别记录蜂窝 8/16 kHz 覆盖情况。
3. 在上一通挂断请求后立即发起下一通，交换 CC/VoIP 停止先后顺序，确认只保留 100，实际释放后至少 500 ms 才发 183/启动下一通；等待超过 3 秒回复 480。分别取消等待中、拨号中和 VoIP STARTING 中的通话。
4. 丢弃 SIP ACK 后由手机先挂断，再立即拨入；确认旧信令后台收尾不影响新媒体，检查 SDP 协商的本地 RTP 端口与实际包流一致、旧端口残留包不会进入新通话。服务器/网络需允许已协商的候选本地端口。
5. 先设置 `cc_media_reboot_on_error=false` 观察事件，再启用 true 验证连续 3 通真实接通至少 2 秒但无 PCM 后清理和重启；短通话、真实静音、健康通话、原生 SDK 错误分别核对，不用单纯丢 RTP 来模拟无 modem PCM。
6. 完成**超过 600 通连续呼叫**，分别记录成功通话数、480/486 原因、PCM session/dl_pushed 和重启事件；确认无重复拨号、遗留通话、上一通音频及内存持续增长。另保留至少一通 60 分钟通话测试。

模块自身不播放早期媒体；真实蜂窝媒体优先于合成彩铃。`PLAY=0` 只结束当前媒体阶段，接通后等待新 `AUDIO_START`；重复事件不延长 3000 ms 超时。

正常通话不会按固定时长自动挂断。保留从上电到异常和挂断后的完整 Lua/底层日志、匹配固件的 ELF/MAP；运行统计可按需调用 `cc.bridgePcmStats()` 查询。
