# CC/SIP 纯 PCM 桥接

该后端供无外置 codec 的 Air8000w 使用，媒体不经过 I2S、DAC、UART 音频或 Audio V2 音频请求。
固件继续保留 Audio V2，`cc.init(0)` 仍选择原音频后端。普通 SIP 的音频模式不会隐式切换 CC 后端。

## 配套仓库

需要配套以下仓库实现，不能只更新 Lua 或复制头文件：

| 仓库 | 配套实现 |
| --- | --- |
| `luatos-sdk-ec7xx` | 使用标准 SDK 的 HAL PCM 通知、语音编码及完成归还接口，不依赖定制 `soc_mobile_pcm_*` 实现 |
| `luatos-soc-2024` | `luat_cc_pcm_bridge_ec7xx.c`、通话事件分发和通话状态查询；启用 `LUAT_USE_CC_PCM_BRIDGE`，保留 `LUAT_USE_AUDIO_V2` |
| `LuatOS` | CC 初始化及接口分发、SoC 本地 PCM 上传适配器、PCM 队列/转换核心、VoIP 帧接口和独立 demo |
| `luatos-ext-components` | G729/G722 库；G729 真实丢帧恢复接口及安全的 ASMB 热点/只读系数放置 |

PCM 上传副本和生命周期由本地 `luat_cc_pcm_upload_*` 适配器管理，构建配置包装标准 SDK 的录音启动、停止和缓冲区归还函数。无需为本 demo 替换定制 SDK 库；固件必须集成上述 SoC、LuatOS 和 codec 实现。

在配套 SoC 仓库使用：

```powershell
python build_luatos_types.py Air8000 13
```

G729/G722 测试使用 Air8000 22 号配套固件（22/122 配置启用两套 codec），并重新编译包含上述 VoIP 帧边界适配的固件。构建配置变化时按 SoC 仓库要求全量重编。固件版本号不能代替能力检查。

G729 的 `inter_3l` 插值常量使用独立只读 RAM-code 子节 `.sect_platFARamcode_text.g729_inter_3l`，由压缩加载器恢复到 ASMB，避免每次插值都访问 Flash。EC7xx 的 `platFDataInAsmbInit` 会从链接时的 Flash Load 地址直接复制 `PLAT_FA_DATA`；压缩打包后该地址可能已成为填充区，因此这张常量表不能使用 `PLAT_FA_DATA` 标注。三个 `G729_HOT2` 函数继续放在 ASMB，grp1 压缩分组上限保持 96 KiB。

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

- SIP 侧支持 PCMA/PCMU/G729（8 kHz）及 G722（16 kHz），固定单声道有符号 16 位 PCM、20 ms。CC 帧交接统一为 8 kHz/160 个采样；G722 在 VoIP 边界完成 16→8 kHz 双采样平均和 8→16 kHz 连续插值，蜂窝通道不会因此变为全程宽带。
- 蜂窝侧支持 8 kHz/160 个采样和 16 kHz/320 个采样。SDK `codec=0/1` 分别对应 8/16 kHz；原共享缓冲 metadata 的 `rate=1/2` 也是 8/16 kHz，不能混用两个枚举。
- SDK 下行完整帧通知复制到自有队列；独立媒体任务完成转换并交给 VoIP。回调不调用 Lua、不等待网络。
- 上行通过 SDK 复制上传接口提交。媒体任务按单调时钟以 20 ms 节拍推进；错过周期时跳过过期语音，不突发补传，不依赖 I2S 节拍。
- 两方向队列最多六帧，积压丢最旧完整帧。SIP→CC 预缓冲三帧，欠载补静音并重新预缓冲。
- G729 在解码前拒绝重复/迟到 RTP；SSRC 变化时先重置解码器。缺失不超过十个 20 ms 包时，每包调用两次真实 10 ms 擦除帧解码并交接 PCM；更大的序号跳变建立新流，避免无界补帧。
- `voip.stats()` 的 `rx_decode_dropped`、`rx_concealed`、`rx_decoder_resets` 分别统计 G729 解码前拒绝、合成的 20 ms PCM 帧和状态重置；解码耗时统计包含这些丢帧恢复帧。
- 16→8 kHz 采用相邻采样平均，8→16 kHz 采用相邻采样插值。
- CC session、媒体 phase 和 VoIP generation 防止上一通或旧媒体阶段的数据、事件进入新通话。

接通与媒体就绪分别判断。本阶段收到真实下行且上行提交成功后才发布 `AUDIO_START`；demo 接通后的媒体启动超时由 `cc_audio_start_timeout_ms` 配置，提交的示例值为 3000 ms。
`PLAY_STOP→SPEECH_START` 是媒体阶段转换，不直接视为整通挂断。真实蜂窝早期媒体优先于合成彩铃，模组本身不播放。
停止时关闭入口、串行结束访问并清空队列；SDK 上传副本等到真实完成通知才释放，超时记录故障而不强制回收。

## Demo 与验证

使用 [独立 PCM demo](../module/Air8000/demo/sip_cc_bridge_pcm/README.md)。demo 通过 `require` 使用 `script/libs` 中的公共 SIP 和网络库，不保留库副本；烧录时按 demo 说明从公共目录直接添加依赖文件。纯 PCM 媒体控制由 `pcm_sip.lua` 提供，不加载通用 `exsip.lua`。

开发阶段的主机测试覆盖 PCM 队列与采样率转换、完整平台后端、CC 分发、VoIP 帧接口，以及 PCMA/PCMU × 蜂窝 8/16 kHz 四种组合。测试中的 SDK、网络和 RTOS 边界使用桩，不能替代实机验证。

`components/voip/tests/test_voip_g729_arm_image.py` 使用 Unicorn 与 pyelftools，加载明确指定的 ELF 中已解压的 RAM 段，再覆盖实际打包 AP 镜像并执行平台的真实 ASMB 初始化指令，检查插值表和 128 帧参考编解码输出。允许 Flash XIP 或只读 ASMB RAM-code 放置，拒绝可被直接复制覆盖的 ASMB RW 数据节。这样可以发现只加载 ELF、只做 PC 算法对拍会遗漏的打包后覆盖问题；该测试仍不能代替板上启动、听音和实时性能验收。

```powershell
python components/voip/tests/test_voip_g729_arm_image.py --elf ../luatos-soc-2024/project/luatos/out/luatos.elf --ap-image ../luatos-soc-2024/project/luatos/build/luatos/ap.bin
```

完整 PC 非 GUI 构建应运行 `bsp/pc/build_windows_32bit_msvc.bat`，只有输出 `Build completed successfully` 才能判为通过。
主机测试不等同于完整固件构建或实机音频验收。实机步骤及日志要求见 demo README。
