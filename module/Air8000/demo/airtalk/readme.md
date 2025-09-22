## 总体设计框图

 



## 功能模块介绍

1、main.lua：主程序入口；

2、talk.lua：airtalk 运行主程序

## 常量的介绍

1. extalk.START = 1     -- 通话开始
2. extalk.STOP = 2      -- 通话结束
3. extalk.UNRESPONSIVE = 3  -- 对端未响应
4. extalk.ONE_ON_ONE = 5  -- 一对一来电
5. extalk.BROADCAST = 6 -- 广播


## 演示功能概述

1.    按一次boot，选择群组内第一个联系人，开始1对1对讲，再按一次boot，结束对讲
2.    按一次powerkey，开始1对多广播，再按一次powerkey或者boot，结束对讲


## 演示硬件环境

![](https://docs.openluat.com/air8000/luatos/app/image/netdrv_multi.jpg)

1、Air8000开发板一块

2、喇叭一个

2、插入喇叭到开发板中


## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2014版本固件](https://docs.openluat.com/air8000/luatos/firmware/)（理论上，2025年7月26日之后发布的固件都可以）


## 演示核心步骤

1、搭建好硬件环境

2、选择本demo 的全部文件(可不包含readme)

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行，如果出现以下日志

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



