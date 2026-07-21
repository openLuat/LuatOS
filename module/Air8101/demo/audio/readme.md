## 功能模块介绍

1、play_file: 播放音频文件，支持MP3/AMR/WAV格式，循环交替播放

2、play_tts: TTS文字转语音，循环播放5种音色

3、play_stream: 流式播放音频，支持PCM/MP3/AMR/WAV格式，可以将音频推流到云端，用来对接大模型或者流式录音的应用

4、record_amr_file: 录音到文件（AMR格式），使用IO29键控制录音，IO37键控制播放，录音完成后自动播放

5、record_pcm_file: 录音到文件（PCM格式），使用IO29键控制录音，IO37键控制播放，流式录音并流式播放

6、http_download_play: HTTP下载音频文件播放，使用IO29键开始下载并播放，IO37键停止播放，支持MP3/AMR/PCM格式

7、http_stream_play: HTTP音频流式播放（边下边播），支持PCM/AMR/MP3/WAV格式，自动连接WiFi

8、sample-6s.mp3、10.amr: 用于测试本地音频文件播放

9、test.pcm: 用于测试PCM流式播放

注意：Air8101仅支持play_stream和http_stream_play播放，其他功能需要用Air8101B来测试

## 常量的介绍

1、exaudio.PLAY_DONE：当播放音频结束时，会在回调函数返回播放完成的时间

2、exaudio.RECORD_DONE：当录音结束时，会在回调函数返回播放完成的时间

## 演示功能概述

### 1、播放音频文件功能（play_file.lua）

- 播放MP3/AMR/WAV格式音频文件
- 初始化后播放sample-6s.mp3（MP3格式）
- 然后循环交替播放10.amr和sample-6s.mp3，播放间隔3秒
- 使用内置DAC输出音频

### 2、TTS文字转语音功能（play_tts.lua）

- 初始化后播默认TTS文字
- 然后循环播放5种音色的TTS，间隔3秒
- 音色包括：许久、许多、晓萍、唐老鸭、许宝宝
- 使用内置DAC输出音频

### 3、流式音频播放功能（play_stream.lua）

- 使用test.pcm模拟音频来源进行流式播放
- 通过流式传输不断填入播放的音频数据
- 支持PCM格式
- 使用内置DAC输出音频

### 4、录音到文件功能（record_amr_file.lua）

- 使用IO29键开始/停止录音，停止播放
- 使用IO37键开始/停止播放，停止录音
- 录音时长5秒，录音过程中可按任意键提前结束
- 录音完成后自动播放录音文件
- AMR_NB格式，录音文件保存到TF卡（/sd/record.amr），TF卡挂载失败时保存到内部存储
- 使用内置DAC输出音频

### 5、流式录音到文件功能（record_pcm_file.lua）

- 使用IO29键开始/停止录音，停止播放
- 使用IO37键开始/停止播放，停止录音
- 录音时长5秒，录音过程中可按任意键提前结束
- PCM格式，16kHz采样率、16位采样深度、有符号、单声道
- 录音文件保存到TF卡（/sd/record.pcm），TF卡挂载失败时保存到内部存储
- 使用流式播放方式播放录音文件
- 使用内置DAC输出音频
- 注意：播放采样位深仅支持到24位，如果录制32位录音则无法播放，需要用电脑进行播放

## 演示硬件环境

1、Air8101_v2.0开发板+喇叭

2、TYPE-C USB数据线一根

- Air8101开发板通过 TYPE-C USB 口供电；

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)

2、Air8101 最新版本固件。

