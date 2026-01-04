
## 演示功能概述

使用Air780EHV核心板外挂Air510W开发板，本示例主要是利用exgnss库，实现了几种不同的应用场景，

第一种场景是：正常模式，第一步先是通过tcp_client_main文件连接服务器，然后第二步模块会配置GNSS参数，开启GNSS应用，第三步会开启一个60s的定时器，定时器每60s会打开一个60sTIMERRORSUC应用，第四步定位成功之后关闭GNSS，然后获取rmc获取经纬度数据，发送经纬度数据到服务器上。

第二种场景是：低功耗模式，第一步先是通过tcp_client_main文件连接服务器，然后第二步模块会配置GNSS参数，开启GNSS应用，第三步会开启一个60s的定时器，定时器每60s会进入正常模式，打开一个60sTIMERRORSUC应用，第四步定位成功之后关闭GNSS，然后获取rmc获取经纬度数据，发送经纬度数据到服务器上,进入低功耗模式。

第三种场景是：PSM+模式，唤醒之后第一步是配置GNSS参数，开启GNSS应用，第二步定位成功之后关闭GNSS，然后获取rmc获取经纬度数据，拼接唤醒信息和经纬度信息，连接服务器，然后把数据发送数据到服务器上，配置休眠唤醒定时器 ，进入飞行模式，然后进入PSM+模式。


## 演示硬件环境

1、Air780EHV核心板一块

2、Air510W开发板一块

3、TYPE-C USB数据线一根

4、Air780EHV核心板和数据线的硬件接线方式为

- Air780EHV核心板通过TYPE-C USB口供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- 外部供电使用的是Air9000给Air530W供电，Air9000的红线连接Air530W的VDD，黑线连接Air530W的GND。

5、为了测试方便，本次非Air780EHV模块低功耗模式，用的是开发板的3.3V给Air510W供电，接的是串口2，默认波特率115200，Air780EHV控制Air530W的ON_OFF脚的gpio是gpio21。外部供电时用了Air9000给Air510W供电。
| Air780EHV核心板 | Air530W开发板 |
| ---------------| -----------------   |
| 3.3V          |     VDD            |
| 29/U2TXD        |    RXD            |
| 28/U2RXD          |     TXD            |
| GND          |     GND          |
| 107/GPIO21     |     ON_OFF         |

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHV V2018版本固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

(1) 第一种场景演示：
打开GNSS应用
```lua
[2025-08-13 17:52:14.073][000000000.420] I/user.全卫星开启
[2025-08-13 17:52:14.105][000000000.420] I/user.agps开启

```
连接服务器成功回复：
```lua
[2025-08-13 17:52:16.557][000000006.653] I/user.tcp_client_main_task_func libnet.connect success
```

定位成功发送数据到服务器：
```lua
[2025-08-13 17:52:34.288][000000024.791] I/gnss Fixed 344787143 1141919779
[2025-08-13 17:52:34.350][000000024.854] I/user.exgnss.statInd@1 true 2 normal 60 36 nil function: 0C7EFAA8
[2025-08-13 17:52:34.367][000000024.855] I/user.exgnss.statInd@2 true 3 libagps 20 2 nil nil
[2025-08-13 17:52:34.943][000000025.448] I/user.exgnss.timerFnc@1 2 normal 60 36 1
[2025-08-13 17:52:34.961][000000025.448] I/user.TAGmode1_cb+++++++++ normal
[2025-08-13 17:52:34.973][000000025.449] I/user.nmea rmc {"variation":0,"lat":3447.8713379,"min":52,"valid":true,"day":13,"lng":11419.1972656,"speed":1.0460000,"year":2025,"month":8,"sec":34,"hour":9,"course":15.3769999}
[2025-08-13 17:52:34.984][000000025.450] I/user.exgnss.close 2 normal 60 function: 0C7EFAA8
[2025-08-13 17:52:34.993][000000025.451] I/user.exgnss.timerFnc@2 3 libagps 20 2 nil
[2025-08-13 17:52:35.010][000000025.452] I/user.DATA gnssnormal {"lat":3447.871338,"lng":11419.197266}
[2025-08-13 17:52:35.026][000000025.453] I/user.tcp_client_main_task_func libnet.wait true true nil
[2025-08-13 17:52:35.070][000000025.574] I/user.tcp_client_sender.proc send success
```
后续是循环这个操作，每60秒GNSS定位一次，每次定位成功后，通过TCP发送给服务器。

(2) 第二种场景低功耗模式，第三种场景PSM+场景，可以直接用Air9000搭配看功耗分析，配合服务器看接收日志，目前没办法用USB线通过luatools看日志。