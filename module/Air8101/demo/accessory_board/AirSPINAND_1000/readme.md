## 功能模块介绍：

1. main.lua：主程序入口，加载以下脚本运行

2. lf_fs：通过littleFS文件系统,对nand flash模块以文件系统的方式进行读写数据操作，详细逻辑请看lf_fs.lua 文件
   
   

## 演示功能概述：

### lf_fs：

1.以对象的方式配置参数，初始化启用 SPI，返回 SPI 对象

2.用 SPI 对象初始化 flash 设备，返回 flash 设备对象

3.用 lf 库挂载 flash 设备对象为LittleFS文件系统

4.读取文件系统的信息，以确认内存情况

5.操作文件读写，并验证写入一致性，追加文件等。

## 演示硬件环境：

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/8101.jpg)

![](https://docs.openluat.com/accessory/AirSPINAND_1000/image/nand.jpg)

1. 合宙Air8101核心板一块

2. 合宙 AirSPINAND_1000配件板 一块

3. TYPE-C USB 数据线一根 ，Air8101 核心板和数据线的硬件接线方式为：
* Air8101核心板通过 TYPE-C USB 口供电；（背面usb开关拨到off）

* TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；
4. 杜邦线 6 根

   Air8101核Air8101心板与 AirSPINAND_1000配件板 按以下方式接线：

<table>
<tr>
<td>Air8101核心板<br/></td><td>AirSPINAND_1000配件板<br/></td></tr>
<tr>
<td>GND(任意)          <br/></td><td>GND<br/></td></tr>
<tr>
<td>3.3V<br/></td><td>VCC<br/></td></tr>
<tr>
<td>54/DISP<br/></td><td>CS<br/></td></tr>
<tr>
<td>28/DCLK<br/></td><td>SCK<br/></td></tr>
<tr>
<td>57/DE<br/></td><td>MOSI<br/></td></tr>
<tr>
<td>55/HSYN<br/></td><td>MISO<br/></td></tr>
</table>

## 演示软件环境：

1. Luatools 下载调试工具

2. 固件版本：LuatOS-SoC_V2002_Air8101_101.soc，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air8101/luatos/firmware/](https://docs.openluat.com/air8101/luatos/firmware/)

3. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境

2. main.lua 中加载lf_fs功能模块

3. Luatools 烧录内核固件和 demo 脚本

4. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，spi 初始化，数据读写，文件操作等。

5. lf_fs.lua 如下 log 显示：

```bash
[2025-11-15 16:41:28.932][000000000.215] I/user.main SPI_NAND 001.000.000
[2025-11-15 16:41:28.945][000000000.224] I/user.lf_fs SPI_ID 0 CS_PIN 8
[2025-11-15 16:41:28.952][000000000.224] SPI_HWInit 552:spi0 speed 2000000,1994805,154
[2025-11-15 16:41:28.961][000000000.225] I/user.硬件spi 初始化，波特率: SPI*: 0C1A6A68 2000000
[2025-11-15 16:41:28.977][000000000.225] I/user.SPI初始化 成功，波特率 2000000
[2025-11-15 16:41:28.985][000000000.225] I/user.Flash初始化 开始
[2025-11-15 16:41:28.997][000000000.225] I/little_flash SFDP header not found.
[2025-11-15 16:41:29.005][000000000.226] I/little_flash JEDEC ID: manufacturer_id:0xEF device_id:0xAA21 
[2025-11-15 16:41:29.011][000000000.226] I/little_flash little flash fonud flash W25N01GVZEIG
[2025-11-15 16:41:29.016][000000000.277] I/user.Flash初始化 成功，设备: userdata: 0C1CA134
[2025-11-15 16:41:29.025][000000000.277] I/user.文件系统 开始挂载: /little_flash
[2025-11-15 16:41:29.799][000000001.737] D/little_flash lfs_mount 0
[2025-11-15 16:41:29.806][000000001.738] D/little_flash vfs mount /little_flash ret 0
[2025-11-15 16:41:29.811][000000001.738] I/user.文件系统 挂载成功: /little_flash
[2025-11-15 16:41:29.818][000000001.738] I/user.文件系统信息 开始查询: /little_flash
[2025-11-15 16:41:30.812][000000002.735] I/user.  总block数: 1024
[2025-11-15 16:41:30.827][000000002.735] I/user.  已用block数: 2
[2025-11-15 16:41:30.835][000000002.736] I/user.  block大小: 131072 字节
[2025-11-15 16:41:30.845][000000002.736] I/user.  文件系统类型: lfs
[2025-11-15 16:41:30.852][000000002.736] I/user.文件操作测试 开始
[2025-11-15 16:41:31.326][000000003.259] I/user.  写入成功 /little_flash/test.txt 内容: 当前时间: Sat Nov 15 16:41:36 2025
[2025-11-15 16:41:31.837][000000003.771] I/user.  读取成功 /little_flash/test.txt 内容: 当前时间: Sat Nov 15 16:41:36 2025
[2025-11-15 16:41:34.095][000000006.020] I/user.  追加后内容: LuatOS 测试 - 追加时间: Sat Nov 15 16:41:38 2025
[2025-11-15 16:41:34.106][000000006.020] I/user.文件操作测试 完成
[2025-11-15 16:41:34.117][000000006.021] I/user.关闭spi true
[2025-11-15 16:41:34.129][000000006.023] D/mobile cid1, state0
[2025-11-15 16:41:34.136][000000006.023] D/mobile bearer act 0, result 0
[2025-11-15 16:41:34.146][000000006.024] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-15 16:41:34.160][000000006.024] D/mobile TIME_SYNC 0

```
