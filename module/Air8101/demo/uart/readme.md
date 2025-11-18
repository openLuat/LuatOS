## 演示模块概述

1、main.lua：主程序入口；

2、uart_manger：串口功能管理模块,用于管理以下五种串口应用场景功能；

3、simple_uart：简易串口，小数据字符串收发；

4、high_volume_uart：大数据收发串口；

5、485_uart：485串口；

6、multiple_uart：多串口；

## 演示功能概述

使用Air8101核心板测试串口相关功能。

## 演示硬件环境

![](https://docs.openluat.com/air8101/luatos/app/multinetwork/4G/image/LzuBbS3NxoVu34x4dj7c3d04nDb.jpg)
Air8101 核心板一块 + TYPE-C USB 数据线一根 + USB转串口数据线一根

- Air8101 核心板通过TYPE-C USB口供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接核心板的UART1_TX，绿线连接核心板的UART1_RX，黑线连接核心板的GND，另外一端连接电脑USB口；

3、不同功能测试时的接线说明:

- 单串口,simple_uart和high_volume_uart 接串口1

| Air8101核心板     | MCU或者串口板 |
| ----------------- | ------------- |
| 11/u1tx           | UART_RXD      |
| 12/u1rx           | UART_TXD      |
| GND               | GND           |

![](https://docs.openluat.com/air8101/luatos/app/driver/uart/image/Air8101-uart1.jpg)

- 多串口,multiple_uart 接串口1,串口2

串口2:

| Air8101核心板     | MCU或者串口板 |
| ----------------- | ------------- |
| 73/VSY            | UART_RXD      |
| 3/HSY             | UART_TXD      |
| GND               | GND           |

串口1:

| Air8101核心板     | MCU或者串口板 |
| ----------------- | ------------- |
| 11/u1tx           | UART_RXD      |
| 12/u1rx           | UART_TXD      |
| GND               | GND           |

![](https://docs.openluat.com/air8101/luatos/app/driver/uart/image/Air8101-uart2.jpg)

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1006版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上，最新发布的固件都可以）

3、PC端的串口工具，例如SSCOM、LLCOM等都可以；

## 演示核心步骤

1、搭建好硬件环境

2、uart_manger.lua 中加载需要用的功能模块，五个功能模块同时只能选择一个使用，其他的注释。

3、Luatools 烧录内核固件和修改后的 demo 脚本代码

4、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印串口初始化和串口收发数据等相关信息。

5、simple_uart：
![](https://docs.openluat.com/air8101/luatos/app/driver/uart/image/8101-uart1.png)

6、high_volume_uart：
![](https://docs.openluat.com/air8101/luatos/app/driver/uart/image/8101-uart6.png)

7、multiple_uart
![](https://docs.openluat.com/air8101/luatos/app/driver/uart/image/8101-uart3.png)

8、485_uart：
![](https://docs.openluat.com/air8101/luatos/app/driver/uart/image/PluHbmrGmolVZ1xLruwcBWR7njd.png)
 