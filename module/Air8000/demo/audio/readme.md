## 总体设计框图

![输入图片说明](../../../../%E9%9F%B3%E9%A2%91%E7%A1%AC%E4%BB%B6%E6%A1%86%E6%9E%B6.png)

## 功能模块介绍

1、main.lua：主程序入口；

2、play_file.lua： 播放音频文件，可支持wav,amr,mp3 格式音频

3、play_tts: 支持文字转普通话输出需要固件支持

4、play_stream: 流式播放音频，仅支持PCM 格式，可以将音频推流到云端，用来对接大模型或者流式录音的应用。

5、record_file: 录音到文件，仅支持PCM 格式

6、record_stream:  流式录音，仅支持PCM，可以将音频流不断的拉取，可用来对接大模型

7、1.mp3: 用于测试本地mp3文件播放

8、test.pcm: 用于测试pcm 流式播放(实际可以云端下载)





## 常量的介绍

1、exaudio.PLAY_DONE : 当播放音频结束时,会在回调函数返回播放完成的时间

2、exaudio.RECORD_DONE : 当录音结束时，会在回调函数返回播放完成的时间

3、exaudio.AMR_NB : 仅录音时有用，表示使用AMR_NB 方式录音

4、exaudio.AMR_WB : 仅录音时有用，表示使用AMR_WB 方式录音

5、exaudio.PCM_8000 :  仅录音时有用，表示使用8000/秒 的速度对音频进行采样

6、exaudio.PCM_16000 : 仅录音时有用，表示使用16000/秒 的速度对音频进行采样

7、exaudio.PCM_24000 : 仅录音时有用，表示使用24000/秒 的速度对音频进行采样

8、exaudio.PCM_32000 : 仅录音时有用，表示使用32000/秒 的速度对音频进行采样

## 演示功能概述

1、播放一个mp3,演示了


## 演示硬件环境

![](https://docs.openluat.com/air8000/luatos/app/image/netdrv_multi.jpg)

1、Air8000开发板一块

2、喇叭一个

2、插入喇叭到开发板中


## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2014版本固件](https://docs.openluat.com/air8000/luatos/firmware/)（理论上，2025年7月26日之后发布的固件都可以）




## 演示核心步骤

