# Air8784 离线 TTS 播报示例（demo）

本示例在 **Air8784** 模块上测试，演示其**离线 TTS 语音播报**最小工程（模块已集成 Air1103，无需外部 UART 接线）：上电使能 Air1103，初始化后调用 `exaudio.play_start({type=1, content=文本})` 即可把文本合成为语音并从喇叭播出，**无需联网、无需云端 TTS**。初始化完成后开机播报一次，之后每按一次 SOS 按键（GPIO20）再播报一次。


## 一、硬件说明

Air8784 已集成 Air1103 语音芯片，**无需外部 UART 接线**（模块内部 UART1，2M 波特率），只需上电使能。

| 项目 | 说明 |
|---|---|
| Air1103 | 已集成在 Air8784 模块内，无需外部 UART 连线 |
| Air1103 供电 | GPIO22 高电平使能 |
| SOS 按键 | GPIO20，上拉，按下拉低（按实际底板调整） |
| 音频 | 模块喇叭输出（仅 PCM） |


## 二、目录结构

```
demo/
├── main.lua     # 入口：Air1103 供电使能(GPIO22) + 加载 tts_app + sys.run()
├── tts_app.lua  # 离线 TTS 播报逻辑：exaudio 初始化 + play_start({type=1})（require 时自动启动）
└── readme.md
```


## 三、使用步骤

1. 用 Luatools 打开本 `demo/` 目录，core 选择 **Air780EHM**（Air8784 模块），lib 目录指向仓库 `script/libs`。
2. 烧录（如脚本区超限，勾选「无调试信息」；详见出厂固件注意事项）。
3. 设备启动后，日志出现 `air1103.tts 请求受理  true` 即表示 TTS 已受理，随后喇叭播出"你好，这是离线语音播报……"。
4. 播完日志打印 `air1103.tts 播放结束`，`exaudio.is_end()` 返回 `true`，此时可播下一句或进入通话。
5. 按一次 SOS 按键（GPIO20），稍作延迟后再播报一次；播报中按键会被忽略（避免 `busy`）。


## 四、代码说明

**`main.lua`（入口）**：仅做 Air1103 供电使能（GPIO22 拉高）后 `require "tts_app"`，最后 `sys.run()`。

**`tts_app.lua`（TTS 逻辑）**：被 require 时自动 `sys.taskInit` 启动播放任务。

```lua
-- tts_app.lua 中
sys.wait(200)  -- 等 Air1103 上电稳定（供电已在 main 中通过 GPIO22 拉高）
assert(exaudio.setup({ model = "air1103", uart_id = 1, audio_mode = "new" }), "Air1103 初始化失败")
```

- `audio_mode="new"` 是离线 TTS 的前提；若固件未注入 `audio_v2` 全局，此 setup 会返回 `false`，需换带 tts_pcm 的固件。

```lua
exaudio.play_start({ type = 1, content = "文本", cbfnc = ttsCallback })
```

- `type = 1`：离线 TTS（本地合成）。
- `content`：要播报的中文文本（支持数字、常用量词读法）。
- `cbfnc`：播放完成回调（`tts_app.lua` 中的具名函数 `ttsCallback`），`event == exaudio.PLAY_DONE` 表示播完。

**SOS 按键触发播报**（`tts_app.lua`）：GPIO20 上拉、下降沿中断，防抖 50ms；中断里只 `sys.publish("SOS_PRESS")`，实际播放在音频任务中执行。每次触发前先判断 `exaudio.is_end()`，正在播报则忽略，避免 `busy`：

```lua
-- tts_app.lua 中
gpio.debounce(SOS_PIN, 50)
gpio.setup(SOS_PIN, function() sys.publish("SOS_PRESS") end, gpio.PULLUP, gpio.FALLING)

-- 播放任务中
while true do
    sys.waitUntil("SOS_PRESS")
    playOnce()  -- is_end() 为 false 时直接返回，不发起播放
end
```

- 开机初始化完成后的 2 秒内（含 `exaudio.setup` 耗时）按键消息无人接收会丢弃，属于正常现象。
- 改按键脚位：修改 `tts_app.lua` 顶部的 `SOS_PIN`。
- 改按键后延迟：修改 `tts_app.lua` 顶部的 `SOS_DELAY_MS`（当前 1000 毫秒）。
- 改播报文本：修改 `tts_app.lua` 顶部的 `TTS_TEXT`。


## 五、注意事项

- **必须等播完**：播放中或未完成回调前再次调用 `play_start` 会报 `busy`；只有 `exaudio.is_end()` 为 `true`（或已收到 `PLAY_DONE`）才能启动下一句/通话。
- **中途停止**：`exaudio.play_stop({ type = 1 })`。
- **与 SIP 通话互斥**：TTS 占用音频通路，通话中不宜同时播 TTS；业务固件中已通过 `cc_sip_bridge` 处理桥接，本示例未涉及。
- **音量**：`exaudio.vol(0~100)` 调节喇叭音量。
- **改文本/多句**：直接修改 `content` 字符串；多句顺序播报时，需在前一句 `PLAY_DONE` 或 `is_end()==true` 之后，再发起下一句 `play_start`。
