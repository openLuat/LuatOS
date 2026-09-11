# Air8101 Wi-Fi SIP 双向本地录音真机 demo

本示例基于 `module/Air8101/demo/sip` 的 Wi-Fi、内置 DAC/ADC 和 SIP 音频配置，并参考 `module/Air8101/demo/tf_card` 使用 SDIO 挂载 TF 卡。录音文件为 8 kHz、16-bit、双声道 WAV：左声道是 Air8101 本地上行，右声道是 SIP 远端下行。

## 硬件和固件

- 建议使用支持完整 SIP 音频能力的 Air8101B 核心板及 AirAUDIO_1000。
- TF 卡使用 AirMICROSD_1000：GPIO2=CLK、GPIO3=CMD、GPIO4=D0、GPIO6=CD，GPIO13控制供电。
- Wi-Fi 仅支持2.4GHz。
- 固件必须同时提供 SIP/VoIP、Audio V2、FATFS/SDIO，以及 `voip.recordStart`、`recordStop`、`recordStatus`。
- 录音每秒会刷新一次 TF 卡；固件中的 FATFS VFS 必须包含 `fflush -> f_sync` 实现。

## 配置与下载

1. 将 `config.lua.template` 复制为 `config.lua`。
2. 填写2.4GHz Wi-Fi、SIP账号和 `dial_target`；不要提交真实密码。
3. 用 LuaTools 将本目录全部文件下载到 Air8101。

本 Air8101 示例在 `config.lua.template` 中显式开启 AEC，配置为同步 Speex、降噪开启、AGC 关闭和 160 点（20ms）声学延迟。公共 `exsip` 默认不启用 AEC。真机先保持其它参数不变，依次比较：

- `aec=false`：无 AEC 基线。
- `aec=true, aec_mode="speex"`：依次试听 `aec_delay_samples=80/160/240/320`。
- 固定最佳延迟后改为 `aec_mode="bk"`，在相同音量和增益下与 Speex 对比。

BK 模式的 `aec_denoise=true` 使用 EC+NS+BPF（`flags=0x07`），DRC/CNI 默认关闭，避免收敛后的金属音和噪声泵动。通话统计中的 `ref_under/ref_over/resets` 在稳定通话时应保持为0，`max_us` 应小于20000。若 `mic_clip` 持续增加，逐级降低 `audio.mic_adc_dig_gain`（默认 `0x2d`，可试 `0x29`、`0x25`）；若仅 `out_clip` 增加，则是 AEC 输出失真。不要用 AGC 掩盖削顶。

默认挂载 `/sd`，自动创建 `/sd/record`。挂载失败不会自动格式化TF卡，而是自动创建内部文件系统目录 `/record`，录音文件保存为 `/record/sip_*.wav`，SIP仍会继续启动。

双声道PCM约占32KB/s。为避免写满内部文件系统，回退模式默认将单次录音限制为60秒；可在 `sd` 配置中增加 `fallback_max_seconds` 调整。内部文件不会自动删除，测试后请及时清理；TF卡正常时仍使用 `record.max_seconds` 配置。

## 按键

- GPIO37：SIP空闲时拨号、来电时接听、通话中切换录音。
- 原Air8101 SIP demo没有独立挂断键；默认由远端挂断。需要本机挂断时，在 `keys.hangup_gpio` 配置一个外接低电平按键。
- `auto_answer=true` 时来电会在 `delay_auto_answer` 秒后自动接听。

## 验证

接通后应依次看到：

```text
自动录音启动请求成功 /sd/record/sip_*.wav
sip_record.record started
sip_record.status recording ms=... bytes=... dropped=0
```

如果TF卡挂载失败，启动日志应显示：

```text
TF卡不可用，已回退到内部文件系统 ... dir=/record max_seconds=60
```

挂断后等待：

```text
sip_record.record stopped ... dropped=0
```

再拔卡。WAV普通播放器会同时播放双方声音；分离声道后，左声道应为Air8101麦克风的AEC后上行，右声道应为远端实际播放音频。若启动时提示没有录音API，需要先为Air8101固件移植并启用VoIP录音内核，Lua demo本身无法补足C层能力。
