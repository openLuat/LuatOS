## 演示模块概述

1、main.lua：主程序入口；

2、uart_manger：串口功能管理模块,用于管理以下五种串口应用场景功能；

3、simple_uart：简易串口，小数据字符串收发；

4、high_volume_uart：大数据收发串口；

5、multiple_uart：多串口；

## 演示功能概述

使用Air1601开发板测试串口相关功能。

## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

3、不同功能测试时的接线说明:

- 单串口,simple_uart和high_volume_uart 接串口1
- 多串口,multiple_uart 接串口1,串口2

| Air1601开发板 | MCU或者串口板 |
| ----------------- | ------------- |
| UART1_TXD         | UART_RXD      |
| UART1_RXD         | UART_TXD      |
| GND               | GND           |

![](https://docs.openluat.com/Air1601/luatos/app/driver/uart/image/image-20250525152816553.png)


串口2:

| Air1601整机开发板 | MCU或者串口板 |
| ----------------- | ------------- |
| UART2_TXD         | UART_RXD      |
| UART2_RXD         | UART_TXD      |
| GND               | GND           |

![](https://docs.openluat.com/osapi/core/image/Multi-serial_port_wiring.jpg)


## 演示软件环境

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/) ；

准备好软件环境之后，接下来查看[如何烧录项目文件到 Air1601 开发板中](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1601开发板 中。

## 演示核心步骤

1、搭建好硬件环境

2、uart_manger.lua 中加载需要用的功能模块，三个功能模块同时只能选择一个使用，其他的注释。

3、Luatools 烧录内核固件和修改后的 demo 脚本代码

4、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印串口初始化和串口收发数据等相关信息。

5、simple_uart：
![](https://docs.openluat.com/osapi/core/image/uart-1.png)

6、high_volume_uart：
![](https://docs.openluat.com/osapi/core/image/uart-2.png)

7、multiple_uart
![](https://docs.openluat.com/osapi/core/image/uart-3.png)
