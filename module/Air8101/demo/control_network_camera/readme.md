## 功能模块介绍

1、main.lua：主程序入口；

2、init_app.lua：初始化模块，负责加载网络驱动和SD卡挂载功能；

3、cam_control.lua：摄像头控制模块，负责OSD设置、拍照和照片上传；

4、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的三种网卡（WiFi STA网卡、RMII以太网卡、SPI以太网卡）中的任何一种网卡；

5、sdcard_mount_app.lua：SD卡挂载功能模块；


## 演示功能概述

### 1.1 网络摄像头控制系统概述

网络摄像头控制系统是一种基于Air8101模组的轻量级摄像头控制解决方案，通过连接WiFi网络或以太网，实现对网络摄像头的OSD文字显示设置、拍照和照片上传功能。

### 1.2 系统工作原理

设备启动后，自动连接指定的网络（WiFi或以太网），初始化SD卡挂载。然后控制网络摄像头，设置OSD文字显示并进行拍照操作，根据SD卡状态智能选择保存路径，最后将照片上传到测试服务器。

### 1.3 核心功能特性

- **多网络支持**：支持WiFi STA和以太网两种连接方式
- **智能路径选择**：SD卡挂载时保存到`/sd/`，未挂载时保存到`/luadb/`
- **自动照片上传**：拍照后自动上传到air32.cn测试服务器
- **OSD控制**：设置摄像头的OSD文字显示内容和位置
- **远程拍照**：控制网络摄像头进行拍照操作

本示例基于合宙 Air8101 模组，演示 **网络摄像头控制** 的完整实现流程。设备连接到网络后，自动控制网络摄像头进行OSD设置、拍照和照片上传操作。

#### 1、系统启动流程

- **初始化阶段**：系统启动后，自动连接指定的网络（WiFi或以太网）
- **环境准备**：联网成功后，自动挂载SD卡，为拍照功能做准备
- **摄像头控制**：设置摄像头的OSD文字显示内容和位置
- **拍照操作**：控制网络摄像头进行拍照，智能选择保存路径
- **照片上传**：将拍摄的照片自动上传到测试服务器

#### 2、网络连接配置

支持多种网络连接方式：

- **WiFi STA模式**：使用 wlan.connect() 连接指定的WiFi网络
- **以太网模式(RMII)**：通过RMII接口外挂PHY芯片的以太网卡
- **以太网模式(SPI)**：通过SPI外挂CH390H芯片的以太网卡

#### 3、SD卡智能管理

- **智能路径选择**：自动检测SD卡状态，挂载时使用`/sd/`，未挂载时使用`/luadb/`
- **文件自动清理**：照片上传成功后自动删除本地文件
- **空间信息查询**：自动获取SD卡可用空间信息

#### 4、摄像头控制功能

- **OSD设置**：设置摄像头的OSD文字显示内容和位置
- **拍照功能**：控制摄像头进行拍照，照片保存为`/sd/get_photo.jpeg`或`/luadb/get_photo.jpeg`
- **照片上传**：自动将照片上传到`http://upload.air32.cn/api/upload/jpg`

#### 5、运行效果

- **网络连接成功**：设备成功连接到指定的网络
- **SD卡智能管理**：根据挂载状态自动选择保存路径
- **OSD设置完成**：摄像头的OSD文字显示设置成功
- **拍照成功**：照片成功保存并自动上传到测试服务器

## 演示硬件环境