3、 luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8101/demo/audio)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air8101开发板](https://docs.openluat.com/air8101/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air8101开发板中。

4、lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

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
├── record_amr_file.lua   # 录音到文件功能模块（AMR格式）
├── record_pcm_file.lua   # 录音到文件功能模块（PCM格式，流式录音/流式播放）
├── http_download_play.lua # HTTP下载音频文件播放功能模块
├── http_stream_play.lua  # HTTP音频流式播放功能模块（边下边播）
├── sample-6s.mp3         # 示例MP3音频文件
├── 10.amr                # 示例AMR音频文件
├── test.pcm              # 示例PCM音频文件，用于流式播放测试
└── readme.md             # 本文档
```

### 1、播放音频文件功能（play_file.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "play_file"`，注释掉其他require
3. 将代码下载到开发板并运行
4. **演示效果**：自动播放sample-6s.mp3，然后循环交替播放10.amr和sample-6s.mp3，间隔3秒

**注意：此功能需要用Air8101B来测试，Air8101不支持**

### 2、TTS文字转语音功能（play_tts.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "play_tts"`，注释掉其他require
3. 将代码下载到开发板并运行
4. **演示效果**：自动播放默认TTS，然后循环播放5种不同音色的TTS，间隔3秒

**注意：此功能需要用Air8101B来测试，Air8101不支持**

### 3、流式音频播放功能（play_stream.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，确保保留`require "play_stream"`这一行
4. 将代码下载到开发板并运行
5. **演示效果**：使用test.pcm模拟音频来源进行流式播放

**运行结果示例：**

```lua
I/user.开始流式播报
I/user.exaudio.setup audio_v2 DAC模式初始化
I/user.exaudio 调用stream: cid= 0 sr= 16000 bits= 16 ch= 1 sig= true pri= 0
I/user.开始流式获取音频数据
I/user.流式播放缓冲区大小 1600
...
I/user.exaudio audio_v2请求结束 0
I/user.播放完成 true
```

### 4、录音到文件功能（record_amr_file.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，取消注释`require "record_amr_file"`，注释掉其他require
4. 确保已插入TF卡（录音文件默认保存到`/sd/record.amr`）
5. 将代码下载到开发板并运行
6. **演示效果**：按IO29键开始5秒录音，录音完成后自动播放录音文件；按IO37键可随时播放最近一次录音

**运行结果示例：**

```lua
I/user.音频系统初始化
I/user.开始挂载TF卡
I/user.TF卡挂载成功 挂载路径: /sd
I/user.TF卡空间信息 {"free_sectors":31107456,"total_kb":15554016,"free_kb":15553728,"total_sectors":31108032}
I/user.TF卡挂载成功！！！
I/user.exaudio.setup 当前使用新音频框架
I/user.exaudio.setup DAC模式 - 通道:0, 声道:1
I/user.exaudio.setup audio_v2 DAC模式初始化
I/user.exaudio.setup audio_v2初始化完成
I/user.音量设置 播放: 70 录音: 70
I/user.找到录音文件 大小: 4728 字节 路径: /sd/record.amr
...
I/user.按下IO29键
I/user.开始录音 时长: 5 秒
I/user.删除旧录音文件
I/user.exaudio 录音已开始, req_id: 0
I/user.录音已开始，按任意键可提前结束
I/user.录音中... 1 秒
...
I/user.录音中... 5 秒
I/user.停止录音 已录制: 5 秒
I/user.录音完成 大小: 5425 字节
I/user.录音文件路径 /sd/record.amr
I/user.播放录音文件 大小: 5425 字节
I/user.播放已开始
I/user.exaudio 播放开始 1
...
I/user.exaudio 播放完毕 1
I/user.播放完成
```

**注意：此功能需要用Air8101B来测试，Air8101不支持**

### 5、流式录音到文件功能（record_pcm_file.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，取消注释`require "record_pcm_file"`，注释掉其他require
4. 确保已插入TF卡（录音文件默认保存到`/sd/record.pcm`）
5. 将代码下载到开发板并运行
6. **演示效果**：按IO29键开始5秒PCM录音，录音过程中实时写入TF卡并打印写入速度；录音完成后按IO37键流式播放录音文件

**注意事项：**
- PCM格式使用16kHz采样率、16位采样深度、有符号、单声道
- 播放采样位深仅支持到24位，如果录制32位录音则无法播放，需要用电脑进行播放
- 录音文件以追加方式实时写入TF卡，确保TF卡有足够空间

**运行结果示例：**

```lua
I/user.音频系统初始化
I/user.开始挂载TF卡
I/user.TF卡挂载成功 挂载路径: /sd
I/user.TF卡空间信息 {"free_sectors":31107456,"total_kb":15554016,"free_kb":15553728,"total_sectors":31108032}
I/user.TF卡挂载成功！！！
I/user.exaudio.setup 当前使用新音频框架
I/user.exaudio.setup DAC模式 - 通道:0, 声道:1
I/user.exaudio.setup audio_v2 DAC模式初始化
I/user.exaudio.setup audio_v2初始化完成
I/user.音量设置 播放: 70 录音: 70
I/user.找到录音文件 大小: 164800 字节 路径: /sd/record.pcm
...
I/user.按下IO29键
I/user.空闲状态，开始录音
I/user.开始录音 时长: 5 秒
I/user.删除旧录音文件
I/user.exaudio 录音已开始, req_id: 0
I/user.录音已开始，按任意键可提前结束
I/user.TF卡写入统计 数据大小: 1600 字节, 写入耗时: 66.00 ms, 写入速度: 23.67 KB/s
...
I/user.录音中... 1 秒
...
I/user.录音中... 5 秒
I/user.停止录音 已录制: 5 秒
...
I/user.按下IO37键
I/user.空闲状态，播放录音
I/user.录音文件路径 /sd/record.pcm
I/user.流式播放录音文件 大小: 158400 字节
I/user.exaudio 调用stream: cid= 0 sr= 16000 bits= 16 ch= 1 sig= true pri= 1
I/user.exaudio 流式播放启动成功, request_index: 1 采样率: 16000 codec_id: 0
I/user.流式播放缓冲区大小 1600
I/user.流式数据读取完成
I/user.exaudio 播放完毕 1
I/user.播放完成
```

**注意：此功能需要用Air8101B来测试，Air8101不支持**

### 6、HTTP下载音频文件播放功能（http_download_play.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "http_download_play"`，注释掉其他require
3. 将代码下载到开发板并运行
4. **演示效果**：按IO29键开始HTTP下载音频文件（MP3格式），下载完成后自动播放；按IO37键停止播放

**运行结果示例：**

```lua
I/user.http_pcm_stream_play 音频系统初始化
I/user.http_pcm_stream_play 开始挂载SD卡
E/user.http_pcm_stream_play SD卡挂载失败 format error
I/user.wifi 开始连接WiFi luatos1234
I/user.WiFi名称: luatos1234
I/user.ping_ip  : nil
I/user.WiFi STA初始化完成
I/user.netdrv 订阅socket连接状态变化事件 WiFi
I/user.wifi 等待IP获取...
I/user.wifi STA事件: CONNECTED luatos1234
I/user.收到STA事件 CONNECTED luatos1234
sta ip 192.168.137.25
I/user.wifi WiFi连接成功
I/user.exaudio.setup 当前使用新音频框架
I/user.exaudio.setup DAC模式 - 通道:0, 声道:1
I/user.exaudio.setup audio_v2 DAC模式初始化
I/user.exaudio.setup audio_v2初始化完成
I/user.http_pcm_stream_play 音量设置: 70
I/user.http_pcm_stream_play 音频硬件初始化成功
I/user.http_pcm_stream_play 存储路径: / (内存)
I/user.http_pcm_stream_play 按键功能说明：
I/user.http_pcm_stream_play 1. IO29按键: 开始HTTP下载并播放音频
I/user.http_pcm_stream_play 2. IO37按键: 停止播放
I/user.http_pcm_stream_play 3. 音频URL: http://airtest.openluat.com:2900/download/sample-6s.mp3
I/user.http_pcm_stream_play 4. 音频格式: mp3
I/user.http_pcm_stream_play 按下IO29键
I/user.http_pcm_stream_play 开始HTTP下载并播放 mp3
I/user.http_pcm_stream_play 启动HTTP下载播放任务
I/user.http_pcm_stream_play 音频格式: mp3 URL: http://airtest.openluat.com:2900/download/sample-6s.mp3
I/user.http_pcm_stream_play 临时文件路径: /tmp_http_audio.mp3 (内存)
I/user.http_pcm_stream_play 获取文件大小...
NOT SUPPORT HEAD
I/user.http_pcm_stream_play 下载进度: 0 / 51635
I/user.http_pcm_stream_play 下载进度: 1069 / 51635
I/user.http_pcm_stream_play 下载进度: 2469 / 51635
...（中间省略多行下载进度日志）...
I/user.http_pcm_stream_play 下载进度: 51635 / 51635
I/user.http_pcm_stream_play HTTP下载完成，文件大小: 51635
I/user.http_pcm_stream_play MP3 使用文件播放
I/user.http_pcm_stream_play 播放已启动
I/user.exaudio 播放开始 0
...（播放中，等待约6秒）...
I/user.exaudio 播放完毕 0
I/user.http_pcm_stream_play 播放完成
I/user.http_pcm_stream_play 临时文件已删除
```

**注意：此功能需要用Air8101B来测试，Air8101不支持**

### 7、HTTP音频流式播放功能（http_stream_play.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "http_stream_play"`，注释掉其他require
3. 将代码下载到开发板并运行
4. **演示效果**：自动连接WiFi，使用httpplus进行HTTP边下边播，支持PCM/AMR/MP3/WAV格式

**运行结果示例：**

```lua
I/user.wifi 开始连接WiFi luatos1234
I/user.WiFi名称: luatos1234
I/user.ping_ip  : nil
I/user.WiFi STA初始化完成
I/user.netdrv 订阅socket连接状态变化事件 WiFi
I/user.wifi 等待IP获取...
I/user.收到STA事件 CONNECTED luatos1234
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

**注意：此功能Air8101和Air8101B均支持**
