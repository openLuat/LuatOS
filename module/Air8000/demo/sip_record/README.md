# Air8000 SIP 双向本地录音真机 demo

本示例基于 `module/Air8000/demo/sip` 的 4G、ES8311 和 SIP 使用方式，专门用于验证普通 SIP 通话的双向 WAV 录音。录音文件为 8 kHz、16-bit、双声道 WAV：左声道是本地上行，右声道是远端下行。

## 准备

1. 使用带 `voip.recordStart`、`voip.recordStop`、`voip.recordStatus` 的 Air8000 1号或13号固件。
2. 在 Air8000 V2.0 开发板插入 FAT/FAT32 TF 卡。默认使用 SPI1、CS=GPIO20；挂载失败时 demo 不会自动格式化卡。
3. 将 `config.lua.template` 复制为 `config.lua`，填写 SIP 服务器、账号、密码和 `dial_target`。不要提交包含真实凭据的 `config.lua`。
4. 用 LuaTools 将本目录作为项目目录下载到设备。

默认自动录音目录为 `/sd/record`，单次最长7200秒。TF 卡异常只会令录音失败，不会阻止 SIP 注册或主动挂断通话。

demo 会直接调用 `voip.recordStart()` 管理自动录音，不依赖固件内置 `exsip.lua` 是否已经包含自动录音逻辑；如果新版 `exsip` 已经先启动录音，demo 会检测当前状态并跳过，避免重复录制。

## 按键

- SIP 就绪且无通话：按 BOOT 键拨打 `dial_target`。
- 来电：按 BOOT 键接听。
- 通话中：按 BOOT 键切换录音。自动录音默认已启动，因此第一次按下会停止，第二次按下会以 `manual_*.wav` 重新开始。
- 通话中或来电时：按 POWERKEY 挂断。

## 验证日志和文件

`sip_record.record` 日志会报告 `started`、`stopped` 或 `error`，并打印路径、原因、字节数、时长和丢帧数。`sip_record.status` 每5秒打印一次队列与丢帧统计。

接通后应先看到 `自动录音启动请求成功 /sd/record/sip_*.wav`，随后看到 `sip_record.record started`。如果状态持续显示 `idle`，请保留从“录音配置”到挂断后的完整日志。

正常挂断后等待 `stopped` 日志，再拔卡读取 WAV。正常 TF 卡下应满足：

- `dropped=0`；
- 左声道可听到本机麦克风声音；
- 右声道可听到远端声音；
- 文件时长与接通后的通话时长基本一致。

可将 `record.max_seconds` 临时改为60，验证录音到时停止但 SIP 通话继续。通话中拔卡可验证 `write_failed`，通话不应中断。
