## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统并启动各个音频功能任务；

2、play_file.lua：音频文件播放功能模块，演示MP3、WAV、AMR格式音频文件的播放；

3、play_tts.lua：文字转语音功能模块，演示TTS语音合成功能；

4、play_stream.lua：流式音频播放功能模块，演示PCM格式音频的流式播放；

5、record_amr_file.lua：录音到文件功能模块，演示AMR格式音频录制；

6、record_pcm_file.lua：流式录音到文件功能模块，演示PCM格式音频录制；

7、http_download_play.lua：从HTTP下载音频文件并播放功能模块，演示从网络下载音频文件并播放的场景；

8、sample-6s.mp3/10.amr：用于测试本地MP3和AMR文件播放的示例音频文件；

9、test.pcm：用于测试PCM流式播放的示例音频文件；

**注意:目前不支持录音和放音同时进行**

**AirAUDIO_1020 使用注意：**
- AirAUDIO_1020 板载 TM8211 编解码器，**不支持录音功能**
- 使用 AirAUDIO_1020 时，仅需在 `audio_setup_param` 修改 `model="tm8211"` 并移除 `i2c_id` 配置即可支持播放功能

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

## 演示硬件环境

1、Air8000开发板一块+喇叭

![alt text](https://docs.openLuat.com/cdn/image/Air8000%E5%BC%80%E5%8F%91%E6%9D%BF.jpg )

2、Air8000核心板+AirAUDIO_1010 音频配件板+喇叭（可选）

![alt text]( https://docs.openLuat.com/cdn/image/Air8000%E6%A0%B8%E5%BF%83%E6%9D%BF+1010.jpg)

Air8000核心板和AirAudio_1010 配件板的硬件接线方式为:

|  Air8000核心板   | AirAUDIO_1010配件板 |
| --------------- | -----------------   |
| 22/I2S_MCLK     | I2S_MCLK            |
| 18/I2S_BCK      | I2S_BCK             |
| 19/I2S_LRCK     | I2S_LRCK            |
| 20/I2S_DIN      | I2S_DIN             |
| 21/I2S_DOUT     | I2S_DOUT            |
| 80/I2C_SCL      | I2C_SCL             |
| 81/I2C_SDA      | I2C_SDA             |
| 82/GPIO17       | PA_EN               |
| 83/GPIO16       | 8311_EN             |
| VBAT            | VCC                 |
| GND             | GND                 |

**AirAUDIO_1010 使用说明：**

1. 使用 AirAUDIO_1010 时，需要修改 `play_file.lua`、`play_tts.lua`、`play_stream.lua` 中的初始化参数：

```lua
local audio_setup_param ={
    model= "es8311",          -- 使用 ES8311 编解码器
    i2c_id = 0,               -- I2C总线ID，根据实际接线配置（0或1）
    pa_ctrl = 162,            -- PA控制管脚（Air8000开发板）
    dac_ctrl = 164,           -- ES8311电源控制管脚（Air8000开发板）
    -- 如果是Air8000核心板，使用以下配置：
    -- pa_ctrl = 17,
    -- dac_ctrl = 16,
}
```

2. 在 `main.lua` 中启用所需功能模块：

```lua
-- 播放功能
require "play_file"
-- require "play_tts"
-- require "play_stream"
-- require "http_download_play"
-- require "record_amr_file"
-- require "record_pcm_file"
```

3、Air8000核心板+AirAUDIO_1020 音频配件板+喇叭（可选）

![alt text]( https://docs.openLuat.com/cdn/image/Air8000+1020.jpg)

Air8000核心板和AirAudio_1020 配件板的硬件接线方式为:

|  Air8000核心板   | AirAUDIO_1020配件板 |
| --------------- | -----------------   |
| 18/I2S_BCK      | I2S_BCK             |
| 19/I2S_LRCK     | I2S_LRCK            |
| 21/I2S_DOUT     | I2S_DOUT            |
| 82/GPIO17       | PA_EN               |
| 83/GPIO16       | TM8211_EN           |
| VBAT            | VCC                 |
| GND             | GND                 |

**AirAUDIO_1020 使用说明：**

1. 使用 AirAUDIO_1020 时，需要修改 `audio_setup_param` 中的初始化参数：

```lua
local audio_setup_param ={
    model= "tm8211",          -- 改为 "tm8211"
    -- i2c_id 无需配置，TM8211不需要I2C
    pa_ctrl = 162,            -- PA控制管脚（Air8000开发板）
    dac_ctrl = 164,           -- TM8211电源控制管脚（Air8000开发板）
    -- 如果是Air8000核心板，使用以下配置：
    -- pa_ctrl = 17,
    -- dac_ctrl = 16,
}
```

2. 在 `main.lua` 中启用所需功能模块：

```lua
-- 播放功能
require "play_file"
-- require "play_tts"
-- require "play_stream"
-- require "http_download_play"

-- 因为AirAUDIO_1020配件板没有麦克风接口，所以不支持录音功能。
-- 录音功能（AirAUDIO_1020不支持）
-- require "record_amr_file"
-- require "record_pcm_file"
```

4、TYPE-C USB数据线一根

- Air8000开发板/核心板通过 TYPE-C USB 口供电；

- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)

2、Air8000 V2018版本固件，选择支持TTS功能的固件。不同版本区别参考[Air8000 LuatOS固件版本](https://docs.openluat.com/air8000/luatos/firmware/)。

3、 luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/audio)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air8000核心板](https://docs.openluat.com/air8000/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air8000开发板/核心板中。

4、[合宙 LuatIO 工具(GPIO 复用初始化配置)使用说明](https://docs.openluat.com/air780epm/common/luatio/)

5、 lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

## 演示核心步骤

在main.lua中，可以根据需要启用或禁用特定的音频功能任务：

- 通过注释或取消注释相应的require语句来控制功能模块的加载
- 每个功能模块作为独立的任务运行，可以单独测试或组合测试

### 目录结构说明

```lua
├── main.lua                # 主程序入口，负责初始化音频系统并启动各个音频功能任务
├── play_file.lua           # 音频文件播放功能模块，支持MP3、WAV、AMR格式
├── play_tts.lua            # 文字转语音功能模块，支持中文TTS语音合成
├── play_stream.lua         # 流式音频播放功能模块，支持PCM格式流式播放
├── record_amr_file.lua     # 录音到文件功能模块，支持AMR格式录音
├── record_pcm_file.lua     # 流式录音到文件功能模块，支持PCM格式录音
├── http_download_play.lua  # 从HTTP下载音频文件并播放功能模块
├── sample-6s.mp3           # 示例音频文件，用于播放测试
├── test.pcm                # 示例PCM音频文件，用于流式播放测试
└── 10.amr                  # 示例AMR音频文件，用于播放测试
```

### 1、音频文件播放功能（play_file.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1010音频板测试，需将AirAUDIO_1010音频板中PA开关拨到OFF，让软件控制PA，避免pop音
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
2. 搭配AirAUDIO_1010音频板测试，需将AirAUDIO_1010音频板中PA开关拨到OFF，让软件控制PA，避免pop音
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
2. 搭配AirAUDIO_1010音频板测试，需将AirAUDIO_1010音频板中PA开关拨到OFF，让软件控制PA，避免pop音
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
2. 搭配AirAUDIO_1010音频板测试，需将AirAUDIO_1010音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，确保保留`require "record_amr_file"`这一行
4. 将代码下载到开发板并运行
5. **演示效果**：录音到文件（AMR格式），通过powerkey/boot按键开始或停止录音/播放，支持5秒录音时长，可提前结束

**运行结果示例：**

```lua
I/user.音频系统初始化
I/user.开始挂载SD卡
I/user.SD卡挂载成功 挂载路径: /sd
I/user.SD卡空间信息 {"free_sectors":31098560,"total_kb":15549952,"free_kb":15549280,"total_sectors":31099904}
I/user.SD卡挂载成功！！！
I/user.exaudio.setup 声道数已设置为:1(1=单声道,2=双声道)
I/user.音量设置 播放: 60 录音: 60
I/user.无录音文件 路径: /sd/record.amr
I/user.按键功能说明：
I/user.1. Power键: 开始/停止录音，停止播放
I/user.2. Boot键: 开始/停止播放，停止录音
I/user.3. 录音时长: 5秒，可提前结束
I/user.4. 录音完成后自动播放
I/user.5. 录音文件保存到: /sd/record.amr

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
I/user.停止录音 已录制: 5 秒
I/user.录音时长已达5秒，自动停止录音
I/user.录音完成 大小: 6703 字节
I/user.播放录音文件 大小: 6703 字节
I/user.播放已开始
I/user.播放完成
```

### 5、流式录音到文件功能 - PCM格式（record_pcm_file.lua）

1. 搭建好硬件环境
2. 搭配AirAUDIO_1010音频板测试，需将AirAUDIO_1010音频板中PA开关拨到OFF，让软件控制PA，避免pop音
3. 打开main.lua，确保保留`require "record_pcm_file"`这一行
4. 将代码下载到开发板并运行
5. **演示效果**：录音到文件（PCM格式），通过powerkey/boot按键开始或停止录音/播放，支持流式录音和播放

**运行结果示例：**

```lua
I/user.音频系统初始化
I/user.开始挂载SD卡
I/user.SD卡挂载成功 挂载路径: /sd
I/user.SD卡空间信息 {"free_sectors":31098560,"total_kb":15549952,"free_kb":15549280,"total_sectors":31099904}
I/user.SD卡挂载成功！！！
I/user.exaudio.setup 声道数已设置为:1(1=单声道,2=双声道)
I/user.音量设置 播放: 60 录音: 60
I/user.找到录音文件 大小: 169600 字节 路径: /sd/record.pcm
I/user.按键功能说明：
I/user.1. Power键: 开始/停止录音，停止播放
I/user.2. Boot键: 开始/停止播放，停止录音
I/user.3. 录音时长: 5秒，可提前结束
I/user.4. 录音完成后自动播放
I/user.5. 录音文件保存到: /sd/record.pcm

# 空闲时按Power键开始录音
I/user.按下POWERKEY键
I/user.空闲状态，开始录音
I/user.开始录音 时长:5秒
I/user.删除旧录音文件
I/user.录音已开始，按任意键可提前结束
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 28.00 ms, 写入速度: 334.82 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 21.00 ms, 写入速度: 446.43 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.录音中... 1 秒
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 26.00 ms, 写入速度: 360.58 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.录音中... 2 秒
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 28.00 ms, 写入速度: 334.82 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.录音中... 3 秒
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 29.00 ms, 写入速度: 323.28 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 18.00 ms, 写入速度: 520.83 KB/s
I/user.录音中... 4 秒
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 29.00 ms, 写入速度: 323.28 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 22.00 ms, 写入速度: 426.14 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 20.00 ms, 写入速度: 468.75 KB/s
I/user.录音中... 5 秒
I/user.停止录音 已录制: 5 秒
I/user.SD卡写入统计 数据大小: 6400 字节, 写入耗时: 15.00 ms, 写入速度: 416.67 KB/s
I/user.SD卡写入统计 数据大小: 9600 字节, 写入耗时: 26.00 ms, 写入速度: 360.58 KB/s
I/user.录音时长已达5秒，自动停止录音
I/user.录音完成 大小: 169600 字节

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

## **异常处理**

1、使用合宙开发板时，如出现I2C/SPI通讯异常的情况，请使用exmux扩展库的setup函数初始化外设分组开关状态，使用open函数打开外设分组，并跳转至exmux扩展库介绍文档中了解I2C/SPI总线上拉问题；https://docs.openluat.com/osapi/ext/exmodbus/

2、使用自己制作的板子时，如出现I2C通讯异常的情况，请根据各型号文档中”硬件设计资料“的I2C和SPI板块”常见的坑“栏目中的经验，检查板子上的I2C/SPI总线是正常上拉；也可使用exmux库来管理i2c和spi总线的上拉状态，详情请参考exmux扩展库介绍文档。
