## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统并启动各个音频功能任务；

2、play_file.lua：播放音频文件，支持MP3/AMR/WAV格式，循环交替播放；

3、play_tts.lua：TTS文字转语音，循环播放5种音色；

4、play_stream.lua：流式音频播放功能模块，支持PCM/MP3/AMR/WAV格式音频的流式播放；

5、http_download_play: HTTP下载音频文件播放，联网后自动开始HTTP下载音频文件并播放，支持MP3/AMR/PCM格式

6、http_stream_play: HTTP音频流式播放（边下边播），支持PCM/AMR/MP3/WAV格式，自动连接WiFi

7、sample-6s.mp3、10.amr：用于测试本地音频文件播放；

8、test.pcm：用于测试PCM流式播放的示例音频文件；

**注意：1601只有DAC，没有I2S，所以无法录音，如需录音功能请使用1602**

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

- 搭建好硬件环境
- 打开main.lua，取消注释`require "http_download_play"`，注释掉其他require
- 将代码下载到开发板并运行
- 开机自动连接WiFi，连接成功后自动下载MP3音频文件并播放
- 需要固件版本>=V1026才可播放音频

### 5、HTTP音频流式播放功能（http_stream_play.lua）

- 搭建好硬件环境
- 打开main.lua，取消注释`require "http_stream_play"`，注释掉其他require
- 将代码下载到开发板并运行
- 自动连接WiFi，使用httpplus进行HTTP边下边播，支持PCM/AMR/MP3/WAV格式
- 需要固件版本>=V1026才可播放音频

## 演示硬件环境

1、Air1601开发板+喇叭

2、TYPE-C USB数据线一根

- Air1601开发板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air1601/common/Luatools/)

2、Air1601 最新版本固件（>=V1026）。

3、 luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601_Air1602/demo/audio/Air1601)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air1601开发板](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1601开发板中。

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
2. 打开main.lua，确保保留`require "play_stream"`这一行
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
