# Air8784 独立蜂窝电话

`user/main.lua` 默认 `BOOT_MODE = "normal"`：真机未配置时启动单 SIP，之后按 AirCloud 保存的 `sip` / `cc` / `sip_cc` 模式启动。PC 仍仅支持单 SIP。不要改成强制 `single` 或 `cc`，否则会绕过云端启动模式选择。已有的模式配置会保留。

## AirCloud 切换

通过现有 Tag19 或 Tag1281 下发 JSON；每次新指令使用不同 `id`，相同 ID 会返回缓存结果。

进入独立 CC（目前支持一个手机号，替换示例号码）：

```json
{"id":"mode-cc-001","cmd":"set_config","params":{"sos_mode":"cc","sos_cc_numbers":["13800138000"]}}
```

切回单 SIP（使用实际 SIP 账号，SIP 服务器与认证配置沿用已保存值）：

```json
{"id":"mode-sip-002","cmd":"set_config","params":{"sos_mode":"sip","sos_sip_numbers":["8643170881027620"]}}
```

切回 SIP_CC（手机号和对应 SIP 账号均需填写）：

```json
{"id":"mode-bridge-003","cmd":"set_config","params":{"sos_mode":"sip_cc","sos_sip_cc_numbers":["13800138000"],"sos_sip_cc_peers":["8643170881027620"]}}
```

成功应返回 `ok=true`、`reboot_pending=true`。配置先保存，回执完整提交给云通道且至少等待 3 秒后，设备在通话和音频均空闲时重启。通话中下发不强制挂断；挂断后再重启。保存不会自动拨号。CC 内仅修改手机号时不重启，下次按 SOS 使用新号码。

独立 CC 模式继续运行 AirCloud 的查询、配置、重连和心跳；音频初始化失败时也可远程切回 SIP。配置变更会通过 Air1103 播报模式及“等待自动重启后生效”，播报和原生音频释放完成后才允许重启。它不加载 SIP 注册或旧 SIP 轮拨任务引擎，不开放远程 `play_tts`。请统一使用 `set_config`，不要用旧文本 `mode:cc`（此前曾表示 SIP_CC 桥接）。

用 `{"id":"query-004","cmd":"get_sip_config"}` 检查 `capabilities.modes`、`sos_status.active_mode` 和 `saved_mode`。独立 CC 要求流式 CC、PCM 重采样和重启接口；SIP_CC 要求 `cc.setBridge` 和 `rtos.reboot`。缺失能力时返回 `unsupported_feature`，不会保存成无法切换的模式。接口存在不等于真机双向音频已验证。

本次仅修改 factory Lua，不需要重编译底层固件。目标为用户现有的 `LuatOS-SoC_V2054_Air780EHM_13.soc`。仓库示例注明 V2048 起的 13/113 固件支持 CC 流式上行，但尚未在该固件和 Air8784 真机上验证双向声音。

## 使用

1. 使用上述 AirCloud 指令配置独立 CC 和手机号；`cc_local_config.number` 仅用于手动强制 CC 的本地调试。
2. 将整个 factory Lua 项目烧录到真机，保留现有底层固件。插入支持语音通话的 SIM 卡，等待蜂窝网络注册。
3. 日志出现 `cc_local STATE IDLE` 后，空闲时按 SOS（GPIO20）拨号；来电时按 SOS 接听。
4. 长按 UP（GPIO21）至少 1 秒，拒接来电或挂断当前呼叫。

程序控制可发布 `CC_LOCAL_DIAL_REQ`（参数为手机号字符串）、`CC_LOCAL_ACCEPT_REQ`、`CC_LOCAL_HANGUP_REQ`。例如：

```lua
sys.publish("CC_LOCAL_DIAL_REQ", "目标手机号")
sys.publish("CC_LOCAL_ACCEPT_REQ")
sys.publish("CC_LOCAL_HANGUP_REQ")
```

`CC_LOCAL_STATE` 发布 INIT、IDLE、PREPARING、DIALING、INCOMING、ANSWERING、CONNECTED、RELEASING、RELEASE_ERROR 或 ERROR。PREPARING 表示正在播报“正在拨号”，尚未提交蜂窝拨号；此时长按 UP 可以取消。IDLE 表示应用初始化完成，不代表 SIM 已注册或网络允许通话。拒绝重复拨号；拨号超时自动请求挂断；挂断确认超时不直接回到 IDLE。

## 音频与验证

- UART1、2 Mbps、GPIO22 供电连接 Air1103，无 ES8311 初始化；GPIO23 参考电压沿用主入口。
- Air1103 的 16 kHz MIC 数据经 `cc.extern_source` / `cc.input` 注入普通 CC 上行。8 kHz 呼叫使用 PCM 重采样器。
- `cc.record` 的下行双缓冲转发至 Air1103 扬声器；不保存录音文件。缓冲对象在应用运行期间保持引用。
- 不加载 SIP、CC–SIP 桥接、旧 SIP 任务引擎和 SIP 键盘；AirCloud 配置通道和主入口 FOTA 保留。
- 拨号前播报“正在拨号”，原生 TTS 释放后才拨号；播报期间来电优先，旧的拨号请求作废。当前没有本地来电铃声，早期媒体也不保证可播放。
- `PCM_START` 仅表示接口接受了启动请求。通话中每 5 秒输出 `PCM bytes TX/RX`；计数应持续增加。先测试双方说话，再测试来电接听、拒接、挂断后再次拨号，以及 8/16 kHz 呼叫。
- 缺少接口、上行阻塞或下行无数据会明确报错并请求挂断，避免长期停留在无声通话中。采样率在同一次通话内发生变化也会结束通话。
- 若 V2054 的普通 CC 后端在无物理 I2S Codec 时不能提供录音或流式注入，Lua 不能补齐底层能力；请保留错误日志，此实现不把接口存在当作真机双向音频已验证。
