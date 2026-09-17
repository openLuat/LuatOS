## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统并启动各个音频功能任务；

2、play_file.lua：播放音频文件，支持MP3/AMR/WAV格式，循环交替播放；

3、play_tts.lua：TTS文字转语音，循环播放5种音色；

4、play_stream.lua：流式音频播放功能模块，支持PCM/MP3/AMR/WAV格式音频的流式播放；

5、http_download_play: HTTP下载音频文件播放，联网后自动开始HTTP下载音频文件并播放，支持MP3/AMR/PCM格式

6、http_stream_play: HTTP音频流式播放（边下边播），支持PCM/AMR/MP3/WAV格式，自动连接WiFi

7、record_amr_file: 录音到文件（AMR格式），开机自动录音5秒，录音完成后自动播放

8、record_pcm_file: 录音到文件（PCM格式），开机自动录音5秒（16kHz/16bit/单声道），录音完成后自动播放

9、record_pcm_to_1103: 通过Air1103语音芯片录音与播放功能模块，演示PCM格式音频的流式录音与播放；

10、sample-6s.mp3、10.amr：用于测试本地音频文件播放；

11、test.pcm：用于测试PCM流式播放的示例音频文件；

**注意：目前不支持录音和放音同时进行**

## 演示功能概述

### 1、播放音频文件功能（play_file.lua）

- 播放MP3/AMR/WAV格式音频文件
- 初始化后播放sample-6s.mp3
- 然后循环交替播放10.amr和sample-6s.mp3，播放间隔3秒
- 使用内置DAC输出音频
- 需要固件版本>=V1024才可播放音频

### 2、TTS文字转语音功能（play_tts.lua）

- 初始化后播放默认TTS
- 然后循环播放5种音色的TTS，间隔3秒
- 音色包括：许久、许多、晓萍、唐老鸭、许宝宝
- 使用内置DAC输出音频
- 需要固件版本>=V1024才可播放音频

### 3、流式音频播放功能（play_stream.lua）

- 使用test.pcm模拟音频来源进行流式播放
- 支持PCM/MP3/AMR/WAV格式
- 通过流式传输不断填入播放的音频数据
- 需要固件版本>=V1024才可播放音频

### 4、HTTP下载音频文件播放功能（http_download_play.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "http_download_play"`，注释掉其他require
3. 将代码下载到开发板并运行
4. 按IO29键开始HTTP下载音频文件（MP3格式），下载完成后自动播放；按IO37键停止播放

### 5、HTTP音频流式播放功能（http_stream_play.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "http_stream_play"`，注释掉其他require
3. 将代码下载到开发板并运行
4. 自动连接WiFi，使用httpplus进行HTTP边下边播，支持PCM/AMR/MP3/WAV格式

### 6、录音到文件功能（record_amr_file.lua）

- 开机自动挂载SD卡（Air160X_V1.2开发板需先拉高SD_EN=GPIO56使能SD供电），挂载失败自动回退内部存储
- 自动开始5秒录音（AMR_NB格式），录音完成后自动播放录音文件
- 使用ES8311编解码芯片：录音走I2S2，播放走内置DAC

### 7、录音到文件功能（record_pcm_file.lua）

- 开机自动挂载SD卡（Air160X_V1.2开发板需先拉高SD_EN=GPIO56使能SD供电），挂载失败自动回退内部存储
- 自动开始5秒录音（PCM格式，16kHz/16bit/单声道），录音完成后自动播放录音文件
- 使用ES8311编解码芯片：录音走I2S2，播放走内置DAC

### 8、录音到文件功能 - 通过Air1103录音与播放（record_pcm_to_1103.lua）

- 通过UART1（波特率固定2M）连接合宙Air1103串口语音芯片，完成PCM流式录音与播放，Air1103无需I2C/PA/CODEC硬件初始化
- 开机自动运行：自动挂载TF卡（失败回退内部存储）→ 自动录音（默认5秒）→ 录音完成后自动流式播放
- PCM格式，16kHz采样率、16位采样深度、有符号、单声道
- 录音文件保存到TF卡（/sd/record.pcm），TF卡挂载失败时保存到内部存储（/record.pcm）
- 通过Air1103语音芯片输出音频（UART串口驱动，无需内置DAC）
- 注意：此功能Air1601和Air1602均支持

## 演示硬件环境

1、Air1602开发板+喇叭

2、TYPE-C USB数据线一根

- Air1602开发板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air1602/common/Luatools/)

2、Air1602 最新版本固件（>=V1024）。

