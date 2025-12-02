## 功能模块介绍：

1. main.lua：主程序入口

2. otp_test.lua：演示otp核心库API的用法，详细逻辑请看otp_test.lua 文件

## 演示功能概述：

### otp_test.lua：

1.读取指定 OTP 区域的数据

2.进入飞行模式，擦除指定的 OTP 区域的数据

3.擦除完成后向该区域写入数据

4.谨慎操作区域加锁(区域加锁后会永久变成只读无法写入)

5.退出飞行模式

## 演示硬件环境：

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/780EHV.jpg)





1. 合宙 Air780EHM/EHV/EGH 核心板一块

2. TYPE-C USB 数据线一根 ，Air780EHM/EHV/EGH 核心板和数据线的硬件接线方式为：
* Air780EHM/EHV/EGH核心板通过 TYPE-C USB 口供电；（USB的拨码开关off/on,拨到on）

* TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境：

1. Luatools 下载调试工具

2. Air780EHM固件版本：LuatOS-SoC_V2016_Air780EHM_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780ehm/luatos/firmware/](https://docs.openluat.com/air780ehm/luatos/firmware/version/)

   Air780EHV固件版本：LuatOS-SoC_V2016_Air780EHV_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780ehv/luatos/firmware/](https://docs.openluat.com/air780ehv/luatos/firmware/version/)



   Air780EGH固件版本：LuatOS-SoC_V2016_Air780EGH_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780egh/luatos/firmware/](https://docs.openluat.com/air780egh/luatos/firmware/version/)



3. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境

2. Luatools 烧录内核固件和  demo 脚本

3. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，otp 读取结果、进入飞行模式、otp区域擦除、写入/读取数据、退出飞行模式

4. 如下 log 显示：

```bash
[2025-11-24 17:08:21.592][000000000.370] I/user.main otp_demo 001.000.000
[2025-11-24 17:08:21.602][000000000.377] I/user.========otp read start=========
[2025-11-24 17:08:21.609][000000000.378] I/user.otp 读取结果  string
[2025-11-24 17:08:21.619][000000000.378] I/user.写数据前先进入飞行模式
[2025-11-24 17:08:21.731][000000000.951] I/user.现在是飞行模式 true
[2025-11-24 17:08:21.738][000000000.951] I/user.========otp erase start=========
[2025-11-24 17:08:21.744][000000000.952] I/otp otp erase zone 1 00001000
[2025-11-24 17:08:21.749][000000000.953] I/user.OTP 擦除成功
[2025-11-24 17:08:21.755][000000000.953] I/user.=========向otp区域1写入数据==========
[2025-11-24 17:08:21.760][000000000.953] I/user.OTP 写入成功 1234
[2025-11-24 17:08:21.765][000000000.953] I/user.=========读取otp区域1数据==========
[2025-11-24 17:08:21.772][000000000.954] I/user.读取4字节数据 1234 string
[2025-11-24 17:08:21.777][000000000.954] I/user.读取8字节数据 1234 string
[2025-11-24 17:08:21.861][000000001.119] I/user.退出飞行模式 false
[2025-11-24 17:08:26.285][000000005.485] D/mobile cid1, state0
[2025-11-24 17:08:26.289][000000005.486] D/mobile bearer act 0, result 0
[2025-11-24 17:08:26.293][000000005.487] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-24 17:08:26.296][000000005.515] D/mobile TIME_SYNC 0

```
