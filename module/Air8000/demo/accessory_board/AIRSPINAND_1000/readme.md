## 功能模块介绍：

1. main.lua：主程序入口

2. AIRSPINAND_1000：通过littleFS文件系统,对flash模块以文件系统的方式进行读写数据操作，详细逻辑请看AIRSPINAND_1000.lua 文件

## 演示功能概述：

### AIRSPINAND_1000：

1.以对象的方式配置参数，初始化启用 SPI，返回 SPI 对象

2.用 SPI 对象初始化 flash 设备，返回 flash 设备对象

3.用 lf 库挂载 flash 设备对象为文件系统

4.读取文件系统的信息，以确认内存足够用于文件操作

5.操作文件读写，并验证写入一致性，追加文件等。

## 演示硬件环境：

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/spi1.jpg)

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/norflash.jpg)

1. 合宙 Air8000 核心板一块

2. 合宙 AIRSPINAND_1000 一块

3. TYPE-C USB 数据线一根 ，Air8000 核心板和数据线的硬件接线方式为：
- Air8000 核心板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；
4. 杜邦线 6 根

    Air8000 核心板与 AIRSPINAND_1000AIRSPINAND_1000 按以下方式接线：

<table>
<tr>
<td>Air8000核心板<br/></td><td>AirSPINORFLASH_1000配件版<br/></td></tr>
<tr>
<td>GND(任意)          <br/></td><td>GND<br/></td></tr>
<tr>
<td>VDD_EXT<br/></td><td>VCC<br/></td></tr>
<tr>
<td>GPIO12/<br/>SPI1_CS<br/></td><td>CS<br/></td></tr>
<tr>
<td>SPI1_SLK<br/></td><td>SCK<br/></td></tr>
<tr>
<td>SPI1_MOSI<br/></td><td>MOSI<br/></td></tr>
<tr>
<td>SPI1_MISO<br/></td><td>MISO<br/></td></tr>
</table>

## 演示软件环境：

1. Luatools 下载调试工具

2. 固件版本：LuatOS-SoC_V2014_Air8000_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air8000/luatos/firmware/](https://docs.openluat.com/air8000/luatos/firmware/)

3. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境

2. main.lua 中加载需要用的功能模块，两个功能模块同时只能选择一个使用，另一个注释。

3. Luatools 烧录内核固件和修改后的 demo 脚本代码

4. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，spi 初始化，数据读写，文件操作等。

5. AIRSPINAND_1000.lua 如下 log 显示：

```bash
[2025-09-18 14:50:09.757][000000000.358] I/user.main Air8000_SPI_lf_NAND 001.000.000
[2025-09-18 14:50:09.763][000000000.368] I/user.lf_fs SPI_ID 1 CS_PIN 12
[2025-09-18 14:50:09.771][000000000.368] SPI_HWInit 552:spi1 speed 2000000,1994805,154
[2025-09-18 14:50:09.777][000000000.369] I/user.硬件spi 初始化，波特率: SPI*: 0C7F5B90 2000000
[2025-09-18 14:50:09.788][000000000.369] I/user.SPI初始化 成功，波特率:20MHz
[2025-09-18 14:50:09.794][000000000.369] I/user.Flash初始化 开始
[2025-09-18 14:50:09.807][000000000.370] I/little_flash Welcome to use little flash V0.0.1 .
[2025-09-18 14:50:09.815][000000000.370] I/little_flash Github Repositories https://github.com/Dozingfiretruck/little_flash .
[2025-09-18 14:50:09.822][000000000.370] I/little_flash Gitee Repositories https://gitee.com/Dozingfiretruck/little_flash .
[2025-09-18 14:50:09.831][000000000.371] I/little_flash SFDP header not found.
[2025-09-18 14:50:09.838][000000000.371] I/little_flash JEDEC ID: manufacturer_id:0xEF device_id:0xAA21 
[2025-09-18 14:50:09.847][000000000.371] I/little_flash little flash fonud flash W25N01GVZEIG
[2025-09-18 14:50:09.853][000000000.421] I/user.Flash初始化 成功，设备: userdata: 0C0F9D7C
[2025-09-18 14:50:09.864][000000000.421] I/user.文件系统 开始挂载: /little_flash
[2025-09-18 14:50:10.078][000000000.816] D/little_flash lfs_mount 0
[2025-09-18 14:50:10.086][000000000.816] D/little_flash vfs mount /little_flash ret 0
[2025-09-18 14:50:10.095][000000000.817] I/user.文件系统 挂载成功: /little_flash
[2025-09-18 14:50:10.102][000000000.817] I/user.文件系统信息 开始查询: /little_flash
[2025-09-18 14:50:10.119][000000001.127] I/user.  总block数: 1024
[2025-09-18 14:50:10.131][000000001.128] I/user.  已用block数: 2
[2025-09-18 14:50:10.143][000000001.128] I/user.  block大小: 131072 字节
[2025-09-18 14:50:10.150][000000001.128] I/user.  文件系统类型: lfs
[2025-09-18 14:50:10.165][000000001.128] I/user.文件操作测试 开始
[2025-09-18 14:50:10.173][000000001.310] I/user.  写入成功 /little_flash/test.txt 内容: 当前时间: Sun Jan  0 08:00:01 1900
[2025-09-18 14:50:10.182][000000001.482] I/user.  读取成功 /little_flash/test.txt 内容: 当前时间: Sun Jan  0 08:00:01 1900
[2025-09-18 14:50:11.057][000000002.366] I/user.  追加后内容: LuatOS 测试 - 追加时间: Sun Jan  0 08:00:02 1900
[2025-09-18 14:50:11.063][000000002.367] I/user.文件操作测试 完成
[2025-09-18 14:50:11.068][000000002.367] I/user.关闭spi true


```

# 


