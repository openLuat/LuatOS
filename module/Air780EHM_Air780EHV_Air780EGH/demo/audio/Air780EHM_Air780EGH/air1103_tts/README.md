# Air780EHM + Air1103 离线 TTS

本示例首期验证目标仅为 **Air780EHM 13/113** 固件；所在父目录包含其他型号，不代表本功能已验证那些型号。固件须启用 Audio V2、板载 16k TTS 资源和 `LUAT_USE_AUDIO_TTS_PCM`。

下载本目录 `main.lua`，以及公共库 `script/libs/exaudio.lua`、`script/libs/air1103.lua`。不要同时下载上级目录的 `main.lua`。UART1 的 TX/RX 与 Air1103 交叉连接并共地，通信波特率 2Mbps；引脚、电平、供电和 Air1103 固件版本按实际硬件核实并记录。

无需联网。`play_start({type=1, content=...})` 返回 `true` 表示受理；完成回调携带 `done`、`stopped` 或错误原因。活动会话期间新播放及新调用 `record_start()` 返回 `busy`，调用 `play_stop()` 后须等待 `is_end()` 为 `true` 再重播、开始录音或进入通话。完成回调中可启动下一句；音量用 `exaudio.vol(0..100)` 调整。

首期无自动排队、抢占或通话混音。已进入芯片的短暂尾音不能撤回。100ms 尾静音仅为初始参数，没有芯片播放完成 ACK。实机项目当前未验证，完整记录见[实现记录](../../../../../../docs/air1103_tts_ec718hm_implementation.md)。
