## 功能模块介绍

1、main.lua：主程序入口；

2、httpsrv_start.lua：HTTP服务器实现模块，包含服务器初始化、路由处理、文本发送和WiFi扫描功能；

3、index.html：Web控制界面，提供LED控制按钮、文本发送输入框和WiFi扫描功能；

4、netdrv_device.lua：网络驱动设备功能模块，用于选择和配置合适的网卡模式；

5、netdrv/netdrv_ap.lua：WiFi AP模式网卡驱动，创建WiFi热点；

6、netdrv/netdrv_wifi.lua：WiFi STA模式网卡驱动，连接外部WiFi路由器；

7、netdrv/netdrv_eth_spi.lua：以太网SPI网卡驱动，通过SPI接口连接CH390H芯片实现有线网络连接；

8、netdrv/netdrv_eth_rmii.lua：通过MAC层的RMII接口外挂PHY芯片（LAN8720Ai）的以太网卡驱动，支持AirPHY_1000配件板，实现稳定的有线网络连接；

## 演示功能概述

1、HTTP服务器：创建Web服务器，提供Web控制界面

- 支持四种网卡模式：WiFi AP模式、WiFi STA模式、以太网SPI模式和以太网RMII模式
- HTTP服务器监听80端口，具体IP地址取决于使用的网卡模式：
  - WiFi AP模式：自动创建名为"luatos8888"的WiFi热点，密码为"12345678"，IP地址为192.168.4.1
  - WiFi STA模式：连接外部WiFi路由器，IP地址由路由器DHCP分配
  - 以太网SPI模式：通过网线连接网络，IP地址由路由器DHCP分配
  - 以太网RMII模式：通过网线连接网络，IP地址由路由器DHCP分配
- 支持访问Web控制界面

2、文本发送功能：通过Web界面发送文本数据

- 提供文本发送（/send/text）接口
- 支持在Web界面的输入框中输入文本并发送
- 发送的文本会在设备日志中显示

3、WiFi扫描功能：搜索周围可用的WiFi热点

- 提供开始扫描（/scan/go）接口
- 提供获取扫描结果（/scan/list）接口
- Web界面上有扫描按钮，点击后显示周围WiFi热点列表
- 显示WiFi的SSID和信号强度信息

## 演示硬件环境

1、Air8101核心板一块+可上网的sim卡一张+wifi天线一根：

- 天线装到开发板上

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air8101核心板和数据线的硬件接线方式为：

- Air8101核心板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）
- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 选择网卡模式

本项目支持三种网卡模式，默认使用WiFi AP模式。要切换网卡模式，请按照以下步骤操作：

1、打开 `netdrv_device.lua` 文件

2、取消注释你想要使用的网卡模式对应的require语句，并确保其他模式的require语句保持注释状态

示例：

- 使用WiFi AP模式（默认）：

```lua
-- 加载"WIFI AP网卡"驱动模块（默认启用）
require "netdrv_ap"

-- 加载"WIFI STA网卡"驱动模块
-- require "netdrv_wifi"

-- 加载"通过SPI外挂CH390H芯片的以太网卡"驱动模块
-- require "netdrv_eth_spi"
```

- 使用WiFi STA模式：

```lua
-- 加载"WIFI AP网卡"驱动模块（默认启用）
-- require "netdrv_ap"

-- 加载"WIFI STA网卡"驱动模块
require "netdrv_wifi"

-- 加载"通过SPI外挂CH390H芯片的以太网卡"驱动模块
-- require "netdrv_eth_spi"
```

- 使用以太网SPI模式：

```lua
-- 加载"WIFI AP网卡"驱动模块（默认启用）
-- require "netdrv_ap"

-- 加载"WIFI STA网卡"驱动模块
-- require "netdrv_wifi"

-- 加载"通过SPI外挂CH390H芯片的以太网卡"驱动模块
require "netdrv_eth_spi"
```

- 使用以太网RMII模式：

```lua
-- 加载"WIFI AP网卡"驱动模块（默认启用）
-- require "netdrv_ap"

-- 加载"WIFI STA网卡"驱动模块
-- require "netdrv_wifi"

-- 加载"通过SPI外挂CH390H芯片的以太网卡"驱动模块
-- require "netdrv_eth_spi"

-- 加载"通过MAC层的rmii接口外挂PHY芯片的以太网卡"驱动模块
require "netdrv_eth_rmii"
```

3、如果使用WiFi STA模式，请修改 `netdrv/netdrv_wifi.lua` 文件中的WiFi配置：

```lua
-- 连接WIFI热点，连接结果会通过"IP_READY"或者"IP_LOSE"消息通知
-- 此处前两个参数表示WIFI热点名称以及密码，更换为自己测试时的真实参数
wlan.connect("你的WiFi名称", "你的WiFi密码", 1)
```

## 演示软件环境

1、Luatools下载调试工具

