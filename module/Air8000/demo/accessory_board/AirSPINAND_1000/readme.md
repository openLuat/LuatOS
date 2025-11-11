## 功能模块介绍：

1. main.lua：主程序入口，以下两个脚本按自己的需求选择其一使用即可，另外一个注释

2. lf_fs：通过littleFS文件系统,对nand flash模块以文件系统的方式进行读写数据操作，详细逻辑请看lf_fs.lua 文件

3. ram_spi：通过原始spi接口对nand flash模块进行读写数据操作，详细逻辑请看ram_spi.lua 文件

## 演示功能概述：

### lf_fs：

1.以对象的方式配置参数，初始化启用 SPI，返回 SPI 对象

2.用 SPI 对象初始化 flash 设备，返回 flash 设备对象

3.用 lf 库挂载 flash 设备对象为LittleFS文件系统

4.读取文件系统的信息，以确认内存情况

5.操作文件读写，并验证写入一致性，追加文件等。

### ram_spi：

1.初始化并启用spi,如果初始化失败，退出程序

2.spi启用后读取并验证nand flash芯片ID,如果验证失败，退出程序

3.验证nand flash芯片后读取寄存器状态，确认芯片就绪

4.验证是否是坏块，非坏块擦除块区，为写入数据做准备

5.擦除块区后，写数据到块区，并读取块区数据与写入数据进行验证

6.操作完成关闭写使能并关闭SPI。

## 演示硬件环境：

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/spi1.jpg)

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/nand.jpg)

1. 合宙 Air8000 核心板一块

2. 合宙 AirSPINAND配件板 一块

3. TYPE-C USB 数据线一根 ，Air8000 核心板和数据线的硬件接线方式为：
- Air8000 核心板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；
4. 杜邦线 6 根

    Air8000 核心板与 AirSPINAND配件板 按以下方式接线：

<table>
<tr>
<td>Air8000核心板<br/></td><td>AirSPINAND配件板<br/></td></tr>
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

2. main.lua 中加载lf_fs功能模块或者ram_spi功能模块，二者使用其一

3. Luatools 烧录内核固件和 修改后的 demo 脚本

4. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，spi 初始化，数据读写，文件操作等。

5. lf_fs.lua 如下 log 显示：

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

6.ram_spi.lua 如下 log 显示：

华邦W25N01GV，手册说明块0~7出厂保证为有效块，可直接跳过检测。块取值0~1023

nand flash中块编码大于块7的操作演示：
    [2025-11-03 16:37:38.913][000000000.626] D/airlink Air8000s启动完成, 等待了 14 ms
    [2025-11-03 16:37:38.916][000000000.662] I/user.main Air8000_SPI_NAND 001.000.000
    [2025-11-03 16:37:38.959][000000000.694] I/user.W25N01GV 初始化SPI1...
    [2025-11-03 16:37:38.962][000000000.695] SPI_HWInit 552:spi1 speed 4000000,3989610,77
    [2025-11-03 16:37:38.966][000000000.696] I/user.芯片ID: 0xEF 0xAA 0x21
    [2025-11-03 16:37:38.969][000000000.696] I/user.擦除块 8 ...
    [2025-11-03 16:37:38.973][000000000.697] I/user.读取主阵列（偏移0x01） 读到的数据 FF 长度 1
    [2025-11-03 16:37:38.980][000000000.699] D/user.块 8 主阵列第1字节：0xFF OOB前2字节：0xFF, 0xFF 判定为好块
    [2025-11-03 16:37:38.991][000000000.710] I/user.写入数据 Hello, W25N01GV! 到页 512 块 8
    [2025-11-03 16:37:38.995][000000000.712] I/user.读到的数据 48656C6C6F2C205732354E3031475621 长度 16
    [2025-11-03 16:37:39.010][000000000.713] I/user.数据验证成功: Hello, W25N01GV!
    [2025-11-03 16:37:41.207][000000003.034] D/mobile cid1, state0
    [2025-11-03 16:37:41.212][000000003.034] D/mobile bearer act 0, result 0
    [2025-11-03 16:37:41.220][000000003.035] D/mobile NETIF_LINK_ON -> IP_READY
    [2025-11-03 16:37:41.229][000000003.070] D/mobile TIME_SYNC 0

nand flash中块编码小于块7的操作演示：
    [2025-11-03 17:02:50.355][000000000.623] D/airlink Air8000s启动完成, 等待了 10 ms
    [2025-11-03 17:02:50.361][000000000.658] I/user.main Air8000_SPI_NAND 001.000.000
    [2025-11-03 17:02:50.367][000000000.673] I/user.W25N01GV 初始化SPI1...
    [2025-11-03 17:02:50.371][000000000.674] SPI_HWInit 552:spi1 speed 2000000,1994805,154
    [2025-11-03 17:02:50.415][000000000.691] I/user.芯片ID: 0xEF 0xAA 0x21
    [2025-11-03 17:02:50.421][000000000.691] I/user.擦除块 7 ...
    [2025-11-03 17:02:50.427][000000000.692] D/user.块 7 是出厂保证有效块，直接判定为好块
    [2025-11-03 17:02:50.438][000000000.693] I/user.写入数据 Hello, W25N01GV! 到页 448 块 7
    [2025-11-03 17:02:50.444][000000000.695] I/user.读到的数据 48656C6C6F2C205732354E3031475621 长度 16
    [2025-11-03 17:02:50.451][000000000.695] I/user.数据验证成功: Hello, W25N01GV!
    [2025-11-03 17:02:52.577][000000002.984] D/mobile cid1, state0
    [2025-11-03 17:02:52.589][000000002.985] D/mobile bearer act 0, result 0
    [2025-11-03 17:02:52.594][000000002.986] D/mobile NETIF_LINK_ON -> IP_READY
    [2025-11-03 17:02:52.602][000000003.017] D/mobile TIME_SYNC 0
