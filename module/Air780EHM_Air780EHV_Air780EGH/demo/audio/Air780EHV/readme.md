## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统并启动各个音频功能任务；

2、play_file.lua：音频文件播放功能模块，演示MP3、WAV、AMR格式音频文件的播放；

3、play_tts.lua：文字转语音功能模块，演示TTS语音合成功能；

4、play_stream.lua：流式音频播放功能模块，演示PCM格式音频的流式播放；

5、record_amr_file.lua：录音到文件功能模块，演示AMR格式音频录制；

6、record_pcm_file.lua：流式录音到文件功能模块，演示PCM格式音频录制；

7、http_download_play.lua：HTTP下载音频文件播放功能模块，支持MP3/AMR/PCM格式，自动识别格式，支持SD卡存储，文件大于200KB时（可自行调整）必须使用SD卡；

8、http_stream_play.lua：HTTP流式边下边播功能模块，支持PCM/AMR/MP3/WAV格式，自动识别格式，使用新音频框架；

9、sample-6s.mp3/10.amr：用于测试本地MP3和AMR文件播放的示例音频文件；

10、test.pcm：用于测试PCM流式播放的示例音频文件；

**注意:目前不支持录音和放音同时进行**

## 常量的介绍

1、exaudio.PLAY_DONE：当播放音频结束时，会在回调函数返回播放完成的时间

2、exaudio.RECORD_DONE：当录音结束时，会在回调函数返回播放完成的时间

3、exaudio.AMR_NB：仅录音时有用，表示使用AMR_NB方式录音

4、exaudio.AMR_WB：仅录音时有用，表示使用AMR_WB方式录音

5、exaudio.PCM_8000/exaudio.PCM_16000/exaudio.PCM_24000/exaudio.PCM_32000：仅录音时有用，表示使用8000/16000/24000/32000/秒的速度对音频进行采样

## 演示功能概述

### 1、音频文件播放功能（play_file.lua）

- 自动播放sample-6s.mp3音乐
- 支持MP3、WAV、AMR格式音频文件播放
- 通过powerkey按键进行音频切换（MP3↔AMR）
- 通过boot按键停止音频播放

### 2、文字转语音功能（play_tts.lua）

- 播放TTS语音合成内容
- 通过powerkey按键进行TTS音色切换
- 通过boot按键停止TTS播放
- 仅支持中文TTS

### 3、流式音频播放功能（play_stream.lua）

- 使用test.pcm模拟音频来源进行流式播放
- 通过流式传输不断填入播放的音频数据
- 通过powerkey按键进行音量减小
- 通过boot按键进行音量增加
- 仅支持PCM格式音频

### 4、录音到文件功能 - AMR格式（record_amr_file.lua）

- 录音到文件（AMR格式），默认保存到/sd/record.amr
- 通过powerkey/boot按键开始或停止录音/播放
- 支持5秒录音时长，可提前结束
- 录音完成后自动播放录音文件

### 5、流式录音到文件功能 - PCM格式（record_pcm_file.lua）

- 录音到文件（PCM格式），默认保存到/sd/record.pcm
- 通过powerkey/boot按键开始或停止录音/播放
- 支持流式录音和播放
- 支持16kHz采样率、16位采样深度、有符号PCM数据

### 6、HTTP流式边下边播功能（http_stream_play.lua）

- 使用httpplus进行HTTP下载，边下边播
- 支持PCM/AMR/MP3/WAV格式的HTTP流式播放
- PCM格式默认16kHz、16位、有符号、单声道
- AMR/MP3/WAV格式会自动解析文件头获取真实采样率
- 使用新音频框架，固件需要V2046及以上的13/113号固件才能播放

## 演示硬件环境

1、Air780EHV核心板+AirAUDIO_1000配件板+喇叭

![alt text](https://docs.openLuat.com/cdn/image/Air780EHV+Airaudio1000.jpg)

Air780EHV核心板和AirAudio_1000 配件板的硬件接线方式为:

| Air780EHV核心板 | AirAUDIO_1000配件板 |
| ---------------| -----------------   |
| 3/MIC+         |     MIC+            |
| 4/MIC-         |     MIC-            |
| 5/SPK+         |     SPK+            |
| 6/SPK-         |     SPK-            |
| 19/GPIO22      |     PA_EN           |
| VBAT           |     VCC             |
| GND            |     GND             |

2、TYPE-C USB数据线一根

- Air780EHV核心板通过 TYPE-C USB 口供电；

- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)

