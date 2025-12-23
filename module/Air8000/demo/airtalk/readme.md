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

2、Air8000 V2018版本固件，选择支持对讲功能的固件。不同版本区别请见https://docs.openluat.com/air8000/luatos/firmware/

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
  TARGET_DEVICE_ID = "78122397"  -- 请替换为实际的目标设备终端ID
  ``` 

5、talk.lua 中，修改WiFi连接参数。 
 ``` lua
-- WiFi连接参数（如果需要使用WiFi联网，请取消注释use_wifi函数调用）
local WIFI_CONFIG = {
    ssid = "茶室-降功耗,找合宙!",  -- WiFi SSID
    password = "Air123456",         -- WiFi密码
}
 ``` 
6、audio_drv中，根据硬件环境修改pa_ctrl和dac_ctrl配置
 - Air8000开发板pa_ctrl和dac_ctrl配置
  ``` lua
  pa_ctrl = 162,         -- 音频放大器电源控制管脚
  dac_ctrl = 164,        -- 音频编解码芯片电源控制管脚  
   ``` 
- Air8000核心板pa_ctrl和dac_ctrl配置
 ``` lua
  pa_ctrl = 17,         -- 音频放大器电源控制管脚
  dac_ctrl = 16,        -- 音频编解码芯片电源控制管脚 
   ```
7、Luatools烧录内核固件和修改后的demo脚本代码

8、烧录成功后，自动开机运行
- 对讲模块初始化
- 启动对讲系统
- LED指示灯初始化
- 初始化音频设备（通过I2C配置ES8311编解码芯片）

 luatools会打印以下日志
``` lua
I/talk.lua:428 对讲模块初始化...
I/talk.lua:371 启动对讲系统...
I/talk.lua:377 LED指示灯初始化完成 - GPIO146
I/talk.lua:383 初始化音频设备...
I/audio_drv.lua:37 audio_drv 开始初始化音频设备
I2C_MasterSetup 426:I2C0, Total 65 HCNT 22 LCNT 40
D/audio codec init es8311 
I/audio_drv.lua:43 audio_drv 音频设备初始化成功
I/talk.lua:388 音频初始化成功
```

9、联网配置：

9.1 WiFi联网（STA模式）
- 配置待连接的WiFi名称（SSID）和密码
- 订阅网络状态变化事件，等待连接就绪
- 连接成功，等待从AP（路由器）通过DHCP获取IP地址
- 收到IP就绪事件，获得完整的网络配置（IP、掩码、网关、DNS）

 luatools会打印以下日志
``` lua
 I/exnetif.lua:372 WiFi名称: HONOR
 I/exnetif.lua:373 密码     : iot12345678
 I/exnetif.lua:374 ping_ip  : nil
 I/exnetif.lua:387 WiFi STA初始化完成
 I/exnetif.lua:64 netdrv 订阅socket连接状态变化事件 WiFi
 change from 1 to 2
 I/exnetif.lua:611 notify_status function
 I/talk.lua:161 WiFi STA事件 CONNECTED HONOR
 I/talk.lua:163 WiFi已连接，等待获取IP地址
 D/airlink wifi sta上线了
 D/netdrv 网卡(2)设置为UP
 D/ulwip adapter 2 dhcp start netif c11169c
 D/DHCP dhcp discover C8C2C68F09CE
 D/ulwip 收到DHCP数据包(len=303)
 D/DHCP find ip d02ba8c0 192.168.43.208
 D/DHCP DHCP get ip ready
 D/ulwip adapter 2 ip 192.168.43.208
 D/ulwip adapter 2 mask 255.255.255.0
 D/ulwip adapter 2 gateway 192.168.43.1
 D/ulwip adapter 2 DNS1:192.168.43.1
 D/netdrv IP_READY 2 192.168.43.208
 I/talk.lua:169 IP就绪事件 192.168.43.208 2
 I/talk.lua:171 IP地址已获取，网络就绪
