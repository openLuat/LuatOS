## 功能模块介绍

1、main.lua：主程序入口；

2、play_file.lua： 播放音频文件，可支持wav,amr,mp3 格式音频

3、play_tts: 支持文字转普通话输出需要固件支持

4、play_stream: 流式播放音频，仅支持PCM 格式

5、record_file: 录音到文件（支持AMR格式）

6、record_stream:  流式录音，仅支持PCM。

7、sample-6s.mp3/10.amr: 用于测试本地mp3和amr文件播放

8、test.pcm: 用于测试pcm 流式播放(实际可以云端下载)


**注意:目前不支持录音和放音同时进行**


## 常量的介绍

1、exaudio.PLAY_DONE : 当播放音频结束时,会在回调函数返回播放完成的时间

2、exaudio.RECORD_DONE : 当录音结束时，会在回调函数返回播放完成的时间

3、exaudio.AMR_NB : 仅录音时有用，表示使用AMR_NB 方式录音

4、exaudio.AMR_WB : 仅录音时有用，表示使用AMR_WB 方式录音

5、exaudio.PCM_8000/exaudio.PCM_16000/exaudio.PCM_24000/exaudio.PCM_32000 :  仅录音时有用，表示使用8000/16000/24000/32000/秒 的速度对音频进行采样


## 演示功能概述

1、play_flie.lua 自动播放一个sample-6s.mp3音乐,点powerkey 按键进行音频切换，播放10.amr文件，点击boot 按键停止音频播放

2、play_tts.lua 播放一个TTS,点powerkey 按键进行tts 的音色切换，点击boot 按键停止音频播放

3、play_stream.lua 流式播放PCM,使用test.pcm 模拟音频来源，通过流式传输不断填入播放的音频，使用powerkey 按键进行音量减小，点击boot 按键进行音量增加

4、record_file.lua 录音到文件（支持AMR格式），使用powerkey/boot 按键开始或停止录音/播放等。

5、record_stream.lua 流式录音(仅支持PCM),不断输出录音的数据地址和录音长度，供给应用层调用


## 演示硬件环境
1、Air8000开发板一块+喇叭

![alt text](https://docs.openLuat.com/cdn/image/Air8000%E5%BC%80%E5%8F%91%E6%9D%BF.jpg )

或者Air8000核心板+AirAUDIO_1010 音频配件板+喇叭

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
| VDD_EXT         | VCC                 |
| GND             | GND                 |


2、TYPE-C USB数据线一根
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

1、搭建好硬件环境

2、demo脚本代码main.lua中，按照自己的需求选择对应的功能

- 如果需要测试播放音频文件，则选择play_file 文件

- 如果需要测试播放tts，则选择play_tts 文件

- 如果需要测试流式播放音频，则选择play_stream 文件

- 如果需要测试录音频到文件，则选择record_file 文件

- 如果需要测试流式录音，则选择record_stream 文件


3、Luatools烧录内核固件和修改后的demo脚本代码

4、 在测试播放音频文件的时候，点powerkey 按键进行音频切换，切换内容是MP3,AMR格式，切换是通过播放优先级进行区分的，注意音频格式仅仅支持:MP3,WAV,AMR,点击boot 按键停止音频播放

5、 在测试播放TTS的时候，点powerkey 按键进行TTS 音色切换，点击boot 按键停止音频播放,注意:仅支持中文TTS。


6、在进行流式播放测试的时候,使用test.pcm 模拟音频来源，通过流式传输不断填入播放的音频，使用powerkey 按键进行音量减小，点击boot 按键进行音量增加，注意流式播放目前仅支持PCM 格式音频，可选择不同的采样率，以及位深。

7、在测试录音到文件（支持AMR格式）时，使用powerkey/boot按键开始或停止录音/播放等。

8、在测试流式录音(仅支持PCM),不断输出录音的数据地址和录音长度，供给应用层调用。

9、运行结果展示

- 播放文件 (play_file.lua)

自动播放一个sample-6s.mp3 音乐；

点击powerkey 按键进行音频切换播放10.amr文件；

点击boot 按键停止音频播放

``` lua
 I/user.开始播放音频文件
 I/user.播放完成 true

 I/user.切换播放
 E/user.是否完成播放 true
 I/user.播放完成 true

 I/user.停止播放
 ```

 - 文字转语音 (play_tts.lua)

 播放一个TTS；

点击powerkey 按键进行tts 的音色切换

点击boot 按键停止音频播放

``` lua
 I/user.开始播放TTS
 I/user.切换播放

 E/user.是否完成播放 true
 I/user.播放完成 true

 I/user.停止播放

```

- 流式播放 (play_stream.lua)

创建一个播放流式音频task（task_audio）和一个模拟获取流式音频的task（audio_get_data），此task通过流式传输不断向exaudio.play_stream_write填入播放的音频，播放task 不断播放传入流式音频。

使用powerkey 按键进行音量减小，点击boot 按键进行音量增加

``` lua
 I/user.开始流式获取音频数据
 I/user.开始流式播报

 I/user.减小音量55
 I/user.增大音量75

 I/user.播放状态 true
 I/user.播放完成 true

```

- 录音到文件  (record_file.lua)

主程序录音到/record.amr 文件

使用powerkey/boot按键开始或停止录音/播放。

按键功能：

Power键：空闲时开始录音，录音中停止录音，播放中停止播放

Boot键：空闲时播放录音，播放中停止播放，录音中停止录音

录音完成后会自动播放录音文件。

``` lua
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
……
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
……
I/user.播放完成
```

- 流式录音(record_stream.lua)，仅支持PCM格式

主程序录音进行流式录音

录音过程中不断的进行recode_data_callback回调，回调内容为音频流的地址和长度。

``` lua
 I/user.开始流式录制音频到文件
 I/user.收到音频流,地址为: ZBUFF*:0C7F70A8 有效数据长度为: 9600
 I/user.录音完成

 E/user.减小音量55
 I/user.增大音量75

 I/user.录音后