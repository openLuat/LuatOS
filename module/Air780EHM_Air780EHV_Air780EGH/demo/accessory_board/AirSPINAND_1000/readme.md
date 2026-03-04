## 功能模块介绍：

1. main.lua：主程序入口，加载lf_fs脚本运行

2. lf_fs：通过littleFS文件系统,对nand flash模块以文件系统的方式进行读写数据操作，详细逻辑请看lf_fs.lua 文件

## 演示功能概述：

### lf_fs：

1.以对象的方式配置参数，初始化启用 SPI，返回 SPI 对象

2.用 SPI 对象初始化 flash 设备，返回 flash 设备对象

3.用 lf 库挂载 flash 设备对象为LittleFS文件系统

4.读取文件系统的信息，以确认内存情况

5.操作文件读写，并验证写入一致性，追加文件等。



## 演示硬件环境：

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/780EHV.jpg)

![](https://docs.openluat.com/accessory/AirSPINAND_1000/image/nand.jpg)

1. 合宙Air780EHM/EHV/EGH 核心板一块

2. 合宙 AirSPINAND_1000配件板 一块

3. TYPE-C USB 数据线一根 ，Air780EHM/EHV/EGH 核心板和数据线的硬件接线方式为：
- Air780EHM/EHV/EGH 核心板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；
4. 杜邦线 6 根

    Air780EHM/EHV/EGH 核心板与 AirSPINAND_1000配件板 按以下方式接线：

<table>
<tr>
<td>Air780EHM/EHV/EGH核心板<br/></td><td>AirSPINAND_1000配件板<br/></td></tr>
<tr>
<td>GND(任意)          <br/></td><td>GND<br/></td></tr>
<tr>
<td>VDD_EXT<br/></td><td>VCC<br/></td></tr>
<tr>
<td>GPIO8/<br/>SPI0_CS<br/></td><td>CS<br/></td></tr>
<tr>
<td>SPI0_SLK<br/></td><td>SCK<br/></td></tr>
<tr>
<td>SPI0_MOSI<br/></td><td>MOSI<br/></td></tr>
<tr>
<td>SPI0_MISO<br/></td><td>MISO<br/></td></tr>
</table>

## 演示软件环境：

1. Luatools 下载调试工具

2. 固件版本：LuatOS-SoC_V2018_Air780EHM_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780ehm/luatos/firmware/version/](https://docs.openluat.com/air780ehm/luatos/firmware/version/)

3. 固件版本：LuatOS-SoC_V2018_Air780EHV_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780ehv/luatos/firmware/version/](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

4. 固件版本：LuatOS-SoC_V2018_Air780EGH_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780egh/luatos/firmware/version/](https://docs.openluat.com/air780egh/luatos/firmware/version/)
   
   

5. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境

2. main.lua 中加载lf_fs功能模块

3. Luatools 烧录内核固件和  demo 脚本

4. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，spi 初始化，数据读写，文件操作等。

5. lf_fs.lua 如下 log 显示：

```bash
[2025-11-14 13:35:50.269][000000000.257] I/user.main SPI_NAND 001.000.000
[2025-11-14 13:35:50.278][000000000.266] I/user.lf_fs SPI_ID 0 CS_PIN 8
[2025-11-14 13:35:50.288][000000000.267] SPI_HWInit 552:spi0 speed 2000000,1994805,154
[2025-11-14 13:35:50.301][000000000.267] I/user.硬件spi 初始化，波特率: SPI*: 0C7F5D18 2000000
[2025-11-14 13:35:50.310][000000000.267] I/user.SPI初始化 成功，波特率 2000000
[2025-11-14 13:35:50.321][000000000.268] I/user.Flash初始化 开始
[2025-11-14 13:35:50.332][000000000.268] I/little_flash SFDP header not found.
[2025-11-14 13:35:50.344][000000000.268] I/little_flash JEDEC ID: manufacturer_id:0xEF device_id:0xAA21 
[2025-11-14 13:35:50.350][000000000.268] I/little_flash little flash fonud flash W25N01GVZEIG
[2025-11-14 13:35:50.359][000000000.319] I/user.Flash初始化 成功，设备: userdata: 0C10B894
[2025-11-14 13:35:50.366][000000000.319] I/user.文件系统 开始挂载: /little_flash
[2025-11-14 13:35:50.965][000000001.427] D/little_flash lfs_mount 0
[2025-11-14 13:35:50.990][000000001.427] D/little_flash vfs mount /little_flash ret 0
[2025-11-14 13:35:51.010][000000001.428] I/user.文件系统 挂载成功: /little_flash
[2025-11-14 13:35:51.024][000000001.428] I/user.文件系统信息 开始查询: /little_flash
[2025-11-14 13:35:51.756][000000002.218] I/user.  总block数: 1024
[2025-11-14 13:35:51.764][000000002.218] I/user.  已用block数: 2
[2025-11-14 13:35:51.767][000000002.219] I/user.  block大小: 131072 字节
[2025-11-14 13:35:51.770][000000002.219] I/user.  文件系统类型: lfs
[2025-11-14 13:35:51.775][000000002.219] I/user.文件操作测试 开始
[2025-11-14 13:35:52.179][000000002.641] I/user.  写入成功 /little_flash/test.txt 内容: 当前时间: Sat Jan  1 08:00:02 2000
[2025-11-14 13:35:52.585][000000003.053] I/user.  读取成功 /little_flash/test.txt 内容: 当前时间: Sat Jan  1 08:00:02 2000
[2025-11-14 13:35:54.429][000000004.898] I/user.  追加后内容: LuatOS 测试 - 追加时间: Sat Jan  1 08:00:04 2000
[2025-11-14 13:35:54.436][000000004.898] I/user.文件操作测试 完成
[2025-11-14 13:35:54.442][000000004.899] I/user.关闭spi true

```
