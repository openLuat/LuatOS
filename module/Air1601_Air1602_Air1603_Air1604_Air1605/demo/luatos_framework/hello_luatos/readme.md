
## 演示功能概述

1、创建一个task；

2、在task中的任务处理函数中，每隔一秒钟通过日志输出一次Hello, LuatOS；


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


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air1601/luatos/common/download/)

2、内核固件文件（底层 core 固件文件）：本demo开发测试时使用的固件为[Air6101 V1016 版本固件](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；


## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，每隔1秒输出1次Hello, LuatOS，就表示运行成功：

``` lua
[2026-05-19 15:39:56.322][LTOS/N][000000000.017]:I/user.Hello, LuatOS
[2026-05-19 15:39:57.173][LTOS/N][000000001.017]:I/user.Hello, LuatOS
[2026-05-19 15:39:58.191][LTOS/N][000000002.018]:I/user.Hello, LuatOS
[2026-05-19 15:39:59.176][LTOS/N][000000003.018]:I/user.Hello, LuatOS
[2026-05-19 15:40:00.191][LTOS/N][000000004.018]:I/user.Hello, LuatOS
[2026-05-19 15:40:01.194][LTOS/N][000000005.019]:I/user.Hello, LuatOS
```
