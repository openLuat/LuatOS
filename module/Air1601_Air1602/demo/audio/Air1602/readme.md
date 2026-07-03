## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统并启动各个音频功能任务；

2、play_file.lua：播放音频文件，支持MP3/AMR/WAV格式，循环交替播放；

3、play_tts.lua：TTS文字转语音，循环播放5种音色；

4、play_stream.lua：流式音频播放功能模块，支持PCM/MP3/AMR/WAV格式音频的流式播放；

5、test.pcm：用于测试PCM流式播放的示例音频文件；

**注意：目前不支持录音和放音同时进行**

## 演示功能概述

### 1、播放音频文件功能（play_file.lua）

- 播放MP3/AMR/WAV格式音频文件
- 初始化后播放sample-6s.mp3
- 然后循环交替播放10.amr和sample-6s.mp3，播放间隔3秒
- 使用内置DAC输出音频

### 2、TTS文字转语音功能（play_tts.lua）

- 初始化后播放默认TTS
- 然后循环播放5种音色的TTS，间隔3秒
- 音色包括：许久、许多、晓萍、唐老鸭、许宝宝
- 使用内置DAC输出音频

### 3、流式音频播放功能（play_stream.lua）

- 使用test.pcm模拟音频来源进行流式播放
- 支持PCM/MP3/AMR/WAV格式
- 通过流式传输不断填入播放的音频数据
- 需要固件版本>=V1024才可播放音频

## 演示硬件环境

1、Air1602核心板+喇叭

Air1602核心板使用内置DAC输出音频，接线方式:

| Air1602核心板 | 喇叭/音频输出 |
| --------------| --------------|
| DAC输出引脚   |     喇叭+      |
| GND           |     喇叭-      |

**注意：** Air1602使用内置DAC，无需外部音频编解码芯片（如ES8311）

**重要提示：** 请根据实际硬件修改各lua文件中的引脚配置：
- PA_CTRL_PIN：PA功放电源控制引脚（默认GPIO45，需确认）

2、TYPE-C USB数据线一根

- Air1602核心板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air1602/common/Luatools/)

2、Air1602 最新版本固件（>=V1024）。

3、 luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601_Air1602/demo/audio/Air1602)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air1602核心板](https://docs.openluat.com/air1602/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1602核心板中。

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
├── test.pcm              # 示例PCM音频文件，用于流式播放测试
└── readme.md             # 本文档
```

### 1、播放音频文件功能（play_file.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "play_file"`，注释其他require
3. 将代码下载到开发板并运行
4. **演示效果**：初始化后播放sample-6s.mp3，然后循环交替播放10.amr和sample-6s.mp3，间隔3秒

### 2、TTS文字转语音功能（play_tts.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "play_tts"`，注释其他require
3. 将代码下载到开发板并运行
4. **演示效果**：初始化后播放默认TTS，然后循环播放5种音色的TTS，间隔3秒

### 3、流式音频播放功能（play_stream.lua）

1. 搭建好硬件环境
2. 打开main.lua，取消注释`require "play_stream"`，注释其他require
3. 将代码下载到开发板并运行
4. **演示效果**：使用test.pcm模拟音频来源进行流式播放

