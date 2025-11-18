## 演示模块概述

1、main.lua：主程序入口；

2、uart_manger：串口功能管理模块,用于管理以下五种串口应用场景功能；

3、simple_uart：简易串口，小数据字符串收发；

4、high_volume_uart：大数据收发串口；

5、485_uart：485串口；

6、multiple_uart：多串口；

7、usb_uart：USB虚拟串口；

8、uart_mux：动态切换串口引脚复用

## 演示功能概述

使用Air780EPM开发板测试串口相关功能。

## 演示硬件环境

![](https://docs.openluat.com/air780epm/luatos/app/driver/eth/image/RFSvb75NRoEWqYxfCRVcVrOKnsf.jpg)

1、Air780EPM V1.3版本开发板一块：

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air780EPM V1.3版本开发板和数据线的硬件接线方式为：

- Air780EPM V1.3版本开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接开发板的UART_TX，绿线连接开发板的UART_RX，黑线连接核心板的GND，另外一端连接电脑USB口；

3、不同功能测试时的接线说明:

- 单串口,simple_uart和high_volume_uart 接串口1

| Air780EPM开发板 | MCU或者串口板 |
| ----------------- | ------------- |
| UART1_TXD         | UART_RXD      |
| UART1_RXD         | UART_TXD      |
| GND               | GND           |

![](https://docs.openluat.com/air780epm/luatos/app/driver/uart/image/uart-2.png)

- 485串口,485_uart 接485-A,B

| Air780EPM开发板 | MCU或者串口板 |
| ----------------- | ------------- |
| 485-A             | 485-A         |
| 485-B             | 485-B         |
| GND               | GND           |


![](https://docs.openluat.com/air780epm/luatos/app/driver/uart/image/780EPM-V1.3.jpg)

- 多串口,multiple_uart 接串口1,串口2

串口2:

| Air780EPM开发板    | MCU或者串口板 |
| ----------------- | ------------- |
| UART2_TX          | UART_RXD      |
| UART2_RX          | UART_TXD      |
| GND               | GND           |

串口1:

| Air780EPM开发板 | MCU或者串口板 |
| ----------------- | ------------- |
| UART1_TXD         | UART_RXD      |
| UART1_RXD         | UART_TXD      |
| GND               | GND           |

![](https://docs.openluat.com/air780epm/luatos/app/driver/uart/image/uart-3.png)

- 串口引脚动态复用

第一组串口2:

| Air780EPM开发板    | MCU或者串口板 |
| ----------------- | ------------- |
| UART2_TX          | UART_RXD      |
| UART2_RX          | UART_TXD      |
| GND               | GND           |

第二组串口2:

| Air780EPM开发板      | MCU或者串口板 |
| ----------------- | ------------- |
| SPI_CLK           | UART_RXD      |
| SPI_MISO          | UART_TXD      |
| GND               | GND           |

![](https://docs.openluat.com/air780epm/luatos/app/driver/uart/image/780EPM-uart-jx.jpg)

- usb虚拟串口,usb_uart 接usb

首先通过带有 DM、DP 的 USB 数据线两端连接 模块 和 Windows10 或者 Windows11 系统的电脑。
然后将模块开机，就可以从电脑的设备管理器中看到端口处多出来 3 个 USB 端口。
找到"USB\VID_19D1&PID_0001&MI_06\7&17910EBA&0&0006"就是用于软件控制串口传输的 USB 虚拟串口。

![](https://docs.openluat.com/air8000/luatos/app/driver/uart/image/Uf82bI0mAov9l1xj2DOcQUbgnZu.png)

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EPM V2016版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)（理论上，最新发布的固件都可以）

3、PC端的串口工具，例如SSCOM、LLCOM等都可以；

## 演示核心步骤

1、搭建好硬件环境

2、uart_manger.lua 中加载需要用的功能模块，五个功能模块同时只能选择一个使用，其他的注释。

3、Luatools 烧录内核固件和修改后的 demo 脚本代码

4、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印串口初始化和串口收发数据等相关信息。

5、simple_uart：
![](https://docs.openluat.com/air780epm/luatos/app/driver/uart/image/780EPM-uart1.png)

6、high_volume_uart：
![](https://docs.openluat.com/air780epm/luatos/app/driver/uart/image/780EPM-uart2.png)

7、multiple_uart
![](https://docs.openluat.com/air780epm/luatos/app/driver/uart/image/780EPM-uart4.png)

8、usb_uart：
![](https://docs.openluat.com/air780epm/luatos/app/driver/uart/image/780EPM-uart3.png)

9、485_uart：
![](https://docs.openluat.com/air780epm/luatos/app/driver/uart/image/uart5.png)
![](https://docs.openluat.com/air780epm/luatos/app/driver/uart/image/uart6.png)

10、uart_mux：
![](https://docs.openluat.com/air780epm/luatos/app/driver/uart/image/780EPM-uart5.png)
