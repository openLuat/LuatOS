## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统并启动各个音频功能任务；

2、play_stream.lua：流式音频播放功能模块，演示PCM格式音频的流式播放；

3、record_pcm_file.lua：流式录音到文件功能模块，演示PCM格式音频录制；

4、test.pcm：用于测试PCM流式播放的示例音频文件；

**注意:目前不支持录音和放音同时进行**

## 常量的介绍

1、exaudio.PLAY_DONE：当播放音频结束时，会在回调函数返回播放完成的时间

2、exaudio.RECORD_DONE：当录音结束时，会在回调函数返回播放完成的时间

3、exaudio.PCM_8000/exaudio.PCM_16000/exaudio.PCM_24000/exaudio.PCM_32000：仅录音时有用，表示使用8000/16000/24000/32000/秒的速度对音频进行采样

## 演示功能概述

### 1、流式音频播放功能（play_stream.lua）

- 使用test.pcm模拟音频来源进行流式播放
- 通过流式传输不断填入播放的音频数据
- 通过GPIO8按键进行音量减小
- 通过GPIO9按键进行音量增加
- 仅支持PCM格式音频
- 需要固件版本>=V2014才可播放音频，V2012及以下固件在播放中无法触发 audio.MORE_DATA 回调，会导致无法播放流式音频

### 2、流式录音到文件功能 - PCM格式（record_pcm_file.lua）

- 录音到文件（PCM格式），默认保存到/sd/record.pcm（TF卡挂载成功）或/record.pcm（TF卡挂载失败）
- 通过GPIO8/GPIO9按键开始或停止录音/播放
- 支持流式录音和播放
- 支持16kHz采样率、16位采样深度
- 支持TF卡存储（需Air8101核心板+AirMICROSD_1010配件板）
- 需要固件版本>=V2014才可播放音频，V2012及以下固件在播放中无法触发 audio.MORE_DATA 回调，会导致无法播放流式音频

## 演示硬件环境

1、Air8101核心板+AirAUDIO_1000配件板+喇叭

Air8101核心板和AirAudio_1000 配件板的硬件接线方式为:

| Air8101核心板 | AirAUDIO_1000配件板 |
| ---------------| -----------------   |
| PIN15 (AUD_LN) |     SPK-            |
| PIN16 (AUD_LP) |     SPK+            |
| VBAT           |     VCC             |
| GND            |     GND             |
| GPIO28         |     PA_EN           |

2、TYPE-C USB数据线一根

- Air8101核心板通过 TYPE-C USB 口供电；

- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)

2、Air8101 最新版本固件。

3、 luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS_demo_v2_temp/tree/master/module/Air8101/demo/audio)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air8101核心板](https://docs.openluat.com/air8101/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air8101核心板中。

4、[合宙 LuatIO 工具(GPIO 复用初始化配置)使用说明](https://docs.openluat.com/air780epm/common/luatio/)

5、 lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

## 演示核心步骤

在main.lua中，可以根据需要启用或禁用特定的音频功能任务：

- 通过注释或取消注释相应的require语句来控制功能模块的加载
- 每个功能模块作为独立的任务运行，可以单独测试或组合测试

### 目录结构说明

```lua
├── main.lua              # 主程序入口，负责初始化音频系统并启动各个音频功能任务
├── play_stream.lua       # 流式音频播放功能模块，支持PCM格式流式播放
├── record_pcm_file.lua   # 流式录音到文件功能模块，支持PCM格式录音
├── test.pcm              # 示例PCM音频文件，用于流式播放测试
└── readme.md             # 本文档
```

### 1、流式音频播放功能（play_stream.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，确保保留`require "play_stream"`这一行
4. 将代码下载到开发板并运行
5. **演示效果**：使用test.pcm模拟音频来源进行流式播放，通过GPIO5按键进行音量减小，通过GPIO8按键进行音量增加

**运行结果示例：**

```lua
I/user.开始流式获取音频数据
I/user.开始流式播报

I/user.减小音量55
I/user.增大音量75

I/user.播放状态 true
I/user.播放完成 true
```

### 2、流式录音到文件功能 - PCM格式（record_pcm_file.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1000音频板测试，需将AirAUDIO_1000音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 如需录制到文件，请使用Air8101核心板+AirMICROSD_1010配件板
4. 打开main.lua，确保保留`require "record_pcm_file"`这一行
5. 将代码下载到开发板并运行
6. **演示效果**：录音到文件（PCM格式），通过GPIO8/GPIO9按键开始或停止录音/播放，支持5秒录音时长，可提前结束

**运行结果示例：**

```lua
I/user.音频系统初始化
I/user.TF卡挂载成功
I/user.音量设置 播放:70 录音:70
I/user.无录音文件
I/user.按键功能说明：
I/user.1. GPIO8: 开始/停止录音，停止播放
I/user.2. GPIO9: 开始/停止播放，停止录音
I/user.3. 录音时长: 5秒，可提前结束
I/user.4. 录音文件保存到: /sd/record.pcm

# 空闲时按GPIO8键开始录音
I/user.按下GPIO8
I/user.空闲状态，开始录音
I/user.开始录音 时长:5秒
I/user.录音已开始，按任意键可提前结束
I/user.录音中... 1 秒
I/user.录音中... 2 秒
I/user.录音中... 3 秒
I/user.录音中... 4 秒
I/user.录音中... 5 秒
I/user.停止录音 已录制: 5 秒
I/user.录音时长已达5秒，自动停止录音
I/user.录音完成 大小: 169600 字节
I/user.按下GPIO9开始播放录音文件

# 空闲时按GPIO9键播放录音
I/user.按下GPIO9
I/user.空闲状态，播放录音
I/user.流式播放录音文件 大小: 169600 字节
I/user.流式播放已开始
I/user.开始流式读取录音数据
I/user.流式播放缓冲区大小 1600
I/user.流式数据读取完成
I/user.播放完成
```
