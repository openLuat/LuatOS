## 功能模块介绍

1、main.lua：主程序入口；

2、ble_client_main.lua：ble中心设备主程序，进行ble初始化，处理各类ble事件（连接、断开连接、扫描报告、GATT操作完成等）；

3、ble_client_receiver.lua：ble中心设备接收数据处理逻辑；

4、ble_client_sender.lua：ble中心设备发送数据处理逻辑；

5、ble_timer_app.lua：ble中心设备定时器处理逻辑，启动两个循环定时器，一个用于定时读取外围设备特征值UUID数据，一个用于定时向外围设备特征值UUID发送数据；

6、ble_uart_app.lua：ble中心设备接uart处理逻辑，将收到的notify数据，通过uart发送到pc端串口工具；

## 用户消息介绍

1、"RECV_BLE_READ_DATA"：ble中心设备主动读取到外围设备特征值UUID数据时，会发布此消息，通知其他应用模块（如ble_uart_app）处理数据；

2、"RECV_BLE_NOTIFY_DATA"：ble中心设备收到外围设备特征值UUID的notify数据时，会发布此消息，通知其他应用模块（如ble_uart_app）处理数据；

3、"SEND_DATA_REQ"：其他应用模块（ble_timer_app）发布此消息，通知ble 中心设备发送publish数据给外围设备；

## 演示功能概述

使用Air8101核心板演示 ble的central(中心设备) 功能。

1、ble中心设备扫描并连接外围设备；

2、ble中心设备连接成功后，开始定时读取外围设备特征值UUID数据， 定时发送数据给外围设备；

3、ble中心设备收到外围设备特征值UUID的notify数据后，通过uart发送到pc端串口工具；

4、pc端串口工具收到数据后，打印到串口工具窗口。

## 演示硬件环境

1、Air8101核心板两块（本次演示中，一块作为中心设备，一块作为外围设备）

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

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和修改后的demo脚本代码

作为中心设备的Air8101核心板，需要烧录central代码；

作为外围设备的Air8101核心板，需要烧录peripheral代码；

3、烧录成功后，自动开机运行，如果中心设备出现以下日志，表示中心设备连接外围设备成功

```lua
I/user.ble 发现目标设备: LuatOS
I/user.ble 停止扫描, 连接设备 C8C2C68D4FF6 0
```
4、如果中心设备出现以下日志，则表示GATT服务发现完成，此时中心设备便可以进行读/写/监听操作

```lua
I/user.ble gatt item table: 60C78190
I/user.ble gatt item table: 60C77F90
I/user.ble gatt item table: 60C77DB0
I/user.ble GATT服务发现完成
```
5、打开PC端的串口工具，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位；

6、在PC端的串口工具窗口中，会打印出中心设备监听到的外围设备notify数据；

```lua
-- 以下便是uart接收到的notify数据，数据格式为：服务UUID,特征值UUID,特征值数据
FA00,EA01,123456Thu Jan  1 08:00:25 1970
```
7、在luatools日志中可以看到中心设备主动写入外围设备指定特征值UUID的数据，以及向外围设备写入的结果。

```lua
-- 中心设备写入数据后，会有数据发送结果回调函数触发，下面打印的"true" 表示发送成功，timer后面的“1234”便是发送的数据。
I/user.send_data_cbfunc true timer1234
```