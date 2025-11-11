## 功能模块介绍

1、main.lua：主程序入口，用于选择加载服务器或客户端模块；

2、iperf_server.lua：iperf服务器模块，用于初始化网络并启动iperf服务器；

3、iperf_client.lua：iperf客户端模块，用于初始化网络并连接到服务器进行测试；

## 演示功能概述

本项目演示如何使用Air780EHM/Air780EHV/Air780EGH核心板进行网络性能测试。通过修改后的代码，可以实现两台Air780EHM/Air780EHV/Air780EGH核心板通过路由器连接，进行网络吞吐量测试。

1、支持以下功能特性：

- 支持DHCP客户端模式，自动从路由器获取IP地址
- 服务器模式和客户端模式分离，可在不同设备上运行
- 增强的错误处理和超时机制
- 清晰的日志输出，便于调试和监控
- 带宽自动计算并以Mbps显示

## 演示硬件环境

![](https://docs.openluat.com/air780ehv/luatos/common/hwenv/image/Air780EHV.png)

1、两台Air780EHM/Air780EHV/Air780EGH核心板

2、一台路由器（支持DHCP功能）

3、网线两根

4、Air780EHM/Air780EHV/Air780EGH核心板和数据线的硬件接线方式为

- Air780EHM/Air780EHV/Air780EGH核心板通过TYPE-C USB口供电；

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者5V管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

5、AirETH_1000配件板一块，Air780EHM/Air780EHV/Air780EGH核心板和AirETH_1000配件板的硬件接线方式为:

| Air780EHM/Air780EHV/Air780EGH核心板  |  AirETH_1000配件板 |
| --------------- | ----------------- |
| 3V3             | 3.3v              |
| gnd             | gnd               |
| 86/SPI0CLK      | SCK               |
| 83/SPI0CS       | CSS               |
| 84/SPI0MISO     | SDO               |
| 85/SPI0MOSI     | SDI               |
| 107/GPIO21      | INT               |

## 演示软件环境

1、Luatools下载调试工具

2、固件获取地址：

[Air780EHM 固件](https://docs.openluat.com/air780epm/luatos/firmware/version/#air780ehmluatos)

[Air780EHV 固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

[Air780EGH 固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境

2、配置服务器端（一台核心板+AirETH_1000配件板）

   a. 确保`main.lua`中已启用服务器模块，禁用客户端模块：
   ```lua
   -- 加载 iperf 服务器测试模块
   require "iperf_server"

   -- 加载 iperf 客户端测试模块
   -- require "iperf_client"
   ```

   b. 烧录到一台Air780EHM/Air780EHV/Air780EGH核心板

   c. 连接AirETH_1000配件板到路由器的LAN口

   d. 启动核心板，它将自动从路由器获取IP地址并启动iperf服务器

3、配置客户端（另一台核心板+AirETH_1000配件板）

   a. 修改`iperf_client.lua`文件中的服务器IP地址为服务器核心板的实际IP地址：

   ```lua
   -- 配置服务器IP地址（需要根据实际服务器IP进行修改）
   local SERVER_IP = "192.168.1.3"  -- 这里需要修改为实际的服务器IP地址
   ```

   b. 确保`main.lua`中已启用客户端模块，禁用服务器模块：

   ```lua
   -- 加载 iperf 服务器测试模块
   -- require "iperf_server"

   -- 加载 iperf 客户端测试模块
   require "iperf_client"
   ```

   c. 烧录到另一台Air780EHM/Air780EHV/Air780EGH核心板

   d. 连接AirETH_1000配件板到路由器的LAN口

   e. 启动核心板，它将自动从路由器获取IP地址并尝试连接到服务器

## 查看测试结果

测试启动后，可以通过Luatools工具查看测试日志。客户端将显示实时的测试报告，包括数据量、持续时间和带宽（以Mbps为单位）。

```lua
2025-11-06 17:02:24.658][000000013.298] I/user.iperf测试 测试进行中...
[2025-11-06 17:02:24.675][000000013.314] D/iperf iperf正常结束, type 1
[2025-11-06 17:02:24.677][000000013.314] D/lwiperf iperf_free 88 c1d553c
[2025-11-06 17:02:24.678][000000013.316] D/iperf report bytes 5989824 ms_duration 10002 bandwidth 4784 kbps
[2025-11-06 17:02:24.680][000000013.317] I/user.iperf报告 数据量: 5989824 bytes, 持续时间: 10002 ms, 带宽: 0.04 Mbps
```

## 注意事项

1、确保两台核心板和电脑都连接到同一个路由器，并且路由器已启用DHCP功能

2、服务器的IP地址需要在客户端配置文件中正确设置，否则客户端将无法连接

3、默认情况下，服务器在端口5001上监听连接请求

4、测试默认持续2分钟后自动结束

## 常见问题排查

1、无法连接到服务器
   - 确认服务器IP地址是否正确
   - 检查两台设备是否在同一网段
   - 检查网线连接是否牢固
