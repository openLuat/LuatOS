
## 演示功能概述

本文演示如何在 Air780EHV 核心板上实现 LCD 屏幕显示图片、字符和画线，框，圆的功能。

## 演示硬件环境

1、Air780EHV核心板一块

2、TYPE-C USB数据线一根

3、Air780EHV核心板和数据线的硬件接线方式为

- Air780EHV核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

4、ST7796 LCD 屏幕 一块

5、核心板和ST7796 LCD 屏幕连接方式

| ST7796 引脚 | Air780EHV 引脚 | 功能             |
|-------------|----------------|------------------|
| GND         | GND            | 地               |
| VDD         | 3.3V           | 逻辑电源         |
| SCL         | LCD_CLK        | 时钟信号 (SPI)   |
| SDA         | LCD_SDA        | 数据输入 (SPI)   |
| RES         | LCD_RES        | 复位控制         |
| RS          | LCD_RS         | 数据/命令选择    |
| CS          | LCD_CS         | 片选信号 (SPI)   |


## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHV V2007版本固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)（测试使用V2007 固件）

## 演示核心步骤

1、搭建好演示硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录成功后，自动开机运行

4、ST7796 LCD 屏幕显示的内容每间隔3秒切换一次。
