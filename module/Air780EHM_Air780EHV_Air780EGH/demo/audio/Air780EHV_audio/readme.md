## 功能模块介绍

1、main.lua：主程序入口；

2、play_file.lua： 播放音频文件，可支持wav,amr,mp3 格式音频

3、play_tts: 支持文字转普通话输出需要固件支持

4、play_stream: 流式播放音频，仅支持PCM 格式

5、record_file: 录音到文件，仅支持PCM 格式

6、record_stream:  流式录音，仅支持PCM。

7、sample-6s.mp3/10.amr: 用于测试本地mp3文件播放

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

4、record_file.lua 录音到文件,演示了pcm 录音到文件，使用powerkey 按键进行录音音量减小，点击boot 按键进行录音音量增加

5、record_stream.lua 流式录音(仅支持PCM),不断输出录音的数据地址和录音长度，供给应用层调用


## 演示硬件环境
1、Air780EHV核心板+AirAUDIO_1000配件板+喇叭

![alt text](https://docs.openLuat.com/cdn/image/Air780EHV+Airaudio1000.jpg)

Air780EHV核心板和AirAudio_1000 配件板的硬件接线方式为:

| Air780EHV核心板 | AirAUDIO_1000配件板 |
| ---------------| -----------------   |
| 3/MIC+         |     MIC+            |
| 4/MIC-         |     MIC-            |
| 5/SPK+         |     SPK+            |
| 6/SPK-         |     SPK-            |
| 19/GPIO22      |     PA_EN           |
| 3V3            |     VCC             |
| GND            |     GND             |

2、YPE-C USB数据线一根
- Air780EHM核心板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/) 

2、Air780EHV V2016版本固件（理论上，2025年7月26日之后发布的固件都可以）。[不同版本区别请见](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

3、[合宙 LuatIO 工具(GPIO 复用初始化配置)使用说明] (https://docs.openluat.com/air780epm/common/luatio/)

4、 lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；


## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码main.lua中，按照自己的需求选择对应的功能

- 如果需要测试播放音频文件，则选择play_file 文件

- 如果需要测试播放tts，则选择play_tts 文件

- 如果需要测试流式播放音频，则选择play_stream 文件

- 如果需要测试录音频到文件，则选择record_file 文件

- 如果需要测试流式录音，则选择record_stream 文件


3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行，如果出现以下日志，播放或者或者录音完成

``` lua
I/user.播放完成 true
I/user.录音完成 
I/user.录音后文件大小 
```

5、 在测试播放音频文件的时候，点powerkey 按键进行音频切换，切换内容是MP3,AMR格式，切换是通过播放优先级进行区分的，注意音频格式仅仅支持:MP3,WAV,AMR,点击boot 按键停止音频播放

6、 在测试播放TTS的时候，点powerkey 按键进行TTS 音色切换，点击boot 按键停止音频播放,注意:仅支持中文TTS。


7、在进行流式播放测试的时候,使用test.pcm 模拟音频来源，通过流式传输不断填入播放的音频，使用powerkey 按键进行音量减小，点击boot 按键进行音量增加，注意流式播放目前仅支持PCM 格式音频，可选择不同的采样率，以及位深

8、在测试录音到文件(仅支持PCM),演示了pcm 录音到文件，使用powerkey 按键进行录音音量减小，点击boot 按键进行录音音量增加

9、在测试流式录音(仅支持PCM),不断输出录音的数据地址和录音长度，供给应用层调用



