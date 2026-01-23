## 功能模块介绍

1、main.lua：主程序入口；

2、ble_server_main.lua：ble外围设备主程序，进行ble初始化，设置广播内容，处理各类ble事件（连接、断开连接、写入请求等）；

3、ble_server_receiver.lua：ble外围设备接收数据处理逻辑；

4、ble_server_sender.lua：ble外围设备发送数据处理逻辑；

5、ble_timer_app.lua：ble外围设备定时器处理逻辑，启动两个循环定时器，分别以notify，write的形式定时向中心设备发送数据；

6、ble_uart_app.lua：ble外围设备接uart处理逻辑，将收到的中心设备的写入数据，通过uart发送到pc端串口工具；

7、check_wifi.lua：检查当前Air8000模组的WiFi固件是否为最新版本，若不是则自动启动升级（需插入可联网的SIM卡）。

8、ble_lowpower.lua：控制WiFi和蓝牙的开启和关闭，默认WiFi和蓝牙都是开启状态，无需控制

## 用户消息介绍

1、"RECV_BLE_WRITE_DATA"：ble外围设备收到中心设备的写入数据后，会发布此消息，通知其他应用模块（如ble_uart_app）处理数据；

3、"SEND_DATA_REQ"：其他应用模块（ble_timer_app）发布此消息，通知ble 外围设备发送publish数据给中心设备；

## 演示功能概述

使用Air8000核心板演示 ble的peripheral(外围设备) 功能。

1、Air8000作为外围设备开启广播，被动等待中心设备发起连接；

2、连接成功后，定期向中心设备发送数据；

3、外围设备收到中心设备的写入数据后，通过uart1发送到pc端串口工具；
   
4、pc端串口工具收到数据后，打印到串口工具窗口。

## 演示硬件环境

1、Air8000核心板一块

2、TYPE-C USB数据线一根

3、Air8000核心板和数据线的硬件接线方式为

- Air8000核心板通过TYPE-C USB口供电；（正常测试时核心板背面的功耗测试开关拨到ON，正面的白色拨码(供电,充电选择脚)开关拨到供电.）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air8000 V2012版本固件](https://docs.openluat.com/air8000/luatos/firmware/)（理论上，2025年7月26日之后发布的固件都可以）

3、PC端的串口工具，例如SSCOM、LLCOM等都可以

4、nrf connect 蓝牙调试软件

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和修改后的demo脚本代码

3、烧录成功后，自动开机运行，如果设备出现以下日志，表示有中心设备主动发起连接，并连接成功

```lua
 I/user.BLE 设备连接成功: 5933D9B08C4B
```
4、如果出现以下日志，则表示Air8000在向中心设备指定的特征值UUID发送数据

```lua
-- 以下日志表示Air8000在向中心设备指定的特征值UUID发送数据，分别以notify，write的方式发送
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

8、演示ble_lowpower.lua模块的功能

- 控制WiFi和蓝牙的开启和关闭

- 默认WiFi和蓝牙都是开启状态，无需控制

- 每300秒关闭一次WiFi，再开启一次WiFi

如果关闭了WiFi和蓝牙后，Luatools将打印”airlink slave timeout”，表示Air8000的4G部分和WiFi协处理器通信超时：

```lua
D/airlink slave timeout
```

下面是演示打开ble_lowpower模块后的日志：

```lua
[2026-01-23 14:01:44.945][000000000.431] I/airlink AIRLINK_READY 431 version 18 t 236
[2026-01-23 14:01:44.968][000000000.435] D/airlink Air8000s启动完成, 等待了 192 ms
[2026-01-23 14:01:45.033][000000000.464] I/user.main project name is  ble_peripheral version is  001.000.000
[2026-01-23 14:01:45.047][000000000.503] D/drv.bt 执行luat_bluetooth_init
[2026-01-23 14:01:45.056][000000000.515] Uart_ChangeBR 1461:uart1, 115200 115203 26000000 3611
[2026-01-23 14:01:45.209][000000000.630] I/user.ble_server_main 广播已成功启动
[2026-01-23 14:01:48.643][000000005.248] I/user.BLE 设备连接成功: 429242B64C70
[2026-01-23 14:01:48.666][000000005.249] I/user.ble_timer_app 已启动notify发送定时器, 间隔: 5000ms
[2026-01-23 14:01:48.670][000000005.250] I/user.ble_timer_app 已启动write发送定时器, 间隔: 6000ms
[2026-01-23 14:01:50.248][000000006.852] I/user.BLE 收到写请求:   0100
[2026-01-23 14:01:50.263][000000006.852] I/user.ble_server_receiver 收到写入数据   0100 4
[2026-01-23 14:01:53.646][000000010.250] I/user.ble_server_sender 使用notify方式发送数据
[2026-01-23 14:01:53.868][000000010.472] I/pm pm
[2026-01-23 14:01:53.871][000000010.472] I/user.ble_lowpower 发布: WiFi状态 -> 0
[2026-01-23 14:01:53.874][000000010.473] I/user.ble_server_main 收到WiFi状态变化: 0
[2026-01-23 14:01:53.880][000000010.474] E/user.ble_server_main_task_func 异常退出, 5秒后重新开启广播
[2026-01-23 14:01:53.882][000000010.475] I/user.ble_server_main 等待5秒后重新尝试...
[2026-01-23 14:01:53.885][000000010.476] I/user.send_data_cbfunc false timer 1 Sat Jan  1 08:00:10 2000
[2026-01-23 14:01:53.890][000000010.476] I/user.ble_timer_app 已停止notify发送定时器
[2026-01-23 14:01:53.895][000000010.477] I/user.ble_timer_app 已停止write发送定时器
[2026-01-23 14:01:54.873][000000011.478] D/airlink slave timeout
[2026-01-23 14:01:58.871][000000015.475] I/user.ble_server_main WiFi关闭，等待WiFi开启...
[2026-01-23 14:02:00.869][000000017.475] I/user.ble_server_main 等待5秒后重新尝试...
[2026-01-23 14:02:05.871][000000022.475] I/user.ble_server_main WiFi关闭，等待WiFi开启...
[2026-01-23 14:02:07.870][000000024.475] I/user.ble_server_main 等待5秒后重新尝试...
[2026-01-23 14:02:12.872][000000029.475] I/user.ble_server_main WiFi关闭，等待WiFi开启...
[2026-01-23 14:02:14.871][000000031.475] I/user.ble_server_main 等待5秒后重新尝试...
[2026-01-23 14:02:19.871][000000036.475] I/user.ble_server_main WiFi关闭，等待WiFi开启...
[2026-01-23 14:02:21.870][000000038.475] I/user.ble_server_main 等待5秒后重新尝试...
[2026-01-23 14:02:23.869][000000040.473] I/pm pm
[2026-01-23 14:02:23.886][000000040.473] I/user.ble_lowpower 发布: WiFi状态 -> 1
[2026-01-23 14:02:23.900][000000040.474] I/user.ble_server_main 收到WiFi状态变化: 1
[2026-01-23 14:02:26.871][000000043.475] D/drv.bt 执行luat_bluetooth_init
[2026-01-23 14:02:26.968][000000043.572] I/user.ble_server_main 广播已成功启动
[2026-01-23 14:02:46.041][000000062.645] I/user.BLE 设备连接成功: 429242B64C70
[2026-01-23 14:02:46.060][000000062.646] I/user.ble_timer_app 已启动notify发送定时器, 间隔: 5000ms
[2026-01-23 14:02:46.067][000000062.647] I/user.ble_timer_app 已启动write发送定时器, 间隔: 6000ms

```