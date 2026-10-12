# CC/SIP 纯 PCM 桥接

该后端供无外置 codec 的 Air8000w 使用，媒体不经过 I2S、DAC、UART 音频或 Audio V2 音频请求。
固件继续保留 Audio V2，`cc.init(0)` 仍选择原音频后端。普通 SIP 的音频模式不会隐式切换 CC 后端。

## 配套仓库

需要同时集成以下三部分，不能只更新 Lua 或复制头文件：

| 仓库 | 配套实现 |
| --- | --- |
| `luatos-sdk-ec7xx` | `soc_mobile_pcm.h`、`soc_pcm_upload_core.h` 及对应 `libcore_airm2m.a` 实现；SDK 源码使用已有 `__USER_CODE__` 宏隔离新增逻辑 |
| `luatos-soc-2024` | `luat_cc_pcm_bridge_ec7xx.c`、通话事件分发和通话状态查询；启用 `LUAT_USE_CC_PCM_BRIDGE`，保留 `LUAT_USE_AUDIO_V2` |
| `LuatOS` | CC 初始化及接口分发、PCM 队列/转换核心、VoIP 帧接口和独立 demo |

SDK 配套源码提交为 `cd65c409`，SoC 后端提交为 `d6a9740d`。构建前应确保实际链接的 SDK 库和公共头都包含对应实现；源码提交不等同于已发布 SDK 二进制包。

在配套 SoC 仓库使用：

```powershell
python build_luatos_types.py Air8000 13
```

构建配置变化时按 SoC 仓库要求全量重编。固件版本号不能代替能力检查。

## 接口

```lua
-- 使用原音频后端
assert(cc.init(0))

-- 实际应用只选择所需的一种模式；纯 PCM demo 使用下面的初始化
assert(cc.AUDIO_MODE_BRIDGE_PCM, "firmware has no CC PCM backend")
local ok, reason = cc.init(0, cc.AUDIO_MODE_BRIDGE_PCM)
assert(ok, reason)
```

同一模式重复初始化幂等；通话期间不能切换后端。空闲切换仍需等待 SDK 在途帧真实归还，否则返回失败。
`cc.bridgeTone()` 控制发往 SIP 的合成彩铃；`cc.bridgeAudioStop()` 幂等关闭纯 PCM 媒体，其他后端返回失败；`cc.bridgePcmStats()` 获取运行统计。
PCM 模式下的本地录音、外部音源和流输入返回失败。本后端不提供 `cc.bridgeSpeechStart()` 或 `cc.bridgeMediaMonitor()`，保留主干原有的 `cc.setBridge()` 接口。

## 数据和生命周期

- SIP 侧仅 PCMA/PCMU、8 kHz、单声道有符号 16 位 PCM、20 ms/160 个采样。
- 蜂窝侧支持 8 kHz/160 个采样和 16 kHz/320 个采样。SDK `codec=0/1` 分别对应 8/16 kHz；原共享缓冲 metadata 的 `rate=1/2` 也是 8/16 kHz，不能混用两个枚举。
- SDK 下行完整帧通知复制到自有队列；独立媒体任务完成转换并交给 VoIP。回调不调用 Lua、不等待网络。
- 上行通过 SDK 复制上传接口提交。媒体任务按单调时钟以 20 ms 节拍推进；错过周期时跳过过期语音，不突发补传，不依赖 I2S 节拍。
- 两方向队列最多六帧，积压丢最旧完整帧。SIP→CC 预缓冲三帧，欠载补静音并重新预缓冲。
- 16→8 kHz 采用相邻采样平均，8→16 kHz 采用相邻采样插值。
- CC session、媒体 phase 和 VoIP generation 防止上一通或旧媒体阶段的数据、事件进入新通话。

接通与媒体就绪分别判断。本阶段收到真实下行且上行提交成功后才发布 `AUDIO_START`；demo 接通后的默认媒体启动超时为 1500 ms。
`PLAY_STOP→SPEECH_START` 是媒体阶段转换，不直接视为整通挂断。真实蜂窝早期媒体优先于合成彩铃，模组本身不播放。
停止时关闭入口、串行结束访问并清空队列；SDK 上传副本等到真实完成通知才释放，超时记录故障而不强制回收。

## Demo 与验证

使用 [独立 PCM demo](../module/Air8000/demo/sip_cc_bridge_pcm/README.md)。demo 通过 `require` 使用 `script/libs` 中的公共 SIP 和网络库，不保留库副本；烧录时按 demo 说明从公共目录直接添加依赖文件。纯 PCM 媒体控制由 `pcm_sip.lua` 提供，不加载通用 `exsip.lua`。

开发阶段的主机测试覆盖 PCM 队列与采样率转换、完整平台后端、CC 分发、VoIP 帧接口，以及 PCMA/PCMU × 蜂窝 8/16 kHz 四种组合。测试中的 SDK、网络和 RTOS 边界使用桩，不能替代实机验证。

完整 PC 非 GUI 构建应运行 `bsp/pc/build_windows_32bit_msvc.bat`，只有输出 `Build completed successfully` 才能判为通过。
主机测试不等同于完整固件构建或实机音频验收。实机步骤及日志要求见 demo README。
