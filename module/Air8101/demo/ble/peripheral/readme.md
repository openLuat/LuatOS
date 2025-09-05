## 功能模块介绍

1、main.lua：主程序入口；

2、ble_server_main.lua：ble外围设备主程序，进行ble初始化，设置广播内容，处理各类ble事件（连接、断开连接、写入请求等）；

3、ble_server_receiver.lua：ble外围设备接收数据处理逻辑；

4、ble_server_sender.lua：ble外围设备发送数据处理逻辑；

5、ble_timer_app.lua：ble外围设备定时器处理逻辑，启动两个循环定时器，分别以notify，write的形式定时向中心设备发送数据；

6、ble_uart_app.lua：ble外围设备接uart处理逻辑，将收到的中心设备的写入数据，通过uart发送到pc端串口工具；

## 用户消息介绍

1、"RECV_BLE_WRITE_DATA"：ble外围设备收到中心设备的写入数据后，会发布此消息，通知其他应用模块（如ble_uart_app）处理数据；

3、"SEND_DATA_REQ"：其他应用模块（ble_timer_app）发布此消息，通知ble 外围设备发送publish数据给中心设备；

## 演示功能概述

使用Air8101核心板演示 ble的peripheral(外围设备) 功能。

1、Air8101作为外围设备开启广播，被动等待中心设备发起连接；

2、连接成功后，定期向中心设备发送数据；

3、外围设备收到中心设备的写入数据后，通过uart1发送到pc端串口工具；
   
4、pc端串口工具收到数据后，打印到串口工具窗口。

## 演示硬件环境

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、USB转串口数据线一根

4、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接核心板的12/U1TX，绿线连接核心板的11/U1RX，黑线连接核心板的gnd，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1005版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上，2025年7月26日之后发布的固件都可以）

3、PC端的串口工具，例如SSCOM、LLCOM等都可以

4、nrf connect 蓝牙调试软件

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和修改后的demo脚本代码

3、烧录成功后，自动开机运行，如果设备出现以下日志，表示有中心设备主动发起连接，并连接成功

```lua
 I/user.BLE 设备连接成功: 5933D9B08C4B
```
4、如果出现以下日志，则表示Air8101在向中心设备指定的特征值UUID发送数据

```lua
-- 以下日志表示Air8101在向中心设备指定的特征值UUID发送数据，分别以notify，write的方式发送
I/user.ble_server_sender 使用write方式发送数据
I/user.send_data_cbfunc true timer 2 Fri Aug 29 17:17:21 2025
I/user.ble_server_sender 使用notify方式发送数据
I/user.send_data_cbfunc true timer 1 Fri Aug 29 17:17:19 2025
```
5、打开PC端的串口工具，选择uart1对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位；

6、在PC端的串口工具窗口中，会打印出中心设备写入外围设备的数据；

```lua
-- 以下便是uart1接收到的写入数据，数据格式为：服务UUID,特征值UUID,特征值数据
FA00,EA02,123456
```
7、在luatools日志中同样可以看到中心设备写入外围设备的数据。

```lua
I/user.BLE 收到写请求: FA00 EA02 123456
I/user.ble_server_receiver 收到写入数据 46413030 45413032 123456 6
```
