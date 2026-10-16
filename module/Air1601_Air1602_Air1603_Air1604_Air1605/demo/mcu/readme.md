## 演示模块概述

1、main.lua：主程序入口；

2、mcu_test.lua：MCU功能测试模块；

## 演示功能概述

使用Air1601开发板测试MCU相关功能，包括：

- MCU死机时的处理模式设置
- 唯一ID获取与显示
- 系统tick计数功能测试
- 64位tick计数和差值计算
- 微秒、毫秒、秒级别的时间计数
- 16进制字符串转换输出

## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

## **演示软件环境**

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、通过luatools工具查看下面日志：

```lua
[2026-03-03 14:24:19.111][LTOS/N][000000000.016]:I/user.mcu ticks: 0
[2026-03-03 14:24:19.111][LTOS/N][000000000.016]:I/user.mcu 获取每秒的tick数量: 50
[2026-03-03 14:24:19.111][LTOS/N][000000000.016]:I/user.mcu tick64: 53FE180000000000 ticks per us: 100
[2026-03-03 14:24:19.111][LTOS/N][000000000.017]:D/heap skip ROM free 147001ba
[2026-03-03 14:24:19.111][LTOS/N][000000000.017]:D/heap skip ROM free 147007d9
[2026-03-03 14:24:19.111][LTOS/N][000000000.117]:I/user.mcu dtick64 result: false diff: -10039838
[2026-03-03 14:24:19.127][LTOS/N][000000000.117]:I/user.mcu us: 0 117258
[2026-03-03 14:24:19.127][LTOS/N][000000000.117]:I/user.mcu ms: 0 117
[2026-03-03 14:24:19.127][LTOS/N][000000000.117]:I/user.mcu sec: 0 0
[2026-03-03 14:24:19.127][LTOS/N][000000000.117]:I/user.mcu string 0x2009fffc
```
