## 功能模块介绍

1、main.lua：程序入口，初始化 AirTalk 对讲系统

2、talk.lua：airtalk 对讲业务核心模块

3、audio_drv：音频设备初始化与控制

## 常量的介绍

1. extalk.START            -- 通话开始

2. extalk.STOP             -- 通话结束

3. extalk.UNRESPONSIVE     -- 对端未响应

4. extalk.ONE_ON_ONE       -- 一对一来电

5. extalk.BROADCAST        -- 广播

## 演示功能概述

1、talk.lua 实现AirTalk对讲核心业务。

- 包括群组内联系人列表信息显示、对讲状态监控、音频设备控制等功能，实时显示对讲状态和设备信息。

- 按键处理：

（1）主动发起对讲：按一次Boot键选择指定设备，开始1对1对讲，再按一次Boot键或powerkey键结束对讲；按一次powerkey键开始一对多广播，再按一次Boot键或powerkey键结束广播。

（2）被动接听对讲：当其他设备呼叫本机时，自动接听对讲；按任意键（Boot或Power键）即可结束当前对讲。

3、audio_drv：定义所有硬件引脚常量，使用exaudio扩展库初始化音频设备。

2、main.lua 启动AirTalk对讲服务。

## 演示硬件环境

Air780EHV核心板+AirAUDIO_1000配件板+喇叭

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

2、TYPE-C USB数据线一根

- Air780EHV核心板通过 TYPE-C USB 口供电；

- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/) 

