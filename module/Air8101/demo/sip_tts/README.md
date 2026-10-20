# Air8101 SIP 通话中向对端播报 TTS

在 SIP 通话过程中，把合成的 TTS 语音作为**上行 RTP** 播给对端（对方听到播报），本机扬声器不参与。芯片侧实现见 `docs/voip-tts-air8101-port.md`。

## 前置条件

| 项 | 要求 |
|---|---|
| 硬件 | 16MB Flash 的 Air8101 / Air8101B |
| 固件 | 106（`python build_luatos_types.py Air8101 106`），需启用 `LUAT_USE_VOIP_PLAY` |
| SIP 媒体 | G.711 PCMU/PCMA，8kHz、20ms 帧 —— `voip.playTTS` 只在这个条件下放行 |
| 对端 | 另一台 Air8101 或手机 SIP 客户端（如 Zoiper / Linphone），或 Asterisk/FreeSWITCH |

## 使用步骤

1. **SIP 账号和被叫都不用手填**：`main.lua` 用 `hmeta.devid()` 取 STA MAC，转成十进制后：
   - `sip_username` = 十进制 + `"0"`
   - `callee_number` = 十进制 + `"1"`

   注意 `hmeta.devid()` 在 WiFi 模组上返回的是 **6 字节原始 MAC（二进制）而不是十六进制字符串**，
   代码内部逐字节转成 12 位十六进制再换算，异常时回退 `wlan.getMac()`。
   例如 `C8C2C69506BC` → `220738880865980`，则账号 `2207388808659800`、默认被叫 `2207388808659801`。
   启动时会打印两者，请确认账号在服务器上已存在或可自动开户。
2. **密码默认 `"123456"`**，按你的 SIP 服务器实际值修改 `sip_config.sip_password`。
3. 修改 `sip_config.sip_server_addr` / `sip_server_port` / `sip_domain`。被叫默认按 `+1` 推导，
   要拨固定号码时把 `callee_override` 设为该号码字符串。
4. 按底板调整 `audio_setup_param.pa_ctrl`（PA 使能脚）与 `pa_on_level`。
5. 把 `main.lua` 作为入口脚本合并烧录；若工程已有入口，则 `require "sip_tts"`，且入口末尾要调 `sys.run()`。
6. 上电后自动注册 → 外呼 → 接通 → 播报一次 `SAY_TEXT`。

## 预期日志

```
I/user.sip_tts 设备 SIP 账号: 2207388808659800 默认被叫: 2207388808659801
I/user.sip_tts 注册: ok
I/user.sip_tts 通话: connected
I/user.sip_tts 播报已启动, id = 1 attempt = 1
I/user.sip_tts play 事件: started sip_samples: 0 reason:
I/user.sip_tts play 事件: done sip_samples: 33133 reason: done
```

`sip_samples` 是已提交到 SIP 上行的 8kHz 样本数，`done` 时约等于播报时长的 8 倍。

## 验收清单

| # | 检查项 | 通过标准 |
|---|---|---|
| 1 | 接通即播 | 对端听到清晰中文播报，无断续、无变调 |
| 2 | 事件顺序 | `started` → `done`，且 `sip_samples` 随时间增长 |
| 3 | 中途打断 | 播报中 `voip.playStop(id)` → 事件为 `stopped`，通话继续 |
| 4 | 中途挂断 | 播报中 `exsip.hangUp()` → 不重启、无残音、可正常再呼 |
| 5 | 连续通话 | 连打 3 通，每次都能播报；PSRAM 无持续增长 |
| 6 | 本地 TTS 回归 | 同一固件上 `module/Air8101/demo/audio/play_tts.lua` 仍能正常出声 |

## 四个必须注意的点（踩过坑）

1. **入口脚本必须有 `PROJECT` 和 `VERSION`**（全局变量，不是 `local`），否则 Luatools 合并报"main.lua缺少PROJECT或者VERSION"。
2. **结尾必须有 `sys.run()`**。LuatOS 的 `luat_main_call()` 只执行一次脚本，脚本一旦返回就打印 `Lua VM exit!! reboot in 15000ms` 并重启；常驻任务靠 `sys.run()` 进入调度循环。`sys.run()` 之后不要再写任何语句。
3. **本 demo 不依赖 `exsip.say()`**。固件不打包 Lua 脚本，`exsip.lua` 来自你合并时用的脚本目录；若该目录里的 `exsip.lua` 是旧版，`exsip.say()` 不存在。demo 内 `say_to_peer()` 直接调 `voip.playTTS`，只需合并 `main.lua`。
4. **`hmeta.devid()` 返回 6 字节原始 MAC，不是十六进制字符串**；且本固件 printf 未链接浮点支持（无 `_printf_float`），`string.format("%.0f", ...)` 会输出 `2e+14` 这类结果。所以账号推导用 `mac_to_hex()` + `hex_to_dec()` 全程整数/字符串运算，不要再改回 `%.0f` 或 `tostring(浮点数)`。

## 联网

demo 顶部有 `WIFI_SSID` / `WIFI_PASSWORD`：
- 留 `nil`：假定你的工程里已有联网逻辑（`exsip` 会等 `IP_READY`）；
- 填上：demo 自己 `wlan.init()` + `wlan.connect()`。

日志出现 `adapter not ready, waiting for IP_READY` 即表示还没联网，此时不会注册、不会外呼。

## 已知限制
- **只支持 G.711 通话**：若协商到 Opus/G722/G729，`voip.playTTS` 返回 `unsupported`，需回落为短信提示或改用 `voip.playFile`（PCM/WAV）。
- **同一时刻只有一个播报任务**：第二次调用返回 `busy`，需先 `voip.playStop(id)`。
- **默认 REPLACE 模式**：播报期间不向对端发送麦克风声音；需要同时送麦克风时传 `{mode="mix"}`。
- **播报内容长度**：引擎同步合成，超长文本会长时间占用播报任务，建议单条控制在 200 字以内，长文本按句拆分。
