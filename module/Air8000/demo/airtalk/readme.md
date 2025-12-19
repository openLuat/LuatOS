## 功能模块介绍

1、main.lua：程序入口，初始化 AirTalk 对讲系统

2、talk.lua：airtalk 对讲业务核心模块

## 常量的介绍

1. extalk.START = 1     -- 通话开始

2. extalk.STOP = 2      -- 通话结束

3. extalk.UNRESPONSIVE = 3  -- 对端未响应

4. extalk.ONE_ON_ONE = 5  -- 一对一来电

5. extalk.BROADCAST = 6 -- 广播

## 演示功能概述

1、talk.lua 实现AirTalk对讲核心业务，包括联系人列表管理、对讲状态监控、音频设备控制等功能，实时显示对讲状态和设备信息。

2、main.lua 启动AirTalk对讲服务，按一次Boot键选择群组内第一个联系人，开始1对1对讲，再按一次Boot键结束对讲；按一次powerkey键开始一对多广播，再按一次powerkey或Boot键结束对讲。

3、当收到对讲信息的时候，LED灯常亮，关闭对讲的时候LED 灯灭。

## 演示硬件环境

Air8000开发板一块+喇叭

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
- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/airtalk)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air8000核心板中](https://docs.openluat.com/air8000/luatos/common/download/) 或者查看 [Air8000 产品手册](https://docs.openluat.com/air8000/product/shouce/) 中“Air8000 整机开发板使用手册 -> 使用说明”，将本篇文章中演示使用的项目文件烧录到 Air8000 开发板中。

4、[合宙 LuatIO 工具(GPIO 复用初始化配置)使用说明](https://docs.openluat.com/air780epm/common/luatio/)

5、 lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

## 演示核心步骤

1、搭建好硬件环境

2、创建群组：详情请见：https://docs.openluat.com/value/airtalk/

3、main.lua中，修改 PRODUCT_KEY 为 IoT 平台对应项目中获取的项目 key。

4、Luatools烧录内核固件和修改后的demo脚本代码

5、烧录成功后，自动开机运行，会打印以下日志

``` lua
 I/talk.lua:185 音频初始化成功
 I/talk.lua:193 extalk初始化成功
 I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/0001 内容: {"key":"123","device_type":2}
 I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/0002 内容: 
 I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/0002 内容: 
 I/talk.lua:37 联系人列表更新:
 I/talk.lua:39   1. ID: 861556079986013, 名称: 
 I/talk.lua:39   2. ID: 74959320, 名称: 866965083769676
 I/extalk.lua:462 对讲管理平台已连接
```

6、 点击BOOT 按键，会选择联系人列表第一个人，进行一对一对讲。
luatools会打印以下日志
``` lua
I/talk.lua:154 开始一对一对讲
I/extalk.lua:555 向 861556079986013 主动发起对讲
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/0003 内容: {"type":"one-on-one","topic":"audio\/866965083769676\/861556079986013\/5360"}
I/extalk.lua:131 对讲模式 0
I/talk.lua:54 对讲开始
……
I/talk.lua:143 结束当前对讲
I/extalk.lua:583 主动断开对讲
```

7、 点击POWERKEY按键，会进行广播，所有群组内的人，都会收到对讲消息。
luatools会打印以下日志
``` lua
 I/talk.lua:150 开始一对多广播
 I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/0003 内容: {"type":"broadcast","topic":"audio\/866965083769676\/all\/7287"}
 I/extalk.lua:131 对讲模式 1
 I/talk.lua:54 对讲开始
 ……
 I/talk.lua:143 结束当前对讲
 I/extalk.lua:583 主动断开对讲
```

8、当手机端对设备发起对讲，luatools会打印以下日志
``` lua
I/talk.lua:73 对讲测试 来电
I/extalk.lua:131 对讲模式 0
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/8102 内容: {"result":"success","info":"","topic":"audio\/74959320\/866965083769676\/au4p"}
I/talk.lua:54 对讲开始
……
I/extalk.lua:83 MQTT发布 - 主题: ctrl/uplink/866965083769676/8103 内容: {"info":"","result":"success"}
I/talk.lua:57 对讲结束
```