```

9.2 4G蜂窝网络联网
  - 系统加载完成后，开始等待网络连接就绪
  - 默认网卡被设置为4G适配器（ID:1）
  - 系统周期性主动检查网络状态，初始状态为“未获取到有效IP”
  - 等待移动网络模块（mobile）完成链路激活和IP地址分配
  -  网络就绪后，获取到运营商分配的IP地址（如10.90.8.191）

  luatools会打印以下日志
  ``` lua
  I/talk.lua:337 等待网络连接就绪...
  I/talk.lua:438 talk.lua加载完成
  I/talk.lua:293 主动检查网络状态...
  I/talk.lua:305 当前默认网卡: 4G 适配器ID: 1
  W/talk.lua:313 默认网卡未获取到有效IP地址
  (等待并多次检查...)
  D/mobile cid1, state0
  D/mobile bearer act 0, result 0
  D/mobile NETIF_LINK_ON -> IP_READY
  D/mobile TIME_SYNC 0
  I/talk.lua:305 当前默认网卡: 4G 适配器ID: 1
  I/talk.lua:310 IP地址: 10.90.8.191 子网掩码: 255.255.255.255 网关: 0.0.0.0
  I/talk.lua:354 主动检查发现网络已就绪  
  ```
10、 网络就绪，对讲核心功能初始化
  - 网络连接成功后（无论是WiFi或4G），系统初始化extalk对讲核心功
  - 读取并上报本机设备信息（IMEI和设备密钥）
  - 通过DNS解析并连接至对讲管理平台的MQTT服务器（mqtt.airtalk.luatos.com）
  - 与服务器完成MQTT协议握手、订阅主题、并上报设备信息进行认证
  - 从服务器获取并更新当前账号下的联系人/设备列表
  - 对讲管理平台连接成功，设备进入可操作状态

  luatools会打印以下日志
  ``` lua
  --无论通过WiFi还是4G联网，都会触发此流程
  I/talk.lua:324 初始化extalk对讲功能...
  I/extalk.lua:431 设备信息 864793080177038 20250722144318A235862A2562652411
  dns_run 676:mqtt.airtalk.luatos.com state 0 id 1 ipv6 0 use dns serverX, try 0
  D/net adapter X connect 121.196.102.79:1883 TCP // X为网卡ID
  I/talk.lua:331 extalk初始化成功
  I/talk.lua:414 对讲系统准备就绪，等待按键操作...
  I/extalk.lua:351 conack
  I/extalk.lua:440 connected
  I/extalk.lua:351 suback true
  I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/864793080177038/0001 内容: {"key":"5544VIDOIHH9Nv8huYVyEIGT4tCvldxI","device_type":1}
  I/extalk.lua:351 sent 0
  I/extalk.lua:351 recv ctrl/downlink/864793080177038/8001
  I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/864793080177038/0002 内容:
  I/extalk.lua:351 sent 0
  I/extalk.lua:351 recv ctrl/downlink/864793080177038/8002
  I/talk.lua:64 联系人列表更新:
  I/talk.lua:66   1. ID: 78122397, 名称: 对讲
  I/talk.lua:66   2. ID: 46365487, 名称: 46365487
   ... 
  I/extalk.lua:462 对讲管理平台已连接


11、点击BOOT 按键，会选择指定IMEI的目标设备，进行一对一对讲，再按一次Boot键或powerkey键结束对讲。
- 按下Boot键，启动一对一对讲流程
- 向指定IMEI设备（终端ID：78122397）发起对讲请求
- 通过MQTT向服务器发送一对一对讲请求，包含音频通道信息
- 进入一对一对讲模式
- 对讲连接建立成功，开始语音传输
- 系统状态更新为对讲中
- 再次按Boot或powerkey键，主动结束对讲

