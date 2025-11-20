## 功能模块介绍：

1. main.lua：主程序入口,以下两个脚本按自己的需求选择其一使用即可，另外一个注释。

2. raw_spi：通过原始spi接口对flash模块进行读写数据操作，详细逻辑请看raw_spi.lua 文件

3. lf_fs：通过littleFS文件系统,对flash模块以文件系统的方式进行读写数据操作，详细逻辑请看lf_fs.lua 文件


## 演示功能概述：

### raw_spi：

1.初始化并启用 spi,如果初始化失败，退出程序

2.spi 启用后读取并验证 flash 芯片 ID,如果验证失败，退出程序

3.验证 flash 芯片后读取寄存器状态，确认芯片就绪

4.擦除扇区，为写入数据做准备

5.擦除扇区后，写数据到扇区，并读取扇区数据与写入数据进行验证

6.关闭写使能并关闭 SPI。

### lf_fs：

1.以对象的方式配置参数，初始化启用 SPI，返回 SPI 对象

2.用 SPI 对象初始化 flash 设备，返回 flash 设备对象

3.用 lf 库挂载 flash 设备对象为LittleFS文件系统

4.读取文件系统的信息

5.操作文件读写，并验证写入一致性，追加文件等。


## 演示硬件环境：

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/780EPM.jpg)

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/norflash.jpg)

1. 合宙 Air780EPM 核心板一块

2. 合宙 AirSPINORFLASH_1000 一块

3. TYPE-C USB 数据线一根 ，Air780EPM 核心板和数据线的硬件接线方式为：
- Air780EPM 核心板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；
4. 杜邦线 6 根

    Air780EPM 核心板与 AirSPINORFLASH_1000 按以下方式接线：

<table>
<tr>
<td>Air780EPM核心板<br/></td><td>AirSPINORFLASH_1000配件版<br/></td></tr>
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


2. 固件版本：LuatOS-SoC_V2018_Air780EPM_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780epm/luatos/firmware/version/](https://docs.openluat.com/air780epm/luatos/firmware/version/)

3. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境
2. main.lua 中加载需要用的功能模块，两个功能模块同时只能选择一个使用，另一个注释。
3. Luatools 烧录内核固件和修改后的 demo 脚本代码
4. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，spi 初始化，数据读写，文件操作等。
5. raw_spi.lua 如下 log 显示：

```bash
[2025-11-15 17:01:11.046][000000000.207] I/user.main AirSPINORFLASH_1000 001.000.000
[2025-11-15 17:01:11.063][000000000.215] I/user.raw_spi SPI_ID 0 CS_PIN 8
[2025-11-15 17:01:11.082][000000000.216] SPI_HWInit 552:spi0 speed 2000000,1994805,154
[2025-11-15 17:01:11.088][000000000.216] I/user.硬件spi 初始化，波特率: 0 2000000
[2025-11-15 17:01:11.100][000000000.217] I/user.spi 芯片ID: 0x%02X 0x%02X 0x%02X 239 64 25
[2025-11-15 17:01:11.111][000000000.217] I/user.spi 寄存器状态为: 0x%02X 0
[2025-11-15 17:01:11.122][000000000.217] I/user.spi 擦除扇区 0x000000...
[2025-11-15 17:01:11.133][000000000.258] I/user.spi 擦除后数据: FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF 32
[2025-11-15 17:01:11.147][000000000.258] I/user.spi 写入数据: Hello, SPI Flash! 
[2025-11-15 17:01:11.157][000000000.260] I/user.spi 正在验证数据...
[2025-11-15 17:01:11.168][000000000.261] I/user.spi 数据验证成功!,读取到数据为：Hello, SPI Flash! 
[2025-11-15 17:01:11.185][000000000.261] I/user.关闭spi 0
[2025-11-15 17:01:12.250][000000002.029] D/mobile cid1, state0
[2025-11-15 17:01:12.256][000000002.030] D/mobile bearer act 0, result 0
[2025-11-15 17:01:12.265][000000002.030] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-15 17:01:12.271][000000002.047] D/mobile TIME_SYNC 0



```

6. lf_fs.lua 如下 log 显示：

```bash
[2025-11-15 16:59:36.747][000000000.206] I/user.main AirSPINORFLASH_1000 001.000.000
[2025-11-15 16:59:36.760][000000000.215] I/user.lf_fs SPI_ID 0 CS_PIN 8
[2025-11-15 16:59:36.772][000000000.215] SPI_HWInit 552:spi0 speed 2000000,1994805,154
[2025-11-15 16:59:36.789][000000000.215] I/user.硬件spi 初始化，波特率: SPI*: 0C1A6A50 2000000
[2025-11-15 16:59:36.815][000000000.216] I/user.SPI初始化 成功，波特率: 2000000
[2025-11-15 16:59:36.846][000000000.216] I/user.Flash初始化 开始
[2025-11-15 16:59:36.872][000000000.216] I/little_flash Found SFDP Header. The Revision is V1.5, NPN is 0, Access Protocol is 0xFF.
[2025-11-15 16:59:36.906][000000000.217] I/little_flash Parameter Header is OK. The Parameter ID is 0xFF00, Revision is V5.1, Length is 16,Parameter Table Pointer is 0x000080.
[2025-11-15 16:59:36.922][000000000.217] I/little_flash Found a flash chip. Size is 33554432 bytes.
[2025-11-15 16:59:36.937][000000000.267] I/user.Flash初始化 成功，设备: userdata: 0C1CA0D4
[2025-11-15 16:59:36.949][000000000.268] I/user.文件系统 开始挂载: /little_flash
[2025-11-15 16:59:36.962][000000000.274] D/little_flash lfs_mount -84
[2025-11-15 16:59:36.975][000000000.389] D/little_flash lfs_format 0
[2025-11-15 16:59:36.985][000000000.395] D/little_flash lfs_mount 0
[2025-11-15 16:59:36.997][000000000.395] D/little_flash vfs mount /little_flash ret 0
[2025-11-15 16:59:37.008][000000000.395] I/user.文件系统 挂载成功: /little_flash
[2025-11-15 16:59:37.024][000000000.396] I/user.文件系统信息 开始查询: /little_flash
[2025-11-15 16:59:37.036][000000000.401] I/user.  总block数: 8192
[2025-11-15 16:59:37.050][000000000.402] I/user.  已用block数: 2
[2025-11-15 16:59:37.060][000000000.402] I/user.  block大小: 4096 字节
[2025-11-15 16:59:37.074][000000000.402] I/user.  文件系统类型: lfs
[2025-11-15 16:59:37.086][000000000.403] I/user.文件操作测试 开始
[2025-11-15 16:59:37.094][000000000.417] I/user.  写入成功 /little_flash/test.txt 内容: 当前时间: Sat Jan  1 08:00:00 2000
[2025-11-15 16:59:37.107][000000000.427] I/user.  读取成功 /little_flash/test.txt 内容: 当前时间: Sat Jan  1 08:00:00 2000
[2025-11-15 16:59:37.117][000000000.486] I/user.  追加后内容: LuatOS 测试 - 追加时间: Sat Jan  1 08:00:00 2000
[2025-11-15 16:59:37.130][000000000.486] I/user.文件操作测试 完成
[2025-11-15 16:59:37.140][000000000.487] I/user.关闭spi true
[2025-11-15 16:59:38.003][000000002.063] D/mobile cid1, state0
[2025-11-15 16:59:38.010][000000002.064] D/mobile bearer act 0, result 0
[2025-11-15 16:59:38.019][000000002.065] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-15 16:59:38.027][000000002.077] D/mobile TIME_SYNC 0



```




