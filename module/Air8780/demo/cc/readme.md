# 语音通话（Air8780V / Air780EHV）

本目录 = `../Air780EHV/` 原 demo + 音频框架自适应，功能场景与事件流程完全不变。

## 板级参数（已写死在 audio_drv.lua）

| 项 | 值 | 依据 |
|---|---|---|
| Codec | 模组内置 ES8311，I2C0，地址 0x18 | 原理图 Sheet1 |
| PA 使能 | **GPIO22**（PIN19，网络标号 `PA_EN` → AW8733 的 SHDN） | 原理图 Sheet1/Sheet6 |
| Codec 电源 | **GPIO20** | 原理图 Sheet1 PIN102 |
| Codec 电平 | 3.3V（`codec_voltage = 1`） | 同 |
| MIC / SPK | PIN3/4、PIN5/6 | 原理图 Sheet1 |
| 录音存储 | **内部 flash** `/record_call.pcm`（8780V 板上无 TF 卡座） | 全 7 页无卡座电路 |

8780 系列只有 **V**（板载 Air780EHV）内部集成 ES8311，P/H/G/S/U/N 板载模组无 codec，
板上也无外挂 8311，做不了本地通话音频。

## 音频框架（new / old）

固件是否编入 `audio_v2`，决定用哪套音频框架：

| 固件 | `audio_v2` | auto | new | old |
|---|---|---|---|---|
| 1 号 | 无 | **正常** | 完全没声音 | 正常 |
| 13 号 | 有 | 板子没声音，手机能听到 | **正常** | 板子没声音，手机能听到 |

`main.lua` 里自动判定，不用手改：

```lua
local FW_NAME = (rtos.firmware and rtos.firmware()) or rtos.version()
local HAS_AUDIO_V2 = audio_v2 ~= nil and audio_v2.input ~= nil and audio_v2.config ~= nil
_G.AUDIO_MODE = _G.AUDIO_MODE or (HAS_AUDIO_V2 and "new" or "old")
```

- `rtos.firmware()` 只能拿到 `LuatOS-SoC_V2056_Air780EHV`，**拿不到尾部的 13/113 号**，
  所以判据是直接探测 `audio_v2` 库，不是解析固件号。
- 780EHV 上 `audio_mode = "auto"` 恒等于 `old`（exaudio 内部 `PREFER_AUDIO_V2 = false`），
  所以这里只产出 `new` / `old` 两种，不写 auto。
- 个别固件编了库但播不出声时，在 `main.lua` 里加一行 `_G.AUDIO_MODE = "old"` 强制旧框架。
- `audio_drv` 里再兜一层：new 初始化失败会自动退回 old 重试一次。

开机日志：

```
I/user.main 固件 LuatOS-SoC_V2056_Air780EHV audio_v2 支持 音频框架 new
I/user.audio_drv 初始化音频 i2c 0 pa_ctrl 22 dac_ctrl 20 框架 new
```

## 场景选择

`main.lua` 里默认 `require "cc_app"`，其余三个注释掉：

| 模块 | 场景 | 备注 |
|---|---|---|
| `cc_app` | 基础通话 | 默认，`ACTIVE_SCENARIO` 选 1~4 |
| `cc_tts_app` | TTS 循环播放 + 接听 | 需要 new 框架 |
| `cc_record_save` | 通话录音 | 写内部 flash |
| `play_audio_during_cc` | 通话中放音给对方 | 需要 new 框架 |

## 录音容量（重要）

内部 flash 的 `lfs` 分区实测只有 **768KB**：

| 通话质量 | 采样率 | 约合码率 | 最长可录 |
|---|---|---|---|
| 2（高） | 16KHz | 31KB/s | **约 12 秒** |
| 1（低） | 8KHz | 15.6KB/s | **约 25 秒** |

`FLASH_MAX_RECORD_KB = 400` 会在写到 400KB 时自动停并打日志，避免写满分区影响脚本存储。
开录时还会打「预计最长可录 N 秒」，不是 bug。

## 烧录

1. 模组选 **Air780EHV**，固件用 **13 / 113 号**（带 VoLTE）。
   场景四必须 13/113 号且 V2046 以上。
2. 脚本里要带 `libs/exaudio.lua`，否则 `require "exaudio"` 为 nil。
3. 场景二 / 场景四要把 `test_16k.mp3` 一起加进 luadb（`/luadb/test_16k.mp3`）。
4. `pins_air780ehv.json` 可选，放进 luadb 能消掉开机那句
   `W/pins ... not exist!!`，不放不影响功能。

## 排查

| 现象 | 原因 |
|---|---|
| 通话刚接通就重启 | 大概率供电。看 `pm poweron reason`，`0 0 0` 是掉电/上电，`0 0 3` 是软复位。Cat.1 发射峰值 2A 叠加功放推喇叭，VBAT 跌落就复位。先用 ≥2A 稳压电源、VBAT 就近加 470~1000µF，或把 `SPEAKER_VOL` 降到 45 验证 |
| 卡在 `等待CC就绪` | `CC_IND` 的 `READY` 没到，看 CSQ 与 SIM 状态。开机头 2 秒的 `NORDY` 是正常早期事件 |
| `i2c_failed ... 错误码-6` 一条 | `es8311.init()` 第一笔 0x44 写失败、紧跟第二笔成功，驱动自带容错，不影响功能 |
| 喇叭没声音但 setup 成功 | 看日志里打印的 `音频框架` 是不是 new；1 号固件要用 old |
| `attempt to index a nil value (global 'cc')` | 烧的是数据固件，换 13/113 号 |
| 录音文件 0 字节 | 看「内部 flash 剩余 N KB」和是否已到 400KB 上限 |
