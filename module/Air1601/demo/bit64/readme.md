## 功能模块介绍

1、main.lua：主程序入口；

2、bit64_app.lua：32 位系统上对 64 位数据的基本算术运算和逻辑运算；

## 演示功能概述

1、创建一个task；

2、演示在 32 位系统上对 64 位数据的基本算术运算和逻辑运算；

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

在开始实践本示例之前，先筹备一下软件环境：

1、烧录工具：[Luatools 下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)

2、内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

3、luatos 需要的脚本和资源文件

- 脚本文件：[https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/bit64](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/bit64)

- lib脚本文件：使用Luatools烧录时，勾选 添加默认lib 选项，使用默认lib脚本文件

准备好软件环境之后，接下来查看[如何烧录项目文件到Air1601开发板](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1601开发板中。

###  API 介绍

bit64 库：[https://docs.openluat.com/osapi/core/bit64/](https://docs.openluat.com/osapi/core/bit64/)

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，就表示运行成功：

``` lua
[2026-03-02 11:57:28.682][LTOS/N][000000000.013]:I/user.main luatos_bit64_app 001.000.000
[2026-03-02 11:57:28.682][LTOS/N][000000000.016]:I/bit64_app.lua:24 bit64 演示
[2026-03-02 11:57:28.682][LTOS/N][000000000.017]:I/bit64_app.lua:31 i32 123456 0x1e240
[2026-03-02 11:57:28.698][LTOS/N][000000000.017]:I/bit64_app.lua:36 i32 12345678 0xbc614e
[2026-03-02 11:57:28.698][LTOS/N][000000000.017]:I/bit64_app.lua:40 i32 -12345678 0xff439eb2
[2026-03-02 11:57:28.698][LTOS/N][000000000.017]:I/bit64_app.lua:44 f32 12.342340000000 12.342340000000
[2026-03-02 11:57:28.714][LTOS/N][000000000.018]:I/bit64_app.lua:48 f32 -12.342340000000 -12.342340000000
[2026-03-02 11:57:28.722][LTOS/N][000000000.018]:I/bit64_app.lua:58 87654321+12345678= 99999999
[2026-03-02 11:57:28.725][LTOS/N][000000000.018]:I/bit64_app.lua:59 87654321-12345678= 75308643
[2026-03-02 11:57:28.729][LTOS/N][000000000.018]:I/bit64_app.lua:60 87654321*12345678= 1082152022374638
[2026-03-02 11:57:28.729][LTOS/N][000000000.018]:I/bit64_app.lua:61 87654321/12345678= 7
[2026-03-02 11:57:28.729][LTOS/N][000000000.019]:I/bit64_app.lua:66 87654321+1234567= 88888888
[2026-03-02 11:57:28.745][LTOS/N][000000000.019]:I/bit64_app.lua:67 87654321-1234567= 86419754
[2026-03-02 11:57:28.745][LTOS/N][000000000.019]:I/bit64_app.lua:68 87654321*1234567= 108215132114007
[2026-03-02 11:57:28.745][LTOS/N][000000000.019]:I/bit64_app.lua:69 87654321/1234567= 71
[2026-03-02 11:57:28.761][LTOS/N][000000000.019]:I/bit64_app.lua:75 87654.326+12345= 99999.326000000
[2026-03-02 11:57:28.761][LTOS/N][000000000.019]:I/bit64_app.lua:76 87654.326+12345= 99999.326000
[2026-03-02 11:57:28.761][LTOS/N][000000000.020]:I/bit64_app.lua:77 87654.326-12345= 75309.326000
[2026-03-02 11:57:28.777][LTOS/N][000000000.020]:I/bit64_app.lua:78 87654.326*12345= 1.082093e+09
[2026-03-02 11:57:28.782][LTOS/N][000000000.020]:I/bit64_app.lua:79 87654.326/12345= 7.100391
[2026-03-02 11:57:28.782][LTOS/N][000000000.020]:I/bit64_app.lua:84 float 87654.32+12345.67= 99999.990000000
[2026-03-02 11:57:28.782][LTOS/N][000000000.020]:I/bit64_app.lua:85 double 87654.32+12345.67= 99999.990000
[2026-03-02 11:57:28.793][LTOS/N][000000000.021]:I/bit64_app.lua:86 double to float 87654.32+12345.67= 99999.990000000
[2026-03-02 11:57:28.793][LTOS/N][000000000.021]:I/bit64_app.lua:87 87654.32-12345.67= 75308.650000
[2026-03-02 11:57:28.793][LTOS/N][000000000.021]:I/bit64_app.lua:88 87654.32*12345.67= 1.082151e+09
[2026-03-02 11:57:28.793][LTOS/N][000000000.021]:I/bit64_app.lua:89 87654.32/12345.67= 7.100005
[2026-03-02 11:57:28.793][LTOS/N][000000000.022]:I/bit64_app.lua:90 double to int64 87654.32/12345.67= 7
[2026-03-02 11:57:28.809][LTOS/N][000000000.022]:I/bit64_app.lua:96 0xc0000000 << 8 = 0xc000000000
[2026-03-02 11:57:28.809][LTOS/N][000000000.022]:I/bit64_app.lua:97 0xc000000000+2= 0xc000000002
[2026-03-02 11:57:28.809][LTOS/N][000000000.022]:I/bit64_app.lua:98 0xc000000000-2= 0xbffffffffe
[2026-03-02 11:57:28.825][LTOS/N][000000000.022]:I/bit64_app.lua:99 0xc000000000*2= 0x18000000000
[2026-03-02 11:57:28.825][LTOS/N][000000000.022]:I/bit64_app.lua:100 0xc000000000/2= 0x6000000000
[2026-03-02 11:57:28.825][LTOS/N][000000000.023]:I/user.data 827E1601D711030000 18
[2026-03-02 11:57:28.840][LTOS/N][000000000.023]:I/user.data 864040064024194
[2026-03-02 11:57:28.840][LTOS/N][000000000.023]:I/user.work time 当前时间 0
[2026-03-02 11:57:28.840][LTOS/N][000000000.024]:D/heap skip ROM free 14700078
[2026-03-02 11:57:28.857][LTOS/N][000000000.024]:D/heap skip ROM free 14700cee
[2026-03-02 11:57:29.381][LTOS/N][000000001.024]:I/user.work time 当前时间 1
[2026-03-02 11:57:30.382][LTOS/N][000000002.024]:I/user.work time 当前时间 2

```
