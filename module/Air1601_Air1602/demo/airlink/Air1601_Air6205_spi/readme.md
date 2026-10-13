## 功能模块介绍

**Air1601**

1、main.lua：主程序入口，负责项目版本定义、看门狗初始化（超时9秒，每3秒喂狗）、加载 network_airlink 模块并启动系统调度

2、network_airlink.lua：AirLink 多网融合模块，核心功能包括：

   - 通过 SPI2（波特率20M）初始化 AirLink 连接，使 Air1601 外挂 Air6205 实现 WiFi 联网
   - 定时发送设备信息（BSP型号、当前时间）给对端 Air6205 模块
   - 通过 HTTP GET 请求（间隔10秒）测试网络连通性
   - 订阅 AIRLINK_SDATA 事件接收对端数据

**Air6205**

模块内部已经烧录好了固件脚本，只需进行下一步操作即可。

## 演示功能概述

本 demo 演示 Air1601 通过 AirLink over SPI 模式外挂 Air6205 WiFi 模块实现联网功能。

Air1601 相关资料参考：[Air1601/Air1602简介](https://docs.openluat.com/air1601/)

AirLink 通信协议说明参考：[AirLink协议介绍](https://docs.openluat.com/protocols/airlink/)

Air6205 相关资料参考：[Air6205简介](https://docs.openluat.com/air6205/)

## 演示硬件环境

1、Air1601 + Air6205 搭配设计的开发板

2、TYPE-C USB 数据线两根（一根用于 Air1601 烧录程序和日志打印，另一根用于 Air6205 烧录程序和日志打印）

Air1601 与 Air6205 AirLink over SPI 连接方式如下：

| Air1601      | Air6205      | 说明           |
| ------------ | ------------ | -------------- |
| GND          | GND          | 地             |
| SPI2_CLK     | SPI_CLK      | SPI时钟        |
| SPI2_MISO    | SPI_MISO     | SPI主入从出    |
| SPI2_MOSI    | SPI_MOSI     | SPI主出从入    |
| GPIO4        | SPI_CS       | SPI片选        |
| GPIO13       | RDY          | 就绪信号       |
| GPIO12       | WIFI_EN      | WiFi使能（低有效）|

## 演示软件环境

1、[LuaTools软件烧录工具](https://docs.openluat.com/common/Luatools/)

2、Air1601 内核固件：[Air1601固件版本](https://docs.openluat.com/air1601/luatos/firmware/1601_version/)

3、Air6205 内部已经烧录好了固件脚本，只需进行下一步操作即可。

## 演示核心步骤

1、搭建硬件环境

2、修改 network_airlink.lua 中的 WiFi 配置（ssid 和 password）

3、Air1601 烧录内核固件+软件脚本，Air6205 烧录量产固件

4、启动设备，观察日志输出：

Air1601 正常连接后日志示例：

```text
[I/user.发送数据给对端设备] Air1601 xxx 当前airlink状态 true
[I/user.收到AIRLINK_SDATA!!] Air6205 xxx
[I/user.网卡状态] true
[I/user.发起HTTP GET请求] https://httpbin.air32.cn/bytes/2048
[I/user.HTTP请求成功] 响应码 200 响应体长度 2048
```

## 硬件引脚说明

本 demo 使用的 Air1601 引脚配置：

| 功能         | 引脚   | 说明                     |
| ------------ | ------ | ------------------------ |
| SPI2_CS      | GPIO4  | SPI片选信号              |
| SPI2_RDY     | GPIO13 | AirLink就绪信号          |
| WIFI_EN      | GPIO12 | WiFi模组使能（低电平有效）|

## 注意事项

1、Air6205 仅支持 2.4G WiFi，不支持 5G WiFi

2、WiFi 使能引脚 GPIO12 为低电平有效，上电时序：先拉高50ms，再拉低120ms使能

3、SPI 速度默认 20MHz，可根据实际硬件情况调整

4、WiFi 名称和密码请在 network_airlink.lua 中修改 WIFI_SSID 和 WIFI_PASSWORD
