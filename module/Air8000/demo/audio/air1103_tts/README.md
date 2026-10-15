# Air8000 + Air1103 离线 TTS

使用本次功能对应的 Air8000 **13 或 113** 号固件，启用 Audio V2、板载 16k TTS 资源和 `LUAT_USE_AUDIO_TTS_PCM`。仅更新 Lua 库不能增加固件能力。

下载本目录 `main.lua`，以及仓库 `script/libs/exaudio.lua`、`script/libs/air1103.lua`；不要同时下载上级音频 demo 的 `main.lua`。UART1 的 TX/RX 与 Air1103 交叉连接并共地，按开发板规格供电，通信波特率为 2Mbps。实际引脚、电平、Air1103 固件版本须按所用硬件核实和记录。

示例无需联网，通过 `exaudio.play_start({type=1, content=...})` 播报中文和数字。`true` 表示受理；完成回调第二参数 `done` 表示发送及尾静音收尾结束，`stopped` 表示取消完成，其他值表示错误。回调前会清除旧会话，允许回调中开始下一句。

播放期间新请求返回 `false, "busy"`，新调用 `record_start()` 同样返回 busy。调用 `exaudio.play_stop()` 后，等待 `exaudio.is_end()` 为 `true` 再启动下一句、录音或通话。已提交给芯片的短暂尾音无法撤回。TTS 不提供自动排队、抢占或通话混音。音量使用 `exaudio.vol(0..100)`。

实机播报、接线和 Air1103 固件版本尚未验证；100ms 尾静音是初始值，不是芯片播放完成 ACK。完整验收与移植说明见[实现记录](../../../../../docs/air1103_tts_ec718hm_implementation.md)。
