## 功能模块介绍：

1、main.lua：主程序入口；

2、rtc_app.lua：无网络时初始化并每秒打印东八区本地时间与 UTC 时间；有网络时等待 NTP 授时后，同样每秒打印更新后的东八区本地时间与 UTC 时间；

## 演示功能概述：

1、第一种场景演示：无网络情况下，rtc时钟初始化并每秒打印东八区本地时间与 UTC 时间。

2、第二种场景演示：连接上网络后，等待 NTP 授时后每秒打印更新后的东八区本地时间与 UTC 时间。

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

本demo默认联网方式用的是SPI_以太网接口，以太网功能开关设置说明

- `V_LAN` 电源开关：拨至 `ON`，为以太网 PHY 芯片供电。
- `U5`（SPI/ETH 通道拨码开关）：所有通道拨向左侧"ON"，打开以太网，以太网使用 `CS1 (GPIO14)` 作为片选。
- `S15`（WAKEUP/LAN_INT 中断开关）：
  - 单独使用以太网时：拨至 `ON`，连接 `WAKEUP` 信号到 `LAN_INT`，启用以太网中断功能。
  - 与触摸（TP）同时使用时：拨至 `OFF`，断开以太网中断，将 `WAKEUP` 信号留给 TP 使用。

![](https://docs.openluat.com/air1601/luatos/app/common/rtc/image/spi_lan.png)

使用其它网络接线方式请参考：[Air1601开发板使用说明](https://docs.openluat.com/air1601/product/shouce/#air1601_2)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、网线一根，网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

4、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

## 演示软件环境

1、 Luatools下载调试工具

2、 固件版本：本demo开发测试时使用的固件为[LuatOS-SoC_V1012_Air1601_101.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码rtc_app.lua中，按照自己的需求启用对应的task函数

4、Luatools烧录内核固件和修改后的demo脚本代码

5、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印ntp时间同步成功、本地时间以及RTC时间等信息，如下log显示： 

选择运行rtc_task2()函数，打印日志如下：

```lua
[2026-04-27 16:54:14.137][LTOS/N][000000000.053]:I/user.rtc.timezone() 32
[2026-04-27 16:54:14.139][LTOS/N][000000000.053]:I/user.rtc设置后时间 Wed Oct 29 03:10:53 2025
[2026-04-27 16:54:16.021][LTOS/N][000000002.023]:I/user.os.date() Mon Apr 27 16:54:09 2026
[2026-04-27 16:54:16.026][LTOS/N][000000002.023]:I/user.循环rtc时间 {"year":2026,"min":54,"hour":8,"mon":4,"sec":9,"day":27}
[2026-04-27 16:54:16.937][LTOS/N][000000003.024]:I/user.os.date() Mon Apr 27 16:54:10 2026
[2026-04-27 16:54:16.940][LTOS/N][000000003.024]:I/user.循环rtc时间 {"year":2026,"min":54,"hour":8,"mon":4,"sec":10,"day":27}
```

选择运行rtc_task1()函数，打印日志如下：

```lua
[2026-04-27 16:49:49.964][LTOS/N][000000000.053]:I/user.rtc.timezone() 32
[2026-04-27 16:49:49.968][LTOS/N][000000000.054]:I/user.rtc初始时间 {"year":2025,"min":10,"hour":8,"mon":10,"sec":53,"day":28}
[2026-04-27 16:49:49.971][LTOS/N][000000000.054]:I/user.rtc设置后的本地时间 Tue Oct 28 16:10:53 2025
[2026-04-27 16:49:49.974][LTOS/N][000000000.054]:I/user.os.date() Tue Oct 28 16:10:53 2025
[2026-04-27 16:49:49.979][LTOS/N][000000000.055]:I/user.循环rtc时间 {"year":2025,"min":10,"hour":8,"mon":10,"sec":53,"day":28}
```