2、Air780EHV V2018版本固件,选择支持对讲功能的固件。[不同版本区别请见](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

3、 luatos需要的脚本和资源文件
- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/airtalk/Air780EHV)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air780EHV核心板](https://docs.openluat.com/air780ehv/luatos/common/download/)， 将本篇文章中演示使用的项目文件烧录到Air780EHV核心板中。

4、lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

## 演示核心步骤

1、搭建好硬件环境

2、创建群组：详情请见：[Airtalk](https://docs.openluat.com/value/airtalk/)  第 5.2 章节--创建群组

3、main.lua 中，修改 PRODUCT_KEY 。
 ``` lua
 --到 iot.openluat.com 创建项目，获取正确的项目key
 PRODUCT_KEY =  "5544VIDOIHH9Nv8huYVyEIGT4tCvldxI"
  ``` 

4、talk.lua 中，修改目标设备终端ID。 
  ``` lua
  -- 目标设备终端ID，修改为你想要对讲的终端ID
  TARGET_DEVICE_IMEI = "78122397"  -- 请替换为实际的目标设备终端ID
  ``` 
5、Luatools烧录内核固件和修改后的demo脚本代码

6、烧录成功后，自动开机运行
- 初始化音频设备，配置ES8311编解码芯片和PA功放
- 音频设备初始化成功，可正常录音和播放
- 初始化extalk对讲功能
- 设备信息显示，本机IMEI：866965083769676，设备密钥：20250724030359A635078A5501877477
- extalk初始化成功
- 对讲系统准备就绪等待用户操作
- 连接到对讲管理平台，可进行对讲业务
- 联系人列表更新，获取到可用设备列表，包括本机设备和目标设备

 luatools会打印以下日志
``` lua
 I/talk.lua:185 初始化音频
 I/audio_drv.lua:33 audio_drv 开始初始化音频设备化成功
 I/audio_drv.lua:39 audio_drv 音频设备初始化成功
 I/talk.lua:196 音频初始化成功
 I/talk.lua:199 初始化extalk...
 I/extalk.lua:431 设备信息 866965083769676 20250724030359A635078A5501877477
 I/talk.lua:205 extalk初始化成功
 I/talk.lua:207 对讲系统准备就绪
……
 I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/0001 内容: {"key":"5544VIDOIHH9Nv8huYVyEIGT4tCvldxI","device_type":1}
 I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/0002 内容:  
 I/talk.lua:37 联系人列表更新:
 I/talk.lua:39   1. ID: 861556079986013, 名称: 
 I/talk.lua:39   2. ID: 74959320, 名称: 866965083769676
 I/extalk.lua:462 对讲管理平台已连接
```

6、 点击BOOT 按键，会选择指定IMEI的目标设备，进行一对一对讲，再按一次Boot键或powerkey键结束对讲。
- 按下Boot键，启动一对一对讲流程
- 向指定IMEI设备（终端ID：78122397）发起对讲请求
- 通过MQTT向服务器发送一对一对讲请求，包含音频通道信息
- 进入一对一对讲模式
- 对讲连接建立成功，开始语音传输
- 系统状态更新为对讲中
- 再次按Boot或powerkey键，主动结束对讲

luatools会打印以下日志
``` lua
I/talk.lua:154 开始一对一对讲
I/extalk.lua:555 向 861556079986013 主动发起对讲
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/0003 内容: {"type":"one-on-one","topic":"audio\/866965083769676\/78122397\/6395"}
I/extalk.lua:131 对讲模式 0
I/talk.lua:54 对讲开始
I/talk.lua:86 当前对讲状态: 正在对讲
……
I/talk.lua:60 对讲结束
I/extalk.lua:583 主动断开对讲
```

7、 点击POWERKEY按键，会进行广播，所有群组内的人，都会收到对讲消息，再按一次Boot键或powerkey键结束广播。
- 按下Power键，启动广播对讲
- 通过MQTT向服务器发送广播请求，音频通道主题包含"all"标识
- 对讲模式1，进入广播对讲模式
- 广播连接建立成功，开始向所有设备广播
- 系统状态更新为对讲中
- 再次按Boot或powerkey键，结束广播对讲

luatools会打印以下日志
``` lua
I/talk.lua:150 开始一对多广播
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/8102 内容: {"result":"success","info":"","topic":"audio\/78122397\/all\/skkj"}
I/extalk.lua:131 对讲模式 1
I/talk.lua:54 对讲开始
I/talk.lua:86 当前对讲状态: 正在对讲
……
I/talk.lua:143 结束当前对讲
I/extalk.lua:583 主动断开对讲
 ```

8、当其他设备或手机/PC的web网页端对设备发起一对一对讲。
- 收到其他设备的对讲呼叫请求，系统自动接听对讲（无需用户按键操作）
- 进入一对一对讲模式
- 通过MQTT通知服务器接听成功
- 确认对讲开始，语音通道建立
- 系统状态更新为对讲中
- 对方结束对讲，本机对讲也随之结束

luatools会打印以下日志
``` lua
I/talk.lua:73 对讲 来电
I/talk.lua:94 当前对讲状态: 正在对讲
I/extalk.lua:131 对讲模式 0
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/8102 内容: {"result":"success","info":"","topic":"audio\/78122397\/866965083769676\/yvh9"}
I/talk.lua:54 对讲开始
I/talk.lua:94 当前对讲状态: 正在对讲
……
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/8103 内容: {"info":"","result":"success"}
I/talk.lua:57 对讲结束
I/talk.lua:94 当前对讲状态: 空闲
```

9、当其他设备或手机/PC的web网页端对设备发起广播。
- 收到其他设备的广播邀请
- 系统自动加入广播（无需按键操作）
- 对讲模式2，进入被动接听广播模式
- 通过MQTT通知服务器加入广播成功
- 确认广播对讲开始
- 系统状态更新为对讲中
- 广播结束，本机对讲也随之结束

luatools会打印以下日志
``` lua
I/talk.lua:91 对讲 开始广播
I/talk.lua:94 当前对讲状态: 正在对讲
I/extalk.lua:131 对讲模式 2
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/8102 内容: {"result":"success","info":"","topic":"audio\/78122397\/all\/rebu"}
I/talk.lua:56 对讲开始
I/talk.lua:94 当前对讲状态: 正在对讲
……
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/8103 内容: {"info":"","result":"success"}
I/talk.lua:60 对讲结束
I/talk.lua:94 当前对讲状态: 空闲
k.lua:57 对讲结束
```
