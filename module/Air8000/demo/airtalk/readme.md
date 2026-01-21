## 功能模块介绍

1、main.lua：程序入口，初始化 AirTalk 对讲系统

2、talk.lua：airtalk 对讲业务核心模块

3、audio_drv：音频设备初始化与控制

4、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；


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

Air8000开发板

![alt text](https://docs.openLuat.com/cdn/image/Air8000%E5%BC%80%E5%8F%91%E6%9D%BF.jpg )
 
 或者Air8000核心板+AirAUDIO_1010 音频扩展板+喇叭

![alt text]( https://docs.openLuat.com/cdn/image/Air8000%E6%A0%B8%E5%BF%83%E6%9D%BF+1010.jpg)

2、TYPE-C USB数据线一根
- Air8000开发板/核心板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

3、可选AirAudio_1010 配件板一块

Air8000核心板和AirAudio_1010 配件板的硬件接线方式为:

|  Air8000核心板   | AirAUDIO_1010配件板 |
| --------------- | -----------------   |
| 22/I2S_MCLK     | I2S_MCLK            |
| 18/I2S_BCK      | I2S_BCK             |
| 19/I2S_LRCK     | I2S_LRCK            |
| 20/I2S_DIN      | I2S_DIN             |
| 21/I2S_DOUT     | I2S_DOUT            |
| 80/I2C0_SCL     | I2C_SCL             |
| 81/I2C0_SDA     | I2C_SDA             |
| 82/GPIO17       | PA_EN               |
| 83/GPIO16       | 8311_EN             |
| VDD_EXT         | VCC                 |
| GND             | GND                 |

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/) 

2、Air8000 V2016版本固件，选择支持对讲功能的固件。不同版本区别请见https://docs.openluat.com/air8000/luatos/firmware/

3、 luatos需要的脚本和资源文件
- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/airtalk)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air8000核心板中](https://docs.openluat.com/air8000/luatos/common/hwenv/) 或者查看 Air8000 产品手册 中“Air8000 整机开发板使用手册 -> 使用说明”，将本篇文章中演示使用的项目文件烧录到 Air8000 开发板中。

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

5、netdrv_device.lua及netdrv文件夹内的netdrv_wifi 要连接的WiFi热点信息
  ``` lua
  exnetif.set_priority_order({{
      WIFI = {
          -- ssid = "茶室-降功耗,找合宙!", 
          -- password = "Air123456"
          ssid = "HONOR", -- WiFi SSID
          password = "iot12345678" -- WiFi密码
      }
  }})
  ``` 
6、Luatools烧录内核固件和修改后的demo脚本代码

7、烧录成功后，系统初始化

- 网络初始化：

  - 初始化以太网，注册CH390H设备，通过SPI1连接以太网芯片（CS引脚12）
  - WiFi STA模式初始化，配置WiFi名称和密码
  - 以太网和WiFi初始化完成，订阅网络状态变化事件
  - 连接默认网络

luatools会打印以下日志   
``` lua
 I/user.初始化以太网
 I/user.config.opts.spi 1 ,config.type 1
 SPI_HWInit 552:spi1 speed 25600000,25600000,12
 I/user.main open spi 0
 D/ch390h 注册CH390H设备(4) SPI id 1 cs 12 irq 255
 D/ch390h adapter 4 netif init ok
 D/netdrv.ch390x task started
 D/ch390h 注册完成 adapter 4 spi 1 cs 12 irq 255
 I/user.以太网初始化完成
 I/user.netdrv 订阅socket连接状态变化事件 Ethernet
 I/user.WiFi名称: HONOR
 I/user.密码     : iot12345678
 I/user.ping_ip  : nil
 I/user.WiFi STA初始化完成
 I/user.netdrv 订阅socket连接状态变化事件 WiFi
 change from 1 to 4
 W/extalk.lua:434 airtalk_mqtt_task: 等待默认网卡就绪，当前网卡ID: 4 4
 D/airlink wifi sta上线了
 D/netdrv 网卡(2)设置为UP
 D/ulwip adapter 2 dhcp start netif c1118b0
 D/ulwip adapter 2 ip 192.168.43.208
 D/ulwip adapter 2 mask 255.255.255.0
 D/ulwip adapter 2 gateway 192.168.43.1
 D/net network ready 2, setup dns server
 D/netdrv IP_READY 2 192.168.43.208
 change from 4 to 2
 I/extalk.lua:438 airtalk_mqtt_task: 默认网卡就绪，ID: 2 4
```

- 音频系统初始化
  - 初始化音频设备，配置ES8311编解码芯片和PA功放，音频设备初始化成功
  - 初始化extalk对讲功能
  - extalk初始化成功
  - LED指示灯初始化
  - talk.lua加载完成

luatools会打印以下日志
``` lua
 I/talk.lua:246 对讲模块初始化...
 I/talk.lua:151 按键初始化完成 - Boot键: GPIO0, Power键: GPIO46
 I/talk.lua:190 启动对讲系统...
 I/talk.lua:195 LED指示灯初始化完成 - GPIO20
 I/talk.lua:198 初始化音频设备...
 I/audio_drv.lua:37 audio_drv 开始初始化音频设备
 I2C_MasterSetup 426:I2C0, Total 65 HCNT 22 LCNT 40
 D/audio codec init es8311 
 I/audio_drv.lua:43 audio_drv 音频设备初始化成功
 I/talk.lua:203 音频初始化成功
 I/talk.lua:206 初始化extalk对讲功能...
 E/airtalk protocol 0 no mqttc
 I/talk.lua:212 extalk初始化成功
 I/talk.lua:255 talk.lua加载完成
``` 

- 网络连接成功后，配置系统

  - 连接到对讲管理平台，可进行对讲业务
  - 设备鉴权成功，进入在线状态
  - 联系人列表更新，获取到可用设备列表，包括本机设备和目标设备

  luatools会打印以下日志
  ``` lua
  I/talk.lua:215 ========== 系统配置信息 ==========
  I/talk.lua:216 目标设备ID: 78122397
  I/talk.lua:217 联网方式: 由netdrv_device.lua配置
  I/talk.lua:218 按键配置: Boot键(GPIO0)=一对一呼叫，Power键=广播
  I/talk.lua:219 按键逻辑: 对讲中按任意键=结束对讲，空闲时按Boot键=一对一呼叫，按Power键=广播
  I/talk.lua:220 ==================================
  I/talk.lua:227 目标设备已配置: 78122397
  I/talk.lua:230 对讲系统准备就绪，等待按键操作...
  I/extalk.lua:465 airtalk_mqtt_task: 设备信息 - IMEI: 864793080177038 MUID: 20250722144318A235862A2562652411
  D/net adapter 2 connect 121.196.102.79:1883 TCP
  I/extalk.lua:346 MQTT事件: conack 主题: 
  I/extalk.lua:346 MQTT事件: suback 主题: true
  I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/864793080177038/0001 内容: {"key":"5544VIDOIHH9Nv8huYVyEIGT4tCvldxI","device_type":1}
  I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/864793080177038/0002 内容:  
  I/talk.lua:48 联系人列表更新:
  I/talk.lua:50   1. ID: 867920073503634, 名称: 
  I/talk.lua:50   2. ID: 78122397, 名称: 对讲
  I/talk.lua:50   3. ID: 46365487, 名称: 46365487
  I/talk.lua:50   4. ID: 58391372, 名称: 58391372
  I/talk.lua:50   5. ID: 866965083769676, 名称: 866965083769676
  I/talk.lua:50   6. ID: 864793080009504, 名称: 
  I/talk.lua:50   7. ID: 861556079986013, 名称: 
  I/extalk.lua:484 airtalk_mqtt_task: 鉴权成功，进入在线状态
  I/extalk.lua:502 airtalk_mqtt_task: 对讲平台已连接，进入在线状态
  ``` 

8、当网络连接中断时，系统会自动检测并进行网络切换和重连
  - WiFi网络掉线，MQTT连接中断
  - 系统自动从WiFi切换到4G网络
  - 延时5秒后自动重连MQTT服务器
  - 使用4G网络重新连接对讲管理平台成功

luatools会打印以下日志
  ``` lua
 D/airlink wifi sta掉线了
 D/netdrv 网卡(2)设置为DOWN
 I/extalk.lua:346 MQTT事件: error 主题: other
 E/extalk.lua:376 MQTT错误: other 0
 W/extalk.lua:525 airtalk_mqtt_task: 收到断开通知，退出在线状态
 W/extalk.lua:539 airtalk_mqtt_task: 进入异常处理，准备重连
 I/extalk.lua:346 MQTT事件: disconnect 主题: 0
 W/extalk.lua:370 MQTT断开连接，触发对讲关闭
 I/extalk.lua:346 MQTT事件: close 主题: 
 D/netdrv IP_LOSE 2
 I/exnetif.lua:183 ip_lose_handle WiFi
 I/exnetif.lua:188 WiFi 失效，切换到其他网络
 I/exnetif.lua:94 设置网卡 4G
 I/netdrv_multiple.lua:35 netdrv_multiple_notify_cbfunc use new adapter 4G 1
 change from 2 to 1
 I/extalk.lua:563 airtalk_mqtt_task: 等待 5.000000 秒后重连
 I/extalk.lua:438 airtalk_mqtt_task: 默认网卡就绪，ID: 1 4
```

9、 点击BOOT 按键，会选择指定IMEI的目标设备，进行一对一对讲，再按一次Boot键或powerkey键结束对讲。
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

10、 点击POWERKEY按键，会进行广播，所有群组内的人，都会收到对讲消息，再按一次Boot键或powerkey键结束广播。

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

11、当其他设备或手机/PC的web网页端对设备发起一对一对讲。
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

12、当其他设备或手机/PC的web网页端对设备发起广播。
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
