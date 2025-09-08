## 功能模块介绍：

1. main.lua：主程序入口,以下两个脚本按自己的需求选择其一使用即可，另外一个注释.
2. AirSPINORFLASH_1000

        SPI 驱动 flash,通过 flash 指令对 flash 模块进行读写数据操作，详细逻辑请看 AirSPINORFLASH_1000.lua 文件.

3. LITTLE_FLASH_NOR

        SPI 驱动 flash，通过 little_flash 库挂载 flash 为文件系统，以文件系统的方式进行读写数据操作，详细逻辑请看 LITTLE_FLASH_NOR.lua 文件.

## 演示功能概述：

### AirSPINORFLASH_1000：

1.初始化并启用 spi,如果初始化失败，退出程序

2.spi 启用后读取并验证 flash 芯片 ID,如果验证失败，退出程序

3.验证 flash 芯片后读取寄存器状态，确认芯片就绪

4.擦除扇区，为写入数据做准备

5.擦除扇区后，写数据到扇区，并读取扇区数据与写入数据进行验证

6.关闭写使能并关闭 SPI。

### LITTLE_FLASH_NOR：

1.以对象的防止配置参数，初始化启用 SPI，返回 SPI 对象

2.用 SPI 对象初始化 flash 设备，返回 flash 设备对象

3.用 lf 库挂载 flash 设备对象为文件系统

4.读取文件系统的信息，以确认内存足够用于文件操作

5.操作文件读写，并验证写入一致性，追加文件等。

## 演示硬件环境：

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/spi1.jpg)

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/norflash.jpg)

1. 合宙 Air8000 核心板一块

2. 合宙 AirSPINORFLASH_1000 一块

3. TYPE-C USB 数据线一根 ，Air8000 核心板和数据线的硬件接线方式为：
- Air8000 核心板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；
4. 杜邦线 6 根

    Air8000 核心板与 AirSPINORFLASH_1000 按以下方式接线：

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

3. 脚本文件： 
   main.lua
   
   

        AirSPINORFLASH_1000.lua



        LITTLE_FLASH_NOR.lua

4. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境
2. main.lua 中加载需要用的功能模块，两个功能模块同时只能选择一个使用，另一个注释。
3. Luatools 烧录内核固件和修改后的 demo 脚本代码
4. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，spi 初始化，数据读写，文件操作等。
5. AirSPINORFLASH_1000.lua 如下 log 显示：

```bash
[2025-09-05 16:11:30.689][000000001.371]I/user.AirSPINORFLASH_1000 SPI_ID 1 CS_PIN 12
[2025-09-05 16:11:30.699][000000001.371] SPI_HWInit 552:spi1 speed 2000000,1994805,154
[2025-09-05 16:11:30.705][000000001.372] I/user.硬件spi 初始化，波特率: SPI*: 0C7F61C8 2000000
[2025-09-05 16:11:30.712][000000001.373] I/user.spi 芯片ID: 0x%02X 0x%02X 0x%02X 239 64 23
[2025-09-05 16:11:30.718][000000001.373] I/user.spi 寄存器状态为: 0x%02X 0
[2025-09-05 16:11:30.728][000000001.373] I/user.spi 擦除扇区 0x000000...
[2025-09-05 16:11:30.766][000000001.434] I/user.spi 擦除后数据: FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF 32
[2025-09-05 16:11:30.772][000000001.435] I/user.spi 写入数据: Hello, SPI Flash! 
[2025-09-05 16:11:30.861][000000001.536] I/user.spi 正在验证数据...
[2025-09-05 16:11:30.866][000000001.537] I/user.spi 数据验证成功!,读取到数据为：Hello, SPI Flash! 
[2025-09-05 16:11:30.872][000000001.537] I/user.spi 设备已关闭
```

6. LITTLE_FLASH_NOR.lua 如下 log 显示：

```bash
[2025-09-05 16:30:36.312][000000000.371] I/user.main 启动 little_flash_demo v1.0.0
[2025-09-05 16:30:36.322][000000000.372] I/user.SPI初始化 ID: 1 CS引脚: 12
[2025-09-05 16:30:36.336][000000000.472] SPI_HWInit 552:spi1 speed 20000000,20480000,15
[2025-09-05 16:30:36.347][000000000.473] I/user.SPI初始化 成功，波特率:20MHz
[2025-09-05 16:30:36.364][000000000.473] I/user.Flash初始化 开始
[2025-09-05 16:30:36.373][000000000.473] I/little_flash Welcome to use little flash V0.0.1 .
[2025-09-05 16:30:36.380][000000000.473] I/little_flash Github Repositories https://github.com/Dozingfiretruck/little_flash .
[2025-09-05 16:30:36.387][000000000.473] I/little_flash Gitee Repositories https://gitee.com/Dozingfiretruck/little_flash .
[2025-09-05 16:30:36.397][000000000.474] I/little_flash Found SFDP Header. The Revision is V1.5, NPN is 0, Access Protocol is 0xFF.
[2025-09-05 16:30:36.408][000000000.474] I/little_flash Parameter Header is OK. The Parameter ID is 0xFF00, Revision is V5.1, Length is 16,Parameter Table Pointer is 0x000080.
[2025-09-05 16:30:36.415][000000000.474] I/little_flash Found a flash chip. Size is 8388608 bytes.
[2025-09-05 16:30:36.432][000000000.525] I/user.Flash初始化 成功，设备: userdata: 0C0F9DA0
[2025-09-05 16:30:36.442][000000000.525] I/user.文件系统 开始挂载: /little_flash
[2025-09-05 16:30:36.449][000000000.530] D/little_flash lfs_mount 0
[2025-09-05 16:30:36.457][000000000.530] D/little_flash vfs mount /little_flash ret 0
[2025-09-05 16:30:36.465][000000000.531] I/user.文件系统 挂载成功: /little_flash
[2025-09-05 16:30:36.476][000000000.531] I/user.文件系统信息 开始查询: /little_flash
[2025-09-05 16:30:36.490][000000000.536] I/user.  总block数: 2048
[2025-09-05 16:30:36.500][000000000.536] I/user.  已用block数: 2
[2025-09-05 16:30:36.508][000000000.536] I/user.  block大小: 4096 字节
[2025-09-05 16:30:36.520][000000000.536] I/user.  文件系统类型: lfs
[2025-09-05 16:30:36.528][000000000.548] I/user.文件系统根分区信息: true 192 4 4096 lfs
[2025-09-05 16:30:36.535][000000000.549] I/user.文件操作测试 开始
[2025-09-05 16:30:36.541][000000000.553] I/user.  写入成功 /little_flash/test.txt 内容: 当前时间: Sun Jan  0 08:00:00 1900
[2025-09-05 16:30:36.548][000000000.557] I/user.  读取成功 /little_flash/test.txt 内容: 当前时间: Sun Jan  0 08:00:00 1900
[2025-09-05 16:30:36.552][000000000.576] I/user.  追加后内容: LuatOS 测试 - 追加时间: Sun Jan  0 08:00:00 1900
[2025-09-05 16:30:36.559][000000000.576] I/user.文件操作测试 完成
```

# 