![](https://docs.openluat.com/air8101/luatos/app/driver/sdcard/image/68ba9d68b71c7d1661a1fced38b3c1a2.jpg)

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、Air8101核心板和数据线的硬件接线方式为：

- Air8101核心板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）
- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；
- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

4、AirMICROSD_1010配件板一个+micro SD卡一张

5、Air8101核心板与AirMICROSD_1010配件板通过杜邦线连接，对应管脚为:

| Air8101/Air6101核心板 | AirMICROSD_1010配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3V3               |
| gnd           | gnd               |
| 65/GPIO2      | spi_clk           |
| 67/GPIO4      | spi_mosi          |
| 66/GPIO3      | spi_cs            |
| 8/GPIO5       | spi_miso          |

6、可选AirPHY_1000配件板一块，Air8101核心板和AirPHY_1000配件板的硬件接线方式为:

| Air8101核心板 | AirPHY_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3.3v              |
| gnd           | gnd               |
| 5/D2          | RX1               |
| 72/D1         | RX0               |
| 71/D3         | CRS               |
| 4/D0          | MDIO              |
| 6/D4          | TX0               |
| 74/PCK        | MDC               |
| 70/D5         | TX1               |
| 7/D6          | TXEN              |
| 不接          | NC                |
| 69/D7         | CLK               |

7、可选AirETH_1000配件板一块，Air8101核心板和AirETH_1000配件板的硬件接线方式为:

| Air8101核心板 | AirETH_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3.3v              |
| gnd           | gnd               |
| 28/DCLK       | SCK               |
| 54/DISP       | CSS               |
| 55/HSYN       | SDO               |
| 57/DE         | SDI               |
| 14/GPIO8      | INT               |

8、支持OSD功能的网络摄像头一台（目前仅支持大华摄像头）

## 演示软件环境

1、Luatools下载调试工具

2、Air8101固件[Air8101 版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（需确保固件版本≥V2001）

## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单WIFI STA网卡，打开require "netdrv/netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("@PHICOMM_75", "li19760705")，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要RMII以太网卡，打开require "netdrv/netdrv_eth_rmii"，其余注释掉

- 如果需要SPI以太网卡，打开require "netdrv/netdrv_eth_spi"，其余注释掉

3、通过Luatools将本工程代码与固件烧录到Air8101核心板中

4、烧录完成后，给设备上电，观察串口日志确认系统正常启动

系统启动日志示例：

```lua
[2026-03-06 15:45:09.929] luat:U(2090):I/user.main CONTROL_NETWORK_CAMERA 001.000.000
[2026-03-06 15:45:09.960] luat:U(2113):I/user.执行STA连接操作
[2026-03-06 15:45:12.007] luat:D(4165):wlan:STA connected @PHICOMM_75 
[2026-03-06 15:45:12.279] luat:U(4434):I/user.SDCARD 挂载SD卡结果: true
[2026-03-06 15:45:12.279] luat:U(4436):I/user.开始运行OSD操作
[2026-03-06 15:45:12.279] luat:U(4436):I/user.osdsetup 检测到大华摄像头，开始初始化
[2026-03-06 15:45:12.279] luat:U(4438):I/user.元素解析 索引 1 值 1111
[2026-03-06 15:45:12.279] luat:U(4439):I/user.元素解析 索引 2 值 2222
[2026-03-06 15:45:12.279] luat:U(4439):I/user.元素解析 索引 3 值 3333
[2026-03-06 15:45:12.279] luat:U(4440):I/user.元素解析 索引 4 值 4444
[2026-03-06 15:45:12.279] luat:U(4440):I/user.元素解析 索引 5 值 5555
[2026-03-06 15:45:12.292] luat:U(4441):I/user.元素解析 索引 6 值 6666
[2026-03-06 15:45:12.292] luat:D(4449):net:adapter 2 connect 192.168.1.108:80 TCP
[2026-03-06 15:45:16.708] luat:U(8863):I/user.DHosd 第一次请求http，code： 401 table: 609B1CB8
[2026-03-06 15:45:16.708] luat:U(4303):l/user.DigestAuth 鉴权信息重组完成
[2026-03-06 15:45:16.708] luat:U(8863):I/user.DHosd 第二次请求http，code:200 OK
[2026-03-06 15:45:17.695] luat:U(9864):I/user.开始运行抓图操作
[2026-03-06 15:45:17.695] luat:U(9865):I/user.getphoto 检测到大华摄像头，开始初始化
[2026-03-06 15:45:17.695] luat:U(9865):I/user.DHPicture 开始执行
[2026-03-06 15:45:17.695] luat:D(9869):net:adapter 2 connect 192.168.1.108:80 TCP
[2026-03-06 15:45:18.695] luat:U(5406):/user.DHPicture 第一次请求http,code: 401 table: 609AFFBO
[2026-03-06 15:45:18.695] luat:U(5408):l/user.DigestAuth 鉴权信息重组完成
[2026-03-06 15:45:18.695] luat:U(5408):/user.DHPicture 鉴权信息重组完成
[2026-03-06 15:45:18.695] luat:U(8224):l/user.DHPicture 第二次请求http，code: 200
[2026-03-06 15:45:19.413] luat:U(8256):l/user.DHpicture 拍照完成
[2026-03-06 15:45:19.413] luat:U(8256):I/user.照片读取成功 文件大小: 102400 字节 路径: /sd/get_photo.jpeg
[2026-03-06 15:45:19.413] luat:U(8256):I/user.照片上传结果 HTTP状态码: 200
[2026-03-06 15:45:19.413] luat:U(8256):I/user.照片上传成功 可在 https://www.air32.cn/upload/data/jpg/ 查看
[2026-03-06 15:45:19.413] luat:U(8256):I/user.本地照片文件已删除 路径: /sd/get_photo.jpeg
```

5、拍照完成后，照片会根据SD卡状态智能选择保存路径，上传成功后自动删除本地文件

## 系统参数说明

### WiFi参数

- SSID：@PHICOMM_75（可在netdrv/netdrv_wifi.lua中修改）
- 密码：li19760705（可在netdrv/netdrv_wifi.lua中修改）

### 摄像头参数

- 品牌：Dhua（大华）
- IP地址：192.168.1.108（可在cam_control.lua中修改）
- 通道号：0（OSD设置），1（拍照）
- OSD内容：1111|2222|3333|4444|5555|6666（可在cam_control.lua中修改）
- OSD位置：X=0, Y=2000（可在cam_control.lua中修改）

### 存储参数

- 照片路径：/sd/get_photo.jpeg 或 /luadb/get_photo.jpeg（根据SD卡状态智能选择）
- 存储介质：SD卡（需FAT32格式）或内部存储

## 注意事项

1、确保Air8101核心板和网络摄像头连接同一网络（WiFi或以太网）

2、如需修改WiFi名称、密码，请修改netdrv/netdrv_wifi.lua中的相关参数；如需修改摄像头参数，请修改cam_control.lua中的相关参数

3、拍照前系统会自动检测SD卡状态，智能选择保存路径（SD卡挂载时保存到`/sd/`，未挂载时保存到`/luadb/`）

4、OSD文字内容需用竖线分隔，格式如"1111|2222|3333|4444|5555|6666"