luatools会打印以下日志
``` lua
I/talk.lua:136 boot_key_callback
I/talk.lua:217 开始一对一对讲，目标设备: 78122397
I/extalk.lua:555 向 78122397 主动发起对讲
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/864793080177038/0003 内容: {"type":"one-on-one","topic":"audio\/864793080177038\/78122397\/6818"}
I/extalk.lua:351 recv ctrl/downlink/864793080177038/8003
I/extalk.lua:131 对讲模式 0
I/talk.lua:80 对讲开始
I/talk.lua:119 当前对讲状态: 正在对讲
// ... 音频设备切换、RTP流同步等底层日志
// 用户按键结束对讲
I/talk.lua:136 boot_key_callback //或 I/talk.lua:142 power_key_callback
I/talk.lua:202 结束当前对讲
I/extalk.lua:583 主动断开对讲
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/864793080177038/0004 内容: {"to":"78122397"}
I/extalk.lua:351 recv ctrl/downlink/864793080177038/8004
I/talk.lua:60 对讲结束 
```

12、 点击POWERKEY按键，会进行广播，所有群组内的人，都会收到对讲消息，再按一次Boot键或powerkey键结束广播。
- 按下Power键，启动广播对讲
- 通过MQTT向服务器发送广播请求，音频通道主题包含"all"标识
- 对讲模式1，进入广播对讲模式
- 广播连接建立成功，开始向所有设备广播
- 系统状态更新为对讲中
- 再次按Boot或powerkey键，结束广播对讲

luatools会打印以下日志

``` lua
I/talk.lua:142 power_key_callback
I/talk.lua:210 开始一对多广播
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/864793080177038/0003 内容: {"type":"broadcast","topic":"audio\/864793080177038\/all\/8618"}
I/extalk.lua:351 recv ctrl/downlink/864793080177038/8003
I/extalk.lua:131 对讲模式 1
I/talk.lua:80 对讲开始
I/talk.lua:119 当前对讲状态: 正在对讲
// ... 音频设备切换等底层日志
// 用户按键结束广播
I/talk.lua:136 boot_key_callback
I/talk.lua:202 结束当前对讲
I/extalk.lua:583 主动断开对讲
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/864793080177038/0004 内容: {"to":"all"}
I/extalk.lua:351 recv ctrl/downlink/864793080177038/8004
I/talk.lua:60 对讲结束 //或状态变为空闲
 ```

13、当其他设备或手机/PC的web网页端对设备发起一对一对讲。
- 收到其他设备的对讲呼叫请求，系统自动接听对讲（无需用户按键操作）
- 进入一对一对讲模式
- 通过MQTT通知服务器接听成功
- 确认对讲开始，语音通道建立
- 系统状态更新为对讲中
- 对方结束对讲，本机对讲也随之结束

luatools会打印以下日志
``` lua
I/extalk.lua:351 recv ctrl/downlink/864793080177038/0102
I/talk.lua:103 对讲 来电
I/talk.lua:119 当前对讲状态: 正在对讲
I/extalk.lua:131 对讲模式 0
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/864793080177038/8102 内容: {"result":"success","info":"","topic":"audio\/78122397\/864793080177038\/akmu"}
I/talk.lua:80 对讲开始
// ... 音频设备切换、RTP流同步等底层日志
// 对方挂断，本机收到结束指令
I/extalk.lua:351 recv ctrl/downlink/864793080177038/8004 //或其他结束指令
I/talk.lua:60 对讲结束
```

14、当其他设备或手机/PC的web网页端对设备发起广播。
- 收到其他设备的广播邀请
- 系统自动加入广播（无需按键操作）
- 对讲模式2，进入被动接听广播模式
- 通过MQTT通知服务器加入广播成功
- 确认广播对讲开始
- 系统状态更新为对讲中
- 广播结束，本机对讲也随之结束

luatools会打印以下日志
``` lua
I/extalk.lua:351 recv ctrl/downlink/864793080177038/0102
I/talk.lua:116 对讲 开始广播 //注意：此处指“开始接收广播”
I/talk.lua:119 当前对讲状态: 正在对讲
I/extalk.lua:131 对讲模式 2
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/864793080177038/8102 内容: {"result":"success","info":"","topic":"audio\/78122397\/all\/yne7"}
I/talk.lua:80 对讲开始
// ... 音频设备切换、RTP流同步等底层日志
// 广播结束，本机收到结束指令
I/extalk.lua:351 recv ctrl/downlink/864793080177038/8004
I/talk.lua:60 对讲结束
```
