## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统并启动各个音频功能任务；

2、play_file.lua：音频文件播放功能模块，演示MP3、WAV、AMR格式音频文件的播放；

3、play_tts.lua：文字转语音功能模块，演示TTS语音合成功能；

4、play_stream.lua：流式音频播放功能模块，演示PCM格式音频的流式播放；

5、record_amr_file.lua：录音到文件功能模块，演示AMR格式音频录制；

6、record_pcm_file.lua：流式录音到文件功能模块，演示PCM格式音频录制；

7、http_download_play.lua：HTTP下载音频文件播放功能模块，支持MP3/AMR/PCM格式，自动识别格式；

8、http_stream_play.lua：HTTP流式边下边播功能模块，支持PCM/AMR/MP3/WAV格式，自动识别格式，使用新音频框架；

9、sample-6s.mp3/10.amr：用于测试本地MP3和AMR文件播放的示例音频文件；

10、test.pcm：用于测试PCM流式播放的示例音频文件；

**注意:目前不支持录音和放音同时进行**

## 硬件版本兼容

本目录下所有模块同时兼容 **Air8201G** 和 **Air8201H** 两种硬件版本，通过 `main.lua` 中的 `_G.HARDWARE_ENV` 宏统一切换（默认值 `"H"`）。

| 项目 | Air8201G | Air8201H |
|------|----------|----------|
| `pa_ctrl` 引脚 | 25 | 23 |
| 操作按键 | PWRKEY (单按键长短按) | PWRKEY (单按键长短按) |
| ES8311 电压 | 默认 | `codec_voltage=0` (1.8V) |

**切换方法**：修改 `main.lua` 中 `_G.HARDWARE_ENV = "H"` 为 `"G"` 或 `"H"`，所有模块自动生效。



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
- 短按PWRKEY（< 1s）：切换音频（MP3↔AMR）
- 长按PWRKEY（≥ 1s）：停止音频播放

### 2、文字转语音功能（play_tts.lua）

- 播放TTS语音合成内容
- 短按PWRKEY（< 1s）：切换TTS音色
- 长按PWRKEY（≥ 1s）：停止TTS播放
- 仅支持中文TTS

### 3、流式音频播放功能（play_stream.lua）

- 使用test.pcm模拟音频来源进行流式播放
- 通过流式传输不断填入播放的音频数据
- 短按PWRKEY（< 1s）：音量 -15
- 长按PWRKEY（≥ 1s）：音量 +20
- 支持PCM/MP3/AMR/WAV格式音频

### 4、录音到文件功能 - AMR格式（record_amr_file.lua）

- 录音到文件（AMR格式），默认保存到/record.amr
- 短按PWRKEY（< 1s）：开始录音 / 停止录音 / 停止播放
- 长按PWRKEY（≥ 1s）：强制停止（录音或播放）
- 支持5秒录音时长，可提前结束
- 录音完成后自动播放录音文件

### 5、流式录音到文件功能 - PCM格式（record_pcm_file.lua）

- 录音到文件（PCM格式），默认保存到/record.pcm
- 短按PWRKEY（< 1s）：开始录音 / 停止录音 / 停止播放
- 长按PWRKEY（≥ 1s）：强制停止（录音或播放）
- 支持流式录音和播放
- 支持16kHz采样率、16位采样深度、有符号PCM数据

### 6、HTTP流式边下边播功能（http_stream_play.lua）

- 使用httpplus进行HTTP下载，边下边播
- 支持PCM/AMR/MP3/WAV格式的HTTP流式播放
- PCM格式默认16kHz、16位、有符号、单声道
- AMR/MP3/WAV格式会自动解析文件头获取真实采样率
- 使用新音频框架，固件需要V2046及以上的13/113号固件才能播放

## 演示硬件环境

本 demo 支持 **Air8201G** 和 **Air8201H** 两种板子：

1、Air8201G板子/Air8201H板子+喇叭

