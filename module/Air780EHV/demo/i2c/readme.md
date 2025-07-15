
## 演示功能概述

本例程将使用 I2C 协议读取传感器数据并打印出来温湿度数值。

## 演示硬件环境

1、Air780EHV核心板一块

2、TYPE-C USB数据线一根

3、Air780EHV核心板和数据线的硬件接线方式为

- Air780EHV核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

4、aht10 温湿度传感器一个

[购买连接](https://item.taobao.com/item.htm?abbucket=15&detail_redpacket_pop=true&id=891645785252&ltk2=1751939170154m7bqoeqwmea8pnqgf2eih&ns=1&priceTId=2147825717519391446893951e12fd&query=aht10&spm=a21n57.1.hoverItem.11&utparam=%7B%22aplus_abtest%22%3A%223f8c6c40d54be7cad7b986e73347904b%22%7D&xxc=taobaoSearch)

5、核心板和温湿度传感器连接方式


| aht10 引脚 | Air780EHV 引脚 | 功能             |
|-------------|----------------|------------------|
| GND         | GND            | 地               |
| VDD         | 3.3V           | 逻辑电源         |
| SCL         | I2C1_SCL        | 时钟信号 (SPI)   |
| SDA         | I2C1_SDA        | 数据输入 (SPI)   |



## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHV V2007版本固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)（测试使用V2007 固件）

## 演示核心步骤

1、搭建好演示硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录成功后，自动开机运行

4、终端循环打印获取的温湿度信息。