3、 luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601_Air1602/demo/audio/Air1602)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air1602开发板](https://docs.openluat.com/air1602/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1602开发板中。

4、 lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

## 演示核心步骤

在main.lua中，可以根据需要启用或禁用特定的音频功能任务：

- 通过注释或取消注释相应的require语句来控制功能模块的加载
- 每个功能模块作为独立的任务运行，可以单独测试或组合测试

### 目录结构说明

```lua
├── main.lua              # 主程序入口，负责初始化音频系统并启动各个音频功能任务
├── play_file.lua         # 播放音频文件功能模块，支持MP3/AMR/WAV格式循环播放
├── play_tts.lua          # TTS文字转语音功能模块，循环播放5种音色
├── play_stream.lua       # 流式音频播放功能模块，支持PCM/MP3/AMR/WAV格式流式播放
├── http_download_play.lua # HTTP下载音频文件播放功能模块
├── http_stream_play.lua  # HTTP音频流式播放功能模块（边下边播）
├── record_amr_file.lua   # 录音到文件功能模块（AMR格式，开机自动录音5秒并自动播放）
├── record_pcm_file.lua   # 录音到文件功能模块（PCM格式，开机自动录音5秒并自动播放）
├── record_pcm_to_1103.lua # 录音到文件功能模块（PCM格式，通过Air1103语音芯片录音与播放）
├── sample-6s.mp3         # 示例音频文件，用于播放测试
├── 10.amr                # 示例AMR音频文件，用于播放测试
├── test.pcm              # 示例PCM音频文件，用于流式播放测试
└── readme.md             # 本文档
```

### 1、播放音频文件功能（play_file.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "play_file"`，注释其他require
3. 将代码下载到开发板并运行
4. **演示效果**：初始化后播放sample-6s.mp3，然后循环交替播放10.amr和sample-6s.mp3，间隔3秒

**运行结果示例：**

```lua
I/user.开始播放音频文件
I/user.exaudio.setup audio_v2 DAC模式初始化
...
I/user.播放完成 true
I/user.播放完成 true
...
```

### 2、TTS文字转语音功能（play_tts.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "play_tts"`，注释其他require
3. 将代码下载到开发板并运行
4. **演示效果**：初始化后播放默认TTS，然后循环播放5种音色的TTS，间隔3秒

**运行结果示例：**

```lua
I/user.开始播放TTS
I/user.exaudio.setup audio_v2 DAC模式初始化
...
I/user.播放完成 true
find software codec 4
...
tts decode sync end
```

### 3、流式音频播放功能（play_stream.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "play_stream"`，注释其他require
3. 将代码下载到开发板并运行
4. **演示效果**：读取test.pcm文件数据进行流式播放

**运行结果示例：**

```lua
I/user.开始流式获取音频数据
I/user.开始流式播报
I/user.exaudio.setup audio_v2 DAC模式初始化
...
I/user.播放完成 true
```

### 4、HTTP下载音频文件播放功能（http_download_play.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "http_download_play"`，注释掉其他require
3. 将代码下载到开发板并运行
4. **演示效果**：开机自动连接WiFi，连接成功后自动下载MP3音频文件并播放

**运行结果示例：**

```lua
I/user.http_download_play 音频系统初始化
I/user.http_download_play 开始挂载SD卡
I/user.wifi 开始连接WiFi luatos1234
I/user.wifi 等待IP获取...
I/user.wifi WiFi连接成功
I/user.exaudio.setup 当前使用新音频框架
I/user.exaudio.setup DAC模式 - 通道:0, 声道:1
I/user.exaudio.setup audio_v2 DAC模式初始化
I/user.exaudio.setup audio_v2初始化完成
I/user.http_download_play 音量设置: 70
I/user.http_download_play 音频硬件初始化成功
I/user.http_download_play WiFi已连接，开始下载并播放音频
I/user.http_download_play 音频URL: http://airtest.openluat.com:2900/download/sample-6s.mp3
I/user.http_download_play 音频格式: mp3
I/user.http_download_play 存储路径: / (内存)
I/user.http_download_play 音频格式: mp3 URL: http://airtest.openluat.com:2900/download/sample-6s.mp3
I/user.http_download_play 临时文件路径: /tmp_http_audio.mp3 (内存)
I/user.http_download_play 获取文件大小...
NOT SUPPORT HEAD
I/user.http_download_play 下载进度: 0 / 51635
I/user.http_download_play 下载进度: 1069 / 51635
...（中间省略多行下载进度日志）...
I/user.http_download_play 下载进度: 51635 / 51635
I/user.http_download_play HTTP下载完成，文件大小: 51635
I/user.http_download_play MP3 使用文件播放
I/user.http_download_play 播放已启动
I/user.exaudio 播放开始 0
...（播放中，等待约6秒）...
I/user.exaudio 播放完毕 0
I/user.http_download_play 播放完成
I/user.http_download_play 临时文件已删除
```

### 5、HTTP音频流式播放功能（http_stream_play.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "http_stream_play"`，注释掉其他require
3. 将代码下载到开发板并运行
4. **演示效果**：自动连接WiFi，使用httpplus进行HTTP边下边播，支持PCM/AMR/MP3/WAV格式

**运行结果示例：**

```lua
I/user.wifi 开始连接WiFi luatos1234
I/user.WiFi名称: luatos1234
I/user.wifi 等待IP获取...
I/user.wifi WiFi连接成功
I/user.exaudio.setup 当前使用新音频框架
I/user.exaudio.setup DAC模式 - 通道:0, 声道:1
I/user.exaudio.setup audio_v2 DAC模式初始化
I/user.exaudio.setup audio_v2初始化完成
I/user.stream ========== 开始HTTP下载+播放 ==========
I/user.stream URL: https://appstoreoss.luatos.com/iot-apps/res/100617/sample-6s.mp3
I/user.parse_audio_info get_play_info result: true sample_rate: 0 next_pos: 47 need_len: 1792
I/user.parse_audio_info buffer mode, sample_rate is 0 need more data, next_pos: 47 need_len: 1792
I/user.stream 头解析需继续缓冲
I/user.parse_audio_info get_play_info result: true sample_rate: 44100 next_pos: 47 need_len: 0
I/user.exaudio 调用stream: cid= 5 sr= 44100 bits= 16 ch= 1 sig= true pri= 0
I/user.exaudio stream返回: ok= true req_id= 0
I/user.exaudio 流式播放启动成功, request_index: 0 采样率: 44100 codec_id: 5
I/user.stream 流启动成功, 采样率: 44100 声道: 1
I/user.stream 写入首块纯音频: 7685 字节
I/user.exaudio 播放开始 0
...（播放中，HTTP边下边播，约6秒后播放完毕）...
I/user.httpplus 服务器已完成响应
I/user.stream HTTP下载完成，总字节: 51635
I/user.stat_summary http_total: 51635 http_chunks: 13 http_time_ms: 1 http_speed: 51635000 B/s
I/user.exaudio 播放完毕 0
I/user.播放完成
I/user.stat_summary ========== 播放完全结束 ==========
```

### 6、录音到文件功能（record_amr_file.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "record_amr_file"`，注释掉其他require
3. 将代码下载到开发板并运行
4. **演示效果**：开机自动挂载SD卡（挂载失败自动回退内部存储），自动开始5秒录音（AMR格式），录音完成后自动播放录音文件

**运行结果示例：**

```lua
I/user.音频系统初始化
I/user.开始挂载SD卡
I/user.SD卡挂载成功 挂载路径: /sd
I/user.SD卡空间信息 {"free_sectors":31107456,"total_kb":15554016,"free_kb":15553728,"total_sectors":31108032}
I/user.录音文件将保存到SD卡: /sd/record.amr
I/user.exaudio.setup 当前使用新音频框架
I/user.exaudio.setup 默认驱动已切换 tx_bus_type: 2 rx_bus_type: 1
I/user.exaudio.setup audio_v2 ES8311模式初始化
I/user.exaudio.setup ES8311已重启 dac_ctrl: 43
I/user.exaudio.setup ES8311初始化完成
I/user.exaudio.setup audio_v2初始化完成
I/user.音量设置 播放: 75 录音: 80
I/user.无录音文件 路径: /sd/record.amr
I/user.音频系统初始化完成，准备开始录音
I/user.录音时长:  5 秒
I/user.录音完成后自动播放
I/user.录音文件保存到: /sd/record.amr
I/user.开始录音 时长: 5 秒
I/user.删除旧录音文件
I/user.exaudio 录音开始 0
I/user.录音已开始
I/user.录音中... 1 秒
...（录音中，每秒打印一次）...
I/user.录音中... 5 秒
I/user.录音时长已达 5 秒，自动停止录音
I/user.停止录音 已录制: 5 秒
I/user.录音完成 大小: 5425 字节
I/user.录音文件路径 /sd/record.amr
I/user.播放录音文件 大小: 5425 字节
I/user.播放已开始
I/user.exaudio 播放开始 1
...（播放中，等待约5秒）...
I/user.exaudio 播放完毕 1
I/user.播放完成
```

### 7、录音到文件功能（record_pcm_file.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "record_pcm_file"`，注释其他require
3. 将代码下载到开发板并运行
4. **演示效果**：开机自动挂载SD卡（挂载失败自动回退内部存储），自动开始5秒录音（PCM格式，16kHz/16bit/单声道），录音完成后自动播放录音文件

**运行结果示例：**

```lua
I/user.音频系统初始化
I/user.开始挂载SD卡
I/user.SD卡挂载失败 format error
I/user.TF卡挂载失败，录音文件将无法保存到TF卡
I/user.exaudio.setup 当前使用新音频框架
I/user.exaudio.setup 默认驱动已切换 tx_bus_type: 2 rx_bus_type: 1
I/user.exaudio.setup audio_v2 ES8311模式初始化
I/user.exaudio.setup ES8311已重启 dac_ctrl: 43
I/user.exaudio.setup ES8311初始化完成
I/user.exaudio.setup audio_v2初始化完成
I/user.音量设置 播放: 70 录音: 70
I/user.无录音文件 路径: /record.pcm
I/user.音频系统初始化完成，准备开始录音
I/user.录音时长:  5 秒
I/user.录音完成后自动播放
I/user.录音文件保存到: /record.pcm
I/user.开始录音 时长: 5 秒
I/user.删除旧录音文件
I/user.exaudio 录音开始 0
I/user.录音已开始
I/user.录音中... 1 秒
...（录音中，每秒打印一次；PCM按3200字节/帧实时写入存储）...
I/user.录音中... 5 秒
I/user.停止录音 已录制: 5 秒
I/user.录音完成 大小: 108800 字节
I/user.录音文件路径 /record.pcm
I/user.流式播放录音文件 大小: 108800 字节
I/user.exaudio 流式播放启动成功, request_index: 1 采样率: 16000 codec_id: 0
I/user.流式播放已开始
I/user.exaudio 播放开始 1
...（播放中，约7秒后播放完毕）...
I/user.exaudio 播放完毕 1
I/user.播放完成
```

### 8、录音到文件功能（record_pcm_to_1103.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "record_pcm_to_1103"`，注释掉其他require
3. 确保已插入TF卡（录音文件默认保存到`/sd/record.pcm`）
4. 将代码下载到开发板并运行
5. **演示效果**：开机自动挂载TF卡（失败回退内部存储）→ 自动录音（默认5秒，实时写入并打印写入速度）→ 录音完成后自动流式播放录音文件

**运行结果示例：**

```lua
I/user.main audio 001.999.000
D/user.exaudio version -> 202609161747
I/user.音频系统初始化
I/user.开始挂载TF卡
E/user.TF卡挂载失败 mount error              -- 未插TF卡，自动回退内部存储
I/user.exaudio.setup 当前使用新音频框架
uart(2) tx pin: 31, rx pin: 30
I/user.air1103 初始化完成 1 6000000
I/user.exaudio.setup Air1103 芯片初始化完成
I/user.exaudio.setup audio_v2 Air1103模式初始化
I/user.exaudio air1103不支持调节麦克风音量
I/user.音量设置 播放: 70 录音: 70
I/user.找到录音文件 大小: 0 字节 路径: /record.pcm
I/user.音频系统初始化完成，准备开始录音
I/user.录音时长:  5 秒
I/user.开始录音 时长: 5 秒
I/user.exaudio.record_start 将录音5秒
I/user.air1103 发送程序复位 02 05 00, 等待重新初始化后自动恢复上行
I/user.exaudio air1103录音已开始(MIC上行)
I/user.录音已开始
I/user.TF卡写入统计 数据大小: 512 字节, 写入耗时: 3.00 ms, 写入速度: 166.67 KB/s
...（录音中，按16ms/512B节奏持续写入，并打印TF卡写入速度）
I/user.录音中... 1 秒
...
I/user.录音中... 5 秒
I/user.停止录音 已录制: 5 秒
I/user.录音完成 大小: 115200 字节
I/user.录音完成后，启动播放任务
I/user.exaudio air1103录音已停止
I/user.流式播放录音文件 大小: 115200 字节
I/user.exaudio air1103流式播放已启动，等待play_stream_write喂数据
I/user.流式播放已开始
I/user.流式播放缓冲区大小 3200
I/user.播放完成
I/user.流式数据读取完成
```

**注意：此功能Air1601和Air1602均支持**
