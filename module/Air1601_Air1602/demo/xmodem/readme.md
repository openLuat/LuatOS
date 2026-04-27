
## 演示功能概述
本demo演示的核心功能为：
使用Air1601开发板的UART1连接PC端的串口工具，通过xmodem协议接收文件。

## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

**连线对应表**

| **Air1601开发板** | **USB 转 TTL 线** |
| ----------------- | ----------------- |
| TX1               | uart_rx           |
| RX1               | uart_tx           |
| gnd               | gnd               |

使用 USB 转 TTL 线连接 Air1601开发板的 TX1、RX1 和 GND

![](https://docs.openluat.com/air1601/luatos/app/common/xmodem/image/uart1.png)

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

## 演示软件环境

1、Luatools下载调试工具

2、内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1012_Air1601_101.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。[](https://docs.openluat.com/air8000/luatos/firmware/)

3、PC端的串口工具，例如SSCOM、LLCOM等都可以；


## 演示核心步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

5、打开串口工具，连接上Air1601开发板 UATR1端口，Air8000等待接收到工具发送过来的字符'C'，然后Air1601开发板开始发送数据，工具端接收到数据返回0x06，0x06为xmodem协议的ack值表示正确接收，然后模块返回0x04,0x04为xmodem协议的EOT值，表示传输结束，然后对端发送0x06表示确认结束，Luatools的运行日志输出：

发送脚本区的文件，日志内容如下：
``` lua
[2026-04-23 17:42:26.119][LTOS/N][000000002.470]:I/user.xmodem uart读取到数据: 43 2
[2026-04-23 17:42:26.123][LTOS/N][000000002.470]:I/user.xmodem 发送第 1 包
[2026-04-23 17:42:33.159][LTOS/N][000000009.524]:I/user.xmodem uart读取到数据: 06 2
[2026-04-23 17:42:33.162][LTOS/N][000000009.525]:I/user.xmodem 文件到头了
[2026-04-23 17:42:33.174][LTOS/N][000000009.525]:I/user.Xmodem start
[2026-04-23 17:42:33.180][LTOS/N][000000009.525]:I/user.Xmodem send result true
[2026-04-23 17:42:33.183][LTOS/N][000000009.525]:I/user.Xmodem send success


```

HTTP下载到文件系统区的，再通过xmodem协议发送日志如下：
``` lua
[2026-04-23 17:42:25.747][LTOS/N][000000002.006]:I/user.http success 200
[2026-04-23 17:42:25.750][LTOS/N][000000002.006]:I/user.HTTP receive ok 29
[2026-04-23 17:42:25.754][LTOS/N][000000002.007]:I/user.文件读取 路径:/send.bin 内容:AA BB CC DD 01 02 03 04 05 06
[2026-04-23 17:42:25.757][CAPP/N][000000002.007]:Uart_ChangeBR 347:uart1 波特率 目标 115200 实际 115218
[2026-04-23 17:42:26.119][LTOS/N][000000002.470]:I/user.xmodem uart读取到数据: 43 2
[2026-04-23 17:42:26.123][LTOS/N][000000002.470]:I/user.xmodem 发送第 1 包
[2026-04-23 17:42:33.159][LTOS/N][000000009.524]:I/user.xmodem uart读取到数据: 06 2
[2026-04-23 17:42:33.162][LTOS/N][000000009.525]:I/user.xmodem 文件到头了
[2026-04-23 17:42:33.174][LTOS/N][000000009.525]:I/user.Xmodem start
[2026-04-23 17:42:33.180][LTOS/N][000000009.525]:I/user.Xmodem send result true
[2026-04-23 17:42:33.183][LTOS/N][000000009.525]:I/user.Xmodem send success



```