- Air8201G: 使用PWRKEY单按键（长短按区分操作）; pa_ctrl=25
- Air8201H: 使用PWRKEY单按键（长短按区分操作）; pa_ctrl=23; 需配置ES8311 1.8V电压


## 演示软件环境

1、Luatools下载调试工具

2、[Air8201H固件](https://cdn6.vue2.cn/Luat_tool_src/v2tools/LuatOS_Air780EHM/LuatOS-SoC_V2016_Air780EHM.zip)，选择支持TTS功能的1、3、5、7、13或101、103、105、107、113号固件。不同版本区别参考[Air780EHM LuatOS固件版本](https://docs.openluat.com/air780epm/luatos/firmware/version/)。

3、[Air8201G固件](https://cdn6.vue2.cn/Luat_tool_src/v2tools/LuatOS_Air780EGH/LuatOS-SoC_V2016_Air780EGH.zip)，选择支持TTS功能的1、3、5、7、13或101、103、105、107、113号固件。不同版本区别参考[Air780EGH LuatOS固件版本](https://docs.openluat.com/air780egh/luatos/firmware/version/)。

4、luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/audio)

5、[合宙 LuatIO 工具(GPIO 复用初始化配置)使用说明](https://docs.openluat.com/air780epm/common/luatio/)

6、lib脚本文件：使用Luatools烧录时，勾选添加默认lib选项，使用默认lib脚本文件；

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
├── http_download_play.lua # HTTP下载音频文件播放功能模块，支持MP3/AMR/PCM格式，自动识别格式
├── http_stream_play.lua   # HTTP流式边下边播功能模块，支持PCM/AMR/MP3/WAV格式，自动识别格式，使用新音频框架
├── sample-6s.mp3          # 示例音频文件，用于播放测试
├── test.pcm               # 示例PCM音频文件，用于流式播放测试
└── 10.amr                 # 示例AMR音频文件，用于播放测试
```

### 1、音频文件播放功能（play_file.lua）

1. 搭建好硬件环境
2. 打开main.lua，确保保留`require "play_file"`这一行
3. 将代码下载到开发板并运行
4. **演示效果**：自动播放sample-6s.mp3音乐，短按PWRKEY切换音频（MP3↔AMR），长按PWRKEY停止播放

**运行结果示例：**

```lua
I/user.开始播放音频文件
I/user.播放完成 true

I/user.短按PWRKEY，切换播放
E/user.是否完成播放 true
I/user.播放完成 true

I/user.长按PWRKEY，停止播放
```

### 2、文字转语音功能（play_tts.lua）

1. 搭建好硬件环境
2. 打开main.lua，确保保留`require "play_tts"`这一行
3. 将代码下载到开发板并运行
4. **演示效果**：播放TTS语音合成内容，短按PWRKEY切换音色，长按PWRKEY停止TTS播放

**运行结果示例：**

```lua
I/user.开始播放TTS
I/user.短按PWRKEY，切换播放

E/user.是否完成播放 true
I/user.播放完成 true

I/user.长按PWRKEY，停止播放
```

### 3、流式音频播放功能（play_stream.lua）

1. 搭建好硬件环境
2. 打开main.lua，确保保留`require "play_stream"`这一行
3. 将代码下载到开发板并运行
4. **演示效果**：使用test.pcm模拟音频来源进行流式播放，短按PWRKEY减小音量，长按PWRKEY增大音量

**运行结果示例：**

```lua
I/user.开始流式获取音频数据
I/user.开始流式播报

I/user.短按PWRKEY，减小音量55
I/user.长按PWRKEY，增大音量75

I/user.播放状态 true
I/user.播放完成 true
```

### 4、录音到文件功能 - AMR格式（record_amr_file.lua）

1. 搭建好硬件环境
2. 打开main.lua，确保保留`require "record_amr_file"`这一行
3. 将代码下载到开发板并运行
4. **演示效果**：录音到文件（AMR格式），短按PWRKEY开始/停止录音/播放，长按PWRKEY强制停止，支持5秒录音时长，可提前结束

**运行结果示例：**

```lua
I/user.音频系统初始化
I/user.exaudio.setup 声道数已设置为:1(1=单声道,2=双声道)
I/user.音量设置 播放: 60 录音: 60
I/user.无录音文件 路径: /record.amr
I/user.按键功能说明：
I/user.1. 短按PWRKEY: 开始录音 / 停止录音 / 停止播放
I/user.2. 长按PWRKEY: 强制停止（录音或播放）
I/user.3. 录音时长: 5秒，可提前结束
I/user.4. 录音完成后自动播放
I/user.5. 录音文件保存到: /record.amr

# 空闲时短按PWRKEY开始录音
I/user.短按PWRKEY，开始录音
I/user.开始录音 时长:5秒
I/user.录音已开始，可短按PWRKEY提前结束
I/user.录音中... 1 秒
I/user.录音中... 2 秒
I/user.录音中... 3 秒
I/user.录音中... 4 秒
I/user.录音中... 5 秒
I/user.停止录音 已录制: 5 秒
I/user.录音时长已达5秒，自动停止录音
I/user.录音完成 大小: 6703 字节
I/user.播放录音文件 大小: 6703 字节
I/user.播放已开始
I/user.播放完成
```

### 5、流式录音到文件功能 - PCM格式（record_pcm_file.lua）

1. 搭建好硬件环境
2. 打开main.lua，确保保留`require "record_pcm_file"`这一行
3. 将代码下载到开发板并运行
4. **演示效果**：录音到文件（PCM格式），短按PWRKEY开始/停止录音/播放，长按PWRKEY强制停止，支持流式录音和播放

**运行结果示例：**

```lua
I/user.音频系统初始化
I/user.exaudio.setup 声道数已设置为:1(1=单声道,2=双声道)
I/user.音量设置 播放: 60 录音: 60
I/user.找到录音文件 大小: 169600 字节 路径: /record.pcm
I/user.按键功能说明：
I/user.1. 短按PWRKEY: 开始录音 / 停止录音 / 停止播放
I/user.2. 长按PWRKEY: 强制停止（录音或播放）
I/user.3. 录音时长: 5秒，可提前结束
I/user.4. 录音完成后自动播放
I/user.5. 录音文件保存到: /record.pcm

# 空闲时短按PWRKEY开始录音
I/user.短按PWRKEY，开始录音
I/user.开始录音 时长:5秒
I/user.删除旧录音文件
I/user.录音已开始，可短按PWRKEY提前结束
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 28.00 ms, 写入速度: 334.82 KB/s
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 21.00 ms, 写入速度: 446.43 KB/s
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.录音中... 1 秒
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 26.00 ms, 写入速度: 360.58 KB/s
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.录音中... 2 秒
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 28.00 ms, 写入速度: 334.82 KB/s
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.录音中... 3 秒
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 29.00 ms, 写入速度: 323.28 KB/s
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 18.00 ms, 写入速度: 520.83 KB/s
I/user.录音中... 4 秒
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 29.00 ms, 写入速度: 323.28 KB/s
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 22.00 ms, 写入速度: 426.14 KB/s
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.录音中... 5 秒
I/user.停止录音 已录制: 5 秒
I/user.文件写入统计 数据大小: 6400 字节, 写入耗时: 15.00 ms, 写入速度: 416.67 KB/s
I/user.文件写入统计 数据大小: 9600 字节, 写入耗时: 26.00 ms, 写入速度: 360.58 KB/s
I/user.录音时长已达5秒，自动停止录音
I/user.录音完成 大小: 169600 字节

# 空闲时短按PWRKEY播放录音
I/user.短按PWRKEY，播放录音
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
2. 打开main.lua，确保保留`require "http_download_play"`这一行
3. 修改`http_download_play.lua`中的`AUDIO_URL`变量，设置为要下载的音频文件URL（支持PCM/MP3/AMR格式，自动识别）
4. 将代码下载到开发板并运行
5. **演示效果**：通过HTTP下载音频文件并播放，自动识别音频格式

**运行结果示例：**

```lua
I/user.http_pcm_stream_play 音频系统初始化
I/user.http_pcm_stream_play 等待网络就绪...
I/user.http_pcm_stream_play 网络已就绪
I/user.http_pcm_stream_play 音量设置: 70
I/user.http_pcm_stream_play 音频硬件初始化成功
I/user.http_pcm_stream_play 存储路径: / (内存)
I/user.http_pcm_stream_play 按键功能说明：
I/user.http_pcm_stream_play 短按PWRKEY: 开始下载播放 / 停止播放
I/user.http_pcm_stream_play 长按PWRKEY: 强制停止播放
I/user.http_pcm_stream_play 3. 音频URL: http://airtest.openluat.com:2900/download/10.amr
I/user.http_pcm_stream_play 4. 音频格式: amr

# 空闲时短按PWRKEY开始下载并播放
I/user.http_pcm_stream_play 短按PWRKEY，开始HTTP下载并播放 amr
I/user.http_pcm_stream_play 启动HTTP下载播放任务
I/user.http_pcm_stream_play 音频格式: amr URL: http://airtest.openluat.com:2900/download/10.amr
I/user.http_pcm_stream_play 临时文件路径: /tmp_http_audio.amr
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
- 播放完成后自动删除临时文件

### 7、HTTP流式边下边播功能（http_stream_play.lua）

1. 搭建好硬件环境
2. 打开main.lua，确保保留`require "http_stream_play"`这一行
3. 修改`http_stream_play.lua`中的`AUDIO_URL`变量，设置为要播放的音频文件URL（支持PCM/AMR/MP3/WAV格式，自动识别）
4. 将代码下载到开发板并运行
5. **演示效果**：通过HTTP边下载边播放音频，自动识别音频格式，AMR/MP3/WAV格式自动解析文件头获取真实采样率

**运行结果示例：**

```lua
I/user.network 等待4G网络就绪...
I/user.network 4G网络已就绪
I/user.exaudio.setup audio_mode=new，切换到新音频框架
I/user.exaudio.setup 当前使用新音频框架
I/user.exaudio.setup audio_v2 ES8311模式初始化
I/user.exaudio.setup ES8311初始化完成
I/user.exaudio.setup audio_v2初始化完成
I/user.stream ========== 开始HTTP下载+播放 ==========
I/user.stream URL: https://appstoreoss.luatos.com/iot-apps/res/100617/sample-6s.mp3
I/user.stream 头解析 ok: true sr: 0 data_start: 47
I/user.stream 头解析需继续缓冲
I/user.stream 头解析 ok: true sr: 44100 data_start: 47
I/user.exaudio 调用stream: cid= 5 sr= 44100 bits= 16 ch= 1 sig= true pri= 0
I/user.exaudio stream返回: ok= true req_id= 0
I/user.exaudio 流式播放启动成功, request_index: 0 采样率: 44100 codec_id: 5
I/user.stream 写入首块纯音频: 7685 字节
I/user.exaudio 播放开始 0
I/user.stat_http chunks: 5 downloaded: 20020 elapsed_ms: 0 speed: 0 B/s
I/user.stat_http chunks: 10 downloaded: 40500 elapsed_ms: 1 speed: 40500000 B/s
I/user.httpplus 服务器已完成响应
I/user.stream HTTP下载完成，总字节: 51635
I/user.stat_summary http_total: 51635 http_chunks: 13 http_time_ms: 1 http_speed: 51635000 B/s
I/user.exaudio 播放完毕 0
I/user.播放完成
I/user.stat_summary ========== 播放完全结束 ==========
```

**注意事项：**
- 音频格式根据URL后缀自动识别（.pcm/.mp3/.amr/.wav）
- PCM格式使用默认参数（16kHz、16位、有符号、单声道）启动流式播放
- AMR/MP3/WAV格式会先缓冲并解析文件头，获取真实采样率后再启动播放
- 下载速度通常远超播放速度，可实现流畅边下边播
- 本功能依赖新音频框架，需使用V2046及以上的13/113号固件
