## 演示功能概述

使用Air1601开发板，本示例主要是展示xxtea核心库的使用，使用xxtea加密算法，对数据进行加密和解密

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

3.准备好软件环境之后，接下来查看[如何烧录项目文件到 Air1601 开发板中](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1601开发板中。

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到整机开发板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

xxtea_encrypt为加密后的字符串，xxtea_decrypt为解密后的字符串，通过16进制展示

```lua
[2025-09-25 12:01:10.767][000000001.449] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:10.777][000000001.449] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:11.055][000000002.450] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:11.064][000000002.450] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:12.053][000000003.451] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:12.061][000000003.451] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:13.105][000000004.478] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:13.113][000000004.479] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:14.080][000000005.480] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:14.089][000000005.480] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:15.079][000000006.481] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:15.090][000000006.481] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:16.089][000000007.482] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:16.098][000000007.482] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:17.091][000000008.483] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:17.100][000000008.483] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24


```