2、Air8101固件[Air8101 版本固件](https://docs.openluat.com/air8101/luatos/firmware/)

## 演示核心步骤

### WiFi AP模式（默认）

1、搭建好硬件环境

2、使用Luatools烧录内核固件和demo脚本代码

3、烧录成功后，设备自动开机运行，创建名为"luatos8888"的WiFi热点（密码：12345678）

4、使用电脑或手机连接到"luatos8888" WiFi热点

5、在浏览器中输入地址：http://192.168.4.1，访问Web控制界面

### WiFi STA模式

1、按照选择网卡模式的说明，配置为WiFi STA模式并设置正确的WiFi名称和密码

2、使用Luatools烧录内核固件和demo脚本代码

3、烧录成功后，设备自动开机运行并尝试连接配置的WiFi路由器

4、通过Luatools日志查看设备获取的IP地址（例如：192.168.1.100）

5、确保你的电脑或手机连接到同一WiFi网络

6、在浏览器中输入设备的IP地址（如http://192.168.1.100），访问Web控制界面

### 以太网SPI模式

1、按照选择网卡模式的说明，配置为以太网SPI模式

2、确保CH390H以太网模块正确连接到Air8000开发板

3、使用网线将以太网模块连接到路由器或网络交换机

4、使用Luatools烧录内核固件和demo脚本代码

5、烧录成功后，设备自动开机运行并尝试通过以太网连接到网络

6、通过Luatools日志查看设备获取的IP地址（例如：192.168.1.101）

7、确保你的电脑连接到同一路由器或网络

8、在浏览器中输入设备的IP地址（如http://192.168.1.101），访问Web控制界面

### 以太网RMII模式

1、按照选择网卡模式的说明，配置为以太网RMII模式

2、确保AirPHY_1000配件板正确连接到Air8101核心板，接线方式如下：

| Air8101核心板 |  AirPHY_1000配件板  |
| ------------ | ------------------ |
|    59/3V3    |         3.3v       |
|     gnd      |         gnd        |
|     5/D2     |         RX1        |
|    72/D1     |         RX0        |
|    71/D3     |         CRS        |
|     4/D0     |         MDIO       |
|     6/D4     |         TX0        |
|    74/PCK    |         MDC        |
|    70/D5     |         TX1        |
|     7/D6     |         TXEN       |
|     不接     |          NC        |
|    69/D7     |         CLK        |

3、硬件连接注意事项：
- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）
- 如果测试发现软件重启，并且日志中出现 "poweron reason 0"，表示供电不足，此时需要通过直流稳压电源对核心板的VIN管脚进行5V供电

4、使用网线将AirPHY_1000配件板连接到路由器或网络交换机

5、使用Luatools烧录内核固件和demo脚本代码

6、烧录成功后，设备自动开机运行，开启PHY芯片供电并初始化以太网卡

7、通过Luatools日志查看设备获取的IP地址（例如：192.168.1.102）

8、确保你的电脑连接到同一路由器或网络

9、在浏览器中输入设备的IP地址（如http://192.168.1.102），访问Web控制界面

## Web控制界面功能

在浏览器访问Web控制界面后，你可以使用以下功能：

- 发送文本消息（会显示在设备日志中）
- 点击WiFi扫描按钮，查看周围可用的WiFi热点列表

```lua
[2025-10-23 23:48:33.725] I/main LuatOS@Air8101 base 25.03 bsp V1004 32bit
[2025-10-23 23:48:33.725] I/main ROM Build: Jun 15 2025 09:58:28
[2025-10-23 23:48:33.725] W/pins /luadb/pins_Air8101.json not exist!!
[2025-10-23 23:48:33.725] D/main loadlibs luavm 1572856 16696 16696
[2025-10-23 23:48:33.725] D/main loadlibs sys   255160 112584 123552
[2025-10-23 23:48:33.725] D/main loadlibs psram 3145728 1840912 2102424
[2025-10-23 23:48:33.725] I/user.main	project name is 	httpsrv_testdemo	version is 	001.000.000
[2025-10-23 23:48:33.725] I/user.执行AP创建操作	luatos8888
[2025-10-23 23:48:33.725] W/netdrv 该netdrv不支持设置dhcp开关
[2025-10-23 23:48:33.725] D/net network ready 3
[2025-10-23 23:48:33.725] D/net 使用223.5.5.5作为默认DNS服务器
[2025-10-23 23:48:33.725] I/user.WIFI	AP热点创建成功
[2025-10-23 23:48:33.725] I/httpsrv http listen at 192.168.4.1:80
[2025-10-23 23:48:33.725] I/user.HTTP	文件服务器已启动
[2025-10-23 23:48:33.725] I/user.HTTP	请连接WiFi: luatos8888 密码: 12345678
[2025-10-23 23:48:33.725] I/user.HTTP	然后访问: http://192.168.4.1/
```

7、通过Luatools工具，可以查看设备的运行日志，包括收到的文本消息和WiFi扫描结果
