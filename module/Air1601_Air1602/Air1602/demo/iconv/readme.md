## 功能模块介绍

1、main.lua：主程序入口；

2、iconv.lua：字符编码转换模块，提供多种字符编码之间的相互转换功能；


## 演示功能概述

本demo演示的功能为：
提供多种字符编码之间的相互转换功能，支持以下编码转换：
1. Unicode小端(ucs2)与GB2312编码互转
2. Unicode大端(ucs2be)与GB2312编码互转
3. Unicode小端(ucs2)与UTF8编码互转
4. Unicode大端(ucs2be)与UTF8编码互转
5. GB2312 编码与 UTF-8 编码之间的转换。

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

## 演示操作步骤

1、搭建好硬件环境

2、将demo烧录到模组中

3、可以看到如下输出：
```lua
[2025-10-27 18:28:17.553][000000005.822] D/mobile NETIF_LINK_ON -> IP_READY
[2025-10-27 18:28:17.614][000000005.932] D/mobile TIME_SYNC 0
[2025-10-27 18:28:21.797][000000010.217] ucs2ToGb2312
[2025-10-27 18:28:21.850][000000010.218] gb2312  code： CED2 4
[2025-10-27 18:28:21.927][000000010.218] gb2312ToUcs2
[2025-10-27 18:28:21.990][000000010.218] unicode little-endian code:1162
[2025-10-27 18:28:22.050][000000010.219] ucs2beToGb2312
[2025-10-27 18:28:22.109][000000010.219] gb2312 code :CED2
[2025-10-27 18:28:22.169][000000010.219] gb2312ToUcs2be
[2025-10-27 18:28:22.227][000000010.220] unicode big-endian code :6211
[2025-10-27 18:28:22.294][000000010.220] ucs2ToUtf8
[2025-10-27 18:28:22.349][000000010.220] utf8  code:E68891
[2025-10-27 18:28:22.400][000000010.220] utf8ToGb2312
[2025-10-27 18:28:22.452][000000010.221] gb2312 code:CED2
[2025-10-27 18:28:22.510][000000010.221] gb2312ToUtf8

```