## 功能模块介绍

1、main.lua：主程序入口；

2、fastlz_app.lua：如何对数据压缩解压；

## 演示功能概述

1、创建一个task；

2、演示如何对数据压缩解压；


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

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

3.luatos 需要的脚本和资源文件

- 脚本和资源文件[点击此处查看与下载](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/fastlz)

-  lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

准备好软件环境之后，接下来查看[如何烧录项目文件到 Air1601 开发板中](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1601开发板 中。

**API** **介绍**

本教程用到的API接口参考：[fastlz](https://docs.openluat.com/osapi/core/fastlz/)

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，就表示运行成功：

``` lua
[2026-03-03 13:44:51.134][LTOS/N][000000000.015]:I/user.原始数据108长度字符串
[2026-03-03 13:44:51.136][LTOS/N][000000000.015]:I/user.原始数据长度 108
[2026-03-03 13:44:51.139][LTOS/N][000000000.016]:I/user.压缩等级1：压缩后的数据长度 47
[2026-03-03 13:44:51.146][LTOS/N][000000000.016]:I/user.压缩等级1：解压后的的数据长度 108
[2026-03-03 13:44:51.148][LTOS/N][000000000.016]:I/user.压缩等级1：解压后的数据与原始数据相同
[2026-03-03 13:44:51.150][LTOS/N][000000000.017]:I/user.压缩等级2：压缩后的数据长度 47
[2026-03-03 13:44:51.152][LTOS/N][000000000.017]:I/user.压缩等级2：解压后的数据长度 108
[2026-03-03 13:44:51.154][LTOS/N][000000000.017]:I/user.压缩等级2：解压后的数据与原始数据相同
[2026-03-03 13:44:51.158][LTOS/N][000000000.017]:I/user.原始数据文件读取2K数据
[2026-03-03 13:44:51.159][LTOS/N][000000000.017]:I/user.原始数据长度 2048
[2026-03-03 13:44:51.163][LTOS/N][000000000.018]:I/user.压缩等级1：压缩后的数据长度 128
[2026-03-03 13:44:51.166][LTOS/N][000000000.018]:I/user.压缩等级1：解压后的的数据长度 2048
[2026-03-03 13:44:51.168][LTOS/N][000000000.018]:I/user.压缩等级1：解压后的数据与原始数据相同
[2026-03-03 13:44:51.171][LTOS/N][000000000.019]:I/user.压缩等级2：压缩后的数据长度 116
[2026-03-03 13:44:51.173][LTOS/N][000000000.019]:I/user.压缩等级2：解压后的数据长度 2048
[2026-03-03 13:44:51.176][LTOS/N][000000000.019]:I/user.压缩等级2：解压后的数据与原始数据相同

```
