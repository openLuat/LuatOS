
## 演示功能概述

使用 Air780EHV 核心板通过 spi 接口驱动 RC522 传感器读取 ic 数据卡数据。

## 演示硬件环境

1、Air780EHV核心板一块

2、TYPE-C USB数据线一根

3、Air780EHV核心板和数据线的硬件接线方式为

- Air780EHV核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

4、rc522 模块一块


5、核心板和rc500模块连接方式

| RC522引脚   | Air780EGH引脚  |说明               |
|------------|----------------|-------------------|
| SDA        | SPL.CS         | 片选信号           |
| SCK        | SPL.CLK        | SPI 时钟信号       |
| MOSI       | SPL.MOSI       | 主设备输出从设备输入 |
| MISO       | SPL.MISO       | 主设备输入从设备输出 |
| RST        | GPIO16         | 复位信号（可自定义）|
| GND        | GND            | 地线               |
| 3.3V       | 3.3V           | 电源（3.3V）       |

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHV V2007版本固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)（测试使用V2007 固件）

## 演示核心步骤

1、搭建好演示硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录成功后，自动开机运行

4、卡片放到读卡区域后可以正常读取卡片信息。
