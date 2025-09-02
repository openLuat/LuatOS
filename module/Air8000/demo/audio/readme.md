## 总体设计框图

![输入图片说明](../../../../audio%E9%9F%B3%E9%A2%91%E6%8B%93%E6%89%91.png)


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

1、Air8000开发板一块+可上网的sim卡一张+4g天线一根+wifi天线一根+网线一根：

- sim卡插入开发板的sim卡槽

- 天线装到开发板上

- 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air8000开发板和数据线的硬件接线方式为：

- Air8000开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接开发板的UART1_TX，绿线连接开发板的UART1_RX，黑线连接核心板的GND，另外一端连接电脑USB口；


## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2012版本固件](https://docs.openluat.com/air8000/luatos/firmware/)（理论上，2025年7月26日之后发布的固件都可以）

3、PC端的串口工具，例如SSCOM、LLCOM等都可以

4、[MQTT客户端软件MQTTX](https://docs.openluat.com/air8000/luatos/common/swenv/#27-mqttmqttx)


## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行，如果出现以下日志，表示四路mqtt连接成功

``` lua
I/user.mqtt_client_main_task_func connect success

I/user.mqtts_client_main_task_func connect success

I/user.mqtts_ca_client_main_task_func connect success

I/user.mqtts_m_ca_client_main_task_func connect success
```

5、启动三个MQTTX工具，分别连接上mqtt client、mqtts client、mqtts mutual client对应的server，订阅$imei/timer/up$主题，imei表示设备的imei号；可以看到，每隔5秒钟，会接收到一段类似于 send from timer: 1 的数据，最后面的数字每次加1；

6、打开PC端的串口工具，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位；

7、PC端的串口工具输入一段数据，点击发送，在MQTTX工具订阅的$imei/uart/up$主题下可以接收到数据；

8、在MQTTX工具上，在主题$imei/down$下publish一段数据，点击发送，在PC端的串口工具上可以接收到主题和数据，并且也能看到是哪一个server发送的，类似于以下效果：

``` lua
recv from mqtt server: 864793080144269/down,123456798012345678901234567830
recv from mqtt ssl server: 864793080144269/down,123456798012345678901234567830
recv from mqtt ssl ca server: 864793080144269/down,123456798012345678901234567830
recv from mqtt ssl mutual ca server: 864793080144269/down,123456798012345678901234567830
```
