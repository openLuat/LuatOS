## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统并启动各个音频功能任务；

2、play_file.lua：音频文件播放功能模块，演示MP3、WAV、AMR格式音频文件的播放；

3、play_tts.lua：文字转语音功能模块，演示TTS语音合成功能；

4、play_stream.lua：流式音频播放功能模块，演示PCM格式音频的流式播放；

5、record_amr_file.lua：录音到文件功能模块，演示AMR格式音频录制；

6、record_pcm_file.lua：流式录音到文件功能模块，演示PCM格式音频录制；

7、http_download_play.lua：HTTP下载播放功能模块，演示从网络下载音频文件并播放；

8、sample-6s.mp3/10.amr：用于测试本地MP3和AMR文件播放的示例音频文件；

9、test.pcm：用于测试PCM流式播放的示例音频文件；

**注意:目前不支持录音和放音同时进行**

## 关于 Air8201H 音频

Air8201H 基于 Air780EHM 模组, 整机板上**板载 ES8311 音频编解码芯片**, 无需外挂 AirAUDIO 配件板即可使用音频功能。

本目录下各功能模块中的 `audio_setup_param` 已按 Air8201H 整机板的硬件配置好, 引脚对应关系如下:

```lua
local audio_setup_param = {
    model    = "es8311",   -- 板载编解码芯片为 ES8311
    i2c_id   = 0,          -- ES8311 挂在 I2C0 上
    pa_ctrl  = 23,         -- 音频放大器(PA)电源控制管脚
    dac_ctrl = 2,          -- 音频编解码芯片(ES8311)电源控制管脚
}
```

若将本 demo 移植到自制板, 请根据实际硬件接线修改 `i2c_id`、`pa_ctrl`、`dac_ctrl` 等参数。

## 常量的介绍

1、exaudio.PLAY_DONE：当播放音频结束时，会在回调函数返回播放完成的事件

2、exaudio.RECORD_DONE：当录音结束时，会在回调函数返回录音完成的事件

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

## 演示硬件环境

1、Air8201H 整机板一块（板载 ES8311 音频编解码芯片）

2、喇叭一个（接到整机板的喇叭接口）

3、TYPE-C USB数据线一根

- Air8201H 整机板通过 TYPE-C USB 口供电；

- TYPE-C USB 数据线直接插到Air8201H的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air8201H LuatOS固件](https://docs.openluat.com/air780epm/luatos/firmware/version/#air780ehmluatos)，选择支持TTS功能的固件（如需使用TTS功能）。

3、luatos需要的脚本和资源文件

- 本目录下的脚本(main.lua等)与资源文件(sample-6s.mp3、10.amr、test.pcm)；

- 准备好软件环境之后，将本目录下的项目文件烧录到 Air8201H 中。

4、lib脚本文件：使用Luatools烧录时，勾选添加默认lib选项，使用默认lib脚本文件；

## 演示核心步骤

在main.lua中，可以根据需要启用或禁用特定的音频功能任务：

- 通过注释或取消注释相应的require语句来控制功能模块的加载
- 每个功能模块作为独立的任务运行，可以单独测试或组合测试

### 目录结构说明

```lua
├── main.lua               # 主程序入口，负责初始化音频系统并启动各个音频功能任务
├── play_file.lua          # 音频文件播放功能模块，支持MP3、WAV、AMR格式
├── play_tts.lua           # 文字转语音功能模块，支持中文TTS语音合成
├── play_stream.lua        # 流式音频播放功能模块，支持PCM格式流式播放
├── record_amr_file.lua    # 录音到文件功能模块，支持AMR格式录音
├── record_pcm_file.lua    # 流式录音到文件功能模块，支持PCM格式录音
├── http_download_play.lua # HTTP下载播放功能模块，支持从网络下载音频文件并播放
├── sample-6s.mp3          # 示例音频文件，用于播放测试
├── test.pcm               # 示例PCM音频文件，用于流式播放测试
└── 10.amr                 # 示例AMR音频文件，用于播放测试
```

## **异常处理**

1、如出现I2C通讯异常的情况，请检查 ES8311 的 I2C 总线(I2C0)是否正常上拉；也可使用exmux库来管理i2c总线的上拉状态，详情请参考[exmux扩展库介绍文档](https://docs.openluat.com/osapi/ext/exmux/)。
