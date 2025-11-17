## 功能模块介绍：

1. main.lua：主程序入口，以下两个脚本按自己的需求选择其一使用即可，另外一个注释

2. lf_fs：通过littleFS文件系统,对nand flash模块以文件系统的方式进行读写数据操作，详细逻辑请看lf_fs.lua 文件

3. raw_spi：通过原始spi接口对nand flash模块进行读写数据操作，详细逻辑请看raw_spi.lua 文件

## 演示功能概述：

### lf_fs：

1.以对象的方式配置参数，初始化启用 SPI，返回 SPI 对象

2.用 SPI 对象初始化 flash 设备，返回 flash 设备对象

3.用 lf 库挂载 flash 设备对象为LittleFS文件系统

4.读取文件系统的信息，以确认内存情况

5.操作文件读写，并验证写入一致性，追加文件等。

### raw_spi：

1.初始化并启用spi,如果初始化失败，退出程序

2.spi启用后读取并验证nand flash芯片ID,如果验证失败，退出程序

3.验证nand flash芯片后读取寄存器状态，确认芯片就绪

4.验证是否是坏块，非坏块擦除块区，为写入数据做准备

5.擦除块区后，写数据到块区，并读取块区数据与写入数据进行验证

6.操作完成关闭写使能并关闭SPI。

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

2. main.lua 中加载lf_fs功能模块或者raw_spi功能模块，二者使用其一

3. Luatools 烧录内核固件和 修改后的 demo 脚本

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

6.raw_spi.lua 如下 log 显示：

华邦W25N01GV，手册说明块0~7出厂保证为有效块，可直接跳过检测。块取值0~1023

nand flash中块编码大于块7的操作演示：


    [2025-11-14 13:44:45.288][000000000.266] I/user.main SPI_NAND 001.000.000
    [2025-11-14 13:44:45.297][000000000.276] I/user.W25N01GV 初始化SPI1...
    [2025-11-14 13:44:45.314][000000000.277] SPI_HWInit 552:spi0 speed 2000000,1994805,154
    [2025-11-14 13:44:45.328][000000000.277] I/user.芯片ID: 0xEF 0xAA 0x21
    [2025-11-14 13:44:45.336][000000000.278] I/user.擦除块 9 ...
    [2025-11-14 13:44:45.346][000000000.278] I/user.读取主阵列（偏移0x01） 读到的数据 FF 长度 1
    [2025-11-14 13:44:45.361][000000000.279] D/user.块 9 主阵列第1字节：0xFF OOB前2字节：0xFF, 0xFF 判定为好块
    [2025-11-14 13:44:45.433][000000000.701] I/user.写入数据 Hello, W25N01GV! 到页 576 块 9
    [2025-11-14 13:44:45.448][000000000.712] I/user.读到的数据 48656C6C6F2C205732354E3031475621 长度 16
    [2025-11-14 13:44:45.468][000000000.712] I/user.数据验证成功: Hello, W25N01GV!

nand flash中块编码小于块7的操作演示：


    [2025-11-14 13:47:04.536][000000000.258] I/user.main SPI_NAND 001.000.000
    [2025-11-14 13:47:04.544][000000000.268] I/user.W25N01GV 初始化SPI1...
    [2025-11-14 13:47:04.561][000000000.268] SPI_HWInit 552:spi0 speed 2000000,1994805,154
    [2025-11-14 13:47:04.575][000000000.269] I/user.芯片ID: 0xEF 0xAA 0x21
    [2025-11-14 13:47:04.583][000000000.269] I/user.擦除块 7 ...
    [2025-11-14 13:47:04.598][000000000.269] D/user.块 7 是出厂保证有效块，直接判定为好块
    [2025-11-14 13:47:04.609][000000000.270] I/user.写入数据 Hello, W25N01GV! 到页 448 块 7
    [2025-11-14 13:47:04.624][000000000.272] I/user.读到的数据 48656C6C6F2C205732354E3031475621 长度 16
    [2025-11-14 13:47:04.635][000000000.272] I/user.数据验证成功: Hello, W25N01GV!
