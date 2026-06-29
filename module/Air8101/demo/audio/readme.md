## 功能模块介绍

1、play_file: 播放音频文件，支持MP3/AMR/WAV格式，循环交替播放

2、play_tts: TTS文字转语音，循环播放5种音色

3、play_stream: 流式播放音频，支持PCM/MP3/AMR/WAV格式，可以将音频推流到云端，用来对接大模型或者流式录音的应用

4、test.pcm: 用于测试pcm流式播放(实际可以云端下载)

注意：Air8101仅支持play_stream播放，其他功能需要用Air8101B来测试

## 常量的介绍

1、exaudio.PLAY_DONE：当播放音频结束时，会在回调函数返回播放完成的时间

2、exaudio.RECORD_DONE：当录音结束时，会在回调函数返回播放完成的时间

## 演示功能概述

### 1、播放音频文件功能（play_file.lua）

- 播放MP3/AMR/WAV格式音频文件
- 初始化后播放sample-6s.mp3（MP3格式）
- 然后循环交替播放10.amr和sample-6s.mp3，播放间隔3秒
- 使用内置DAC输出音频

**运行结果示例：**
```lua
I/user.开始播放音频文件
I/user.exaudio.setup DAC模式初始化
...
detect ok 44100-2-2-1, data start pos 47  -- sample-6s.mp3播放
auto search find codec 5                    -- 检测到MP3格式
...
detect ok 8000-2-1-1, data start pos 6     -- 10.amr播放
auto search find codec 2                    -- 检测到AMR格式
...
detect ok 44100-2-2-1, data start pos 47   -- 循环回sample-6s.mp3
```

### 2、TTS文字转语音功能（play_tts.lua）

- 初始化后播默认TTS文字
- 然后循环播放5种音色的TTS，间隔3秒
- 音色包括：许久、许多、晓萍、唐老鸭、许宝宝
- 使用内置DAC输出音频

**运行结果示例：**
```lua
I/user.开始播放TTS
I/user.exaudio.setup DAC模式初始化
...
find software codec 4          -- 检测到TTS格式
I/user.exaudio audio_v2播放开始 0
tts start, play info 16000,2,1  -- TTS启动，16kHz
...
tts decode sync end             -- TTS播放结束
```

### 3、流式音频播放功能（play_stream.lua）

- 使用test.pcm模拟音频来源进行流式播放
- 通过流式传输不断填入播放的音频数据
- 支持PCM格式
- 使用内置DAC输出音频

**运行结果示例：**
```lua
I/user.开始流式播报
I/user.exaudio.setup audio_v2 DAC模式初始化
I/user.exaudio 调用stream: cid= 0 sr= 16000 bits= 16 ch= 1 sig= true pri= 0
I/user.开始流式获取音频数据
I/user.流式播放缓冲区大小 1600
I/user.播放状态 false
...
print from irq 0 0 640          -- 流式数据写入中
decode input fifo not enough ...
...
I/user.exaudio audio_v2请求结束 0
I/user.播放完成 true
```

**注意：Air8101仅支持play_stream播放，play_file和play_tts功能需要用Air8101B来测试**

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