2、Air780EHV V2016版本固件，选择支持TTS功能的固件。不同版本区别参考[Air780EHV LuatOS固件版本](https://docs.openluat.com/air780ehv/luatos/firmware/version/)。

3、 luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS_demo_v2_temp/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/audio/Air780EHV)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air780EHV核心板](https://docs.openluat.com/air780ehv/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air780EHV核心板中。

4、[合宙 LuatIO 工具(GPIO 复用初始化配置)使用说明](https://docs.openluat.com/air780epm/common/luatio/)

5、 lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

## 演示核心步骤

在main.lua中，可以根据需要启用或禁用特定的音频功能任务：

- 通过注释或取消注释相应的require语句来控制功能模块的加载
- 每个功能模块作为独立的任务运行，可以单独测试或组合测试

### 目录结构说明

```lua
├── main.lua              # 主程序入口，负责初始化音频系统并启动各个音频功能任务
├── play_file.lua         # 音频文件播放功能模块，支持MP3、WAV、AMR格式
├── play_tts.lua          # 文字转语音功能模块，支持中文TTS语音合成
├── play_stream.lua       # 流式音频播放功能模块，支持PCM格式流式播放
├── record_amr_file.lua   # 录音到文件功能模块，支持AMR格式录音
├── record_pcm_file.lua   # 流式录音到文件功能模块，支持PCM格式录音
├── http_download_play.lua # HTTP下载音频文件播放功能模块，支持MP3/AMR/PCM格式，自动识别格式，支持SD卡存储，文件大于200KB时（可自行调整）必须使用SD卡
├── http_stream_play.lua   # HTTP流式边下边播功能模块，支持PCM/AMR/MP3/WAV格式，自动识别格式，使用新音频框架
├── sample-6s.mp3         # 示例音频文件，用于播放测试
├── test.pcm              # 示例PCM音频文件，用于流式播放测试
└── 10.amr                # 示例AMR音频文件，用于播放测试
```

### 1、音频文件播放功能（play_file.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，确保保留`require "play_file"`这一行
4. 将代码下载到开发板并运行
5. **演示效果**：自动播放sample-6s.mp3音乐，通过powerkey按键进行音频切换（MP3↔AMR），通过boot按键停止音频播放

**运行结果示例：**

```lua
I/user.开始播放音频文件
I/user.播放完成 true

I/user.切换播放
E/user.是否完成播放 true
I/user.播放完成 true

I/user.停止播放
```

### 2、文字转语音功能（play_tts.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，确保保留`require "play_tts"`这一行
4. 将代码下载到开发板并运行
5. **演示效果**：播放TTS语音合成内容，通过powerkey按键进行TTS音色切换，通过boot按键停止TTS播放

**运行结果示例：**

```lua
I/user.开始播放TTS
I/user.切换播放

E/user.是否完成播放 true
I/user.播放完成 true

I/user.停止播放
```

### 3、流式音频播放功能（play_stream.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，确保保留`require "play_stream"`这一行
4. 将代码下载到开发板并运行
5. **演示效果**：使用test.pcm模拟音频来源进行流式播放，通过powerkey按键进行音量减小，通过boot按键进行音量增加

**运行结果示例：**

```lua
I/user.开始流式获取音频数据
I/user.开始流式播报

I/user.减小音量55
I/user.增大音量75

I/user.播放状态 true
I/user.播放完成 true
```

### 4、录音到文件功能 - AMR格式（record_amr_file.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，确保保留`require "record_amr_file"`这一行
4. 将代码下载到开发板并运行
5. **演示效果**：录音到文件（AMR格式），通过powerkey/boot按键开始或停止录音/播放，支持5秒录音时长，可提前结束

**运行结果示例：**

```lua
I/user.音频系统初始化
I/user.exaudio.setup 声道数已设置为:1(1=单声道,2=双声道)
I/user.音量设置 播放:60 录音:60
I/user.无录音文件
I/user.按键功能说明：
I/user.1. Power键: 开始/停止录音，停止播放
I/user.2. Boot键: 开始/停止播放，停止录音
I/user.3. 录音时长: 5秒，可提前结束
I/user.4. 录音完成后自动播放

# 空闲时按Power键开始录音
I/user.按下POWERKEY键
I/user.空闲状态，开始录音
I/user.开始录音 时长:5秒
I/user.录音已开始，按任意键可提前结束
I/user.录音中... 1 秒
I/user.录音中... 2 秒
I/user.录音中... 3 秒
I/user.录音中... 4 秒
I/user.录音中... 5 秒
I/user.提前停止录音 已录制: 5 秒
I/user.录音时长已达5秒，自动停止录音
I/user.录音完成 时长: 0 秒 大小: 3931 字节
I/user.播放录音文件 大小: 3931 字节
I/user.播放已开始
I/user.播放完成

# 空闲时按Boot键播放录音
I/user.按下BOOT键
I/user.空闲状态，播放录音
I/user.播放录音文件 大小: 3931 字节
I/user.播放已开始
I/user.播放完成

# 播放中按Power键停止播放
I/user.按下POWERKEY键
I/user.正在播放中，停止播放
I/user.停止播放
I/user.播放完成

# 再次按Power键开始录音并提前停止
I/user.按下POWERKEY键
I/user.空闲状态，开始录音
I/user.开始录音 时长:5秒
I/user.录音已开始，按任意键可提前结束
I/user.录音中... 1 秒
I/user.录音中... 2 秒
I/user.按下POWERKEY键
I/user.正在录音中，停止录音
I/user.提前停止录音 已录制: 2 秒
I/user.录音完成 时长: 0 秒 大小: 1999 字节
I/user.播放录音文件 大小: 1999 字节
I/user.播放已开始
I/user.播放完成
```

### 5、流式录音到文件功能 - PCM格式（record_pcm_file.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，确保保留`require "record_pcm_file"`这一行
4. 将代码下载到开发板并运行
5. **演示效果**：录音到文件（PCM格式），通过powerkey/boot按键开始或停止录音/播放，支持5秒录音时长，可提前结束

**运行结果示例：**

```lua
I/user.音频系统初始化
I/user.exaudio.setup 声道数已设置为:1(1=单声道,2=双声道)
I/user.音量设置 播放:60 录音:60
I/user.无录音文件
I/user.按键功能说明：
I/user.1. Power键: 开始/停止录音，停止播放
I/user.2. Boot键: 开始/停止播放，停止录音
I/user.3. 录音时长: 5秒，可提前结束
I/user.4. 录音完成后自动播放

# 空闲时按Power键开始录音
I/user.按下POWERKEY键
I/user.空闲状态，开始录音
I/user.开始录音 时长:5秒
I/user.录音已开始，按任意键可提前结束
I/user.录音中... 1 秒
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 29.00 ms, 写入速度: 323.28 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 21.00 ms, 写入速度: 446.43 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 21.00 ms, 写入速度: 446.43 KB/s
I/user.录音中... 2 秒
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 27.00 ms, 写入速度: 347.22 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 21.00 ms, 写入速度: 446.43 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 21.00 ms, 写入速度: 446.43 KB/s
I/user.录音中... 3 秒
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 22.00 ms, 写入速度: 426.14 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 29.00 ms, 写入速度: 323.28 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 21.00 ms, 写入速度: 446.43 KB/s
I/user.录音中... 4 秒
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 29.00 ms, 写入速度: 323.28 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 23.00 ms, 写入速度: 407.61 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.录音中... 5 秒
I/user.停止录音 已录制: 5 秒
I/user.exaudio.record_stop 处理缓冲区1的剩余数据: 6400字节
I/user.SD卡写入统计 数据大小: 6400 字节, 写入耗时: 15.00 ms, 写入速度: 416.67 KB/s
I/user.exaudio.record_stop 处理缓冲区2的剩余数据: 9600字节
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 27.00 ms, 写入速度: 347.22 KB/s
I/user.录音时长已达5秒，自动停止录音
I/user.录音完成 大小: 169600 字节
I/user.按下BOOT键开始播放录音文件
I/user.录音完成 大小: 169600 字节
I/user.按下BOOT键开始播放录音文件

# 空闲时按Boot键播放录音
I/user.按下BOOT键
I/user.空闲状态，播放录音
I/user.流式播放录音文件 大小: 169600 字节
I/user.流式播放已开始
I/user.开始流式读取录音数据
I/user.流式播放缓冲区大小 1600
I/user.mem.lua 4194296 134496 151520
I/user.mem.sys 3200560 475860 485708
I/user.流式数据读取完成
I/user.mem.lua 4194296 222872 258424
I/user.mem.sys 3200560 478380 485708
I/user.播放完成
```

### 6、HTTP下载音频文件播放功能（http_download_play.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，确保保留`require "http_download_play"`这一行
4. 修改`http_download_play.lua`中的`AUDIO_URL`变量，设置为要下载的音频文件URL（支持PCM/MP3/AMR格式，自动识别）
5. 将代码下载到开发板并运行
6. **演示效果**：通过HTTP下载音频文件并播放，自动识别音频格式，支持SD卡存储，文件大于200KB时必须使用SD卡

**运行结果示例：**

```lua
I/user.http_pcm_stream_play 音频系统初始化
I/user.http_pcm_stream_play 开始挂载SD卡
I/user.http_pcm_stream_play SD卡挂载成功 挂载路径: /sd
I/user.http_pcm_stream_play SD卡空间信息 {"free_sectors":31106560,"total_kb":15554016,"free_kb":15553280,"total_sectors":31108032}
I/user.http_pcm_stream_play 等待网络就绪...
I/user.http_pcm_stream_play 网络已就绪
I/user.http_pcm_stream_play 音量设置: 70
I/user.http_pcm_stream_play 音频硬件初始化成功
I/user.http_pcm_stream_play 存储路径: /sd (SD卡)
I/user.http_pcm_stream_play 按键功能说明：
I/user.http_pcm_stream_play 1. Power键: 开始HTTP下载并播放音频
I/user.http_pcm_stream_play 2. Boot键: 停止播放
I/user.http_pcm_stream_play 3. 音频URL: http://airtest.openluat.com:2900/download/10.amr
I/user.http_pcm_stream_play 4. 音频格式: amr

# 空闲时按Power键开始下载并播放
I/user.http_pcm_stream_play 按下POWERKEY键
I/user.http_pcm_stream_play 开始HTTP下载并播放 amr
I/user.http_pcm_stream_play 启动HTTP下载播放任务
I/user.http_pcm_stream_play 音频格式: amr URL: http://airtest.openluat.com:2900/download/10.amr
I/user.http_pcm_stream_play 临时文件路径: /sd/tmp_http_audio.amr (SD卡)
I/user.http_pcm_stream_play 获取文件大小...
I/user.http_pcm_stream_play 下载进度: 0 / 678
I/user.http_pcm_stream_play 下载进度: 678 / 678
I/user.http_pcm_stream_play HTTP下载完成，文件大小: 678
I/user.http_pcm_stream_play AMR 使用文件播放
I/user.http_pcm_stream_play 播放已启动
I/user.http_pcm_stream_play 播放完成
I/user.http_pcm_stream_play 临时文件已删除
```

**注意事项：**
- 音频格式根据URL后缀自动识别（.pcm/.mp3/.amr）
- PCM格式使用流式播放，MP3/AMR格式使用文件播放
- 文件大于200KB且SD卡未挂载时会提示"文件过大，请用SD卡下载"
- 播放完成后自动删除临时文件

### 7、HTTP流式边下边播功能（http_stream_play.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，确保保留`require "http_stream_play"`这一行
4. 修改`http_stream_play.lua`中的`AUDIO_URL`变量，设置为要播放的音频文件URL（支持PCM/AMR/MP3/WAV格式，自动识别）
5. 将代码下载到开发板并运行
6. **演示效果**：通过HTTP边下载边播放音频，自动识别音频格式，AMR/MP3/WAV格式自动解析文件头获取真实采样率

**运行结果示例：**

```lua
[2026-07-03 15:06:32.060][000000000.000] main_entry 708:SDK base line V017_p001.026
[2026-07-03 15:06:32.061][000000000.007] am_service_init 1372:Air780EHV_A11
[2026-07-03 15:06:32.062][000000000.008] am_get_chip_type 868:6bef6,1b,64,87,10,EC718HM
[2026-07-03 15:06:32.063][000000000.008] am_service_init 1380:APB MP 102400000
[2026-07-03 15:06:32.063][000000000.080] bsp_user_init_io 466:io volt 3.3v 21
[2026-07-03 15:06:32.064][000000000.081] BSP_CustomInit 558:hardfault mode init 4
[2026-07-03 15:06:32.064][000000000.081] Uart_ChangeBR 1461:uart0, 6000000 6028985 26000000 69
[2026-07-03 15:06:32.065][000000000.103] I/pm poweron: Power/Reset
[2026-07-03 15:06:32.066][000000000.103] luat_pm_get_poweron_reason 336:ap 2, cp 2
[2026-07-03 15:06:32.067][000000000.103] I/pm poweron reason: 0 0 5
[2026-07-03 15:06:32.067][000000000.229] self_info 125:model Air780EHV_A11 imei 862288081583054 dbversion 0x260d5b01
[2026-07-03 15:06:32.068][000000000.229] self_info 127:firmware[113] VOLTE fs 512kbyte script 512kbyte
[2026-07-03 15:06:32.068][000000000.231] I/main LuatOS@Air780EHV base 26.04 bsp V2045 64bit
[2026-07-03 15:06:32.074][000000000.231] I/main ROM Build: Jun 30 2026 10:03:13
[2026-07-03 15:06:32.076][000000000.233] W/pins /luadb/pins_air780ehv.json not exist!!
[2026-07-03 15:06:32.078][000000000.236] D/main loadlibs luavm 4194296 18736 18736
[2026-07-03 15:06:32.080][000000000.236] D/main loadlibs sys   3157288 195200 195240
[2026-07-03 15:06:32.081][000000000.236] D/main loadlibs psram 3157288 195200 195240
[2026-07-03 15:06:32.083][000000000.256] I/user.main audio 001.999.000
[2026-07-03 15:06:32.084][000000000.286] D/user.exaudio version -> 202607021200
[2026-07-03 15:06:32.087][000000000.304] I/user.network 等待4G网络就绪...
[2026-07-03 15:06:34.399][000000003.038] I/mobile sim0 sms ready
[2026-07-03 15:06:34.401][000000003.039] D/mobile cid1, state0
[2026-07-03 15:06:34.402][000000003.039] D/mobile bearer act 0, result 0
[2026-07-03 15:06:34.404][000000003.040] D/mobile NETIF_LINK_ON -> IP_READY
[2026-07-03 15:06:34.423][000000003.089] D/mobile TIME_SYNC 0 tm 1783062395
[2026-07-03 15:06:34.639][000000003.304] I/user.network 4G网络已就绪
[2026-07-03 15:06:36.632][000000005.306] I/user.exaudio.setup audio_mode=new，切换到新音频框架
[2026-07-03 15:06:36.634][000000005.306] I/user.exaudio.setup 当前使用新音频框架
[2026-07-03 15:06:36.636][000000005.307] I/user.exaudio.setup audio_v2 ES8311模式初始化
[2026-07-03 15:06:36.637][000000005.307] I2C_MasterSetup 426:I2C0, Total 260 HCNT 113 LCNT 136
[2026-07-03 15:06:36.638][000000005.308] I/user.exaudio.setup 默认驱动已设置, probe_id: 65537
[2026-07-03 15:06:36.663][000000005.338] I/user.es8311 init voltage 0
[2026-07-03 15:06:36.695][000000005.365] I/user.exaudio.setup ES8311初始化完成
[2026-07-03 15:06:36.697][000000005.366] I/user.exaudio.setup audio_v2初始化完成
[2026-07-03 15:06:36.698][000000005.366] I/user.stream ========== 开始HTTP下载+播放 ==========
[2026-07-03 15:06:36.699][000000005.366] I/user.stream URL: https://appstoreoss.luatos.com/iot-apps/res/100617/sample-6s.mp3
[2026-07-03 15:06:36.701][000000005.371] D/socket connect to appstoreoss.luatos.com,443
[2026-07-03 15:06:36.710][000000005.372] dns_run 676:appstoreoss.luatos.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-07-03 15:06:36.803][000000005.467] dns_run 693:dns all done ,now stop
[2026-07-03 15:06:37.659][000000006.327] I/user.stream 头解析 ok: true sr: 0 data_start: 47
[2026-07-03 15:06:37.661][000000006.327] I/user.stream 头解析需继续缓冲
[2026-07-03 15:06:37.674][000000006.346] I/user.stream 头解析 ok: true sr: 44100 data_start: 47
[2026-07-03 15:06:37.676][000000006.347] I/user.exaudio 调用stream: cid= 5 sr= 44100 bits= 16 ch= 1 sig= true pri= 0
[2026-07-03 15:06:37.678][000000006.349] D/audio_core driver 0x10001 create play fifo
[2026-07-03 15:06:37.679][000000006.351] I/user.exaudio stream返回: ok= true req_id= 0
[2026-07-03 15:06:37.680][000000006.352] I/user.exaudio 流式播放启动成功, request_index: 0 采样率: 44100 codec_id: 5
[2026-07-03 15:06:37.682][000000006.352] I/user.stream 流启动成功, 采样率: 44100 声道: 1
[2026-07-03 15:06:37.690][000000006.354] I/user.stream 写入首块纯音频: 7685 字节
[2026-07-03 15:06:37.704][000000006.369] I/user.exaudio 播放开始 0
[2026-07-03 15:06:37.766][000000006.442] W/audio_core print from irq 0 0 8000
[2026-07-03 15:06:38.032][000000006.704] I/user.stat_http chunks: 5 downloaded: 20020 elapsed_ms: 0 speed: 0 B/s
[2026-07-03 15:06:38.699][000000007.368] I/user.stat_http chunks: 10 downloaded: 40500 elapsed_ms: 1 speed: 40500000 B/s
[2026-07-03 15:06:38.867][000000007.544] I/user.httpplus 服务器已完成响应
[2026-07-03 15:06:38.882][000000007.546] I/user.stream HTTP下载完成，总字节: 51635
[2026-07-03 15:06:38.884][000000007.547] I/user.stat_summary http_total: 51635 http_chunks: 13 http_time_ms: 1 http_speed: 51635000 B/s
[2026-07-03 15:06:44.482][000000013.154] I/user.exaudio 播放完毕 0
[2026-07-03 15:06:44.486][000000013.155] I/user.播放完成
[2026-07-03 15:06:44.514][000000013.182] I/user.stat_summary ========== 播放完全结束 ==========
[2026-07-03 15:06:44.575][000000013.245] W/audio_core print from irq 2 0 0
```

**注意事项：**
- 音频格式根据URL后缀自动识别（.pcm/.mp3/.amr/.wav）
- PCM格式使用默认参数（16kHz、16位、有符号、单声道）启动流式播放
- AMR/MP3/WAV格式会先缓冲并解析文件头，获取真实采样率后再启动播放
- 本功能依赖新音频框架，需使用V2046及以上的13/113号固件

## **异常处理**

1、使用合宙开发板时，如出现I2C/SPI通讯异常的情况，请使用exmux扩展库的setup函数初始化外设分组开关状态，使用open函数打开外设分组，并跳转至exmux扩展库介绍文档中了解I2C/SPI总线上拉问题；https://docs.openluat.com/osapi/ext/exmux/

2、使用自己制作的板子时，如出现I2C通讯异常的情况，请根据各型号文档中”硬件设计资料“的I2C和SPI板块”常见的坑“栏目中的经验，检查板子上的I2C/SPI总线是正常上拉；也可使用exmux库来管理i2c和spi总线的上拉状态，详情请参考exmux扩展库介绍文档。