## 功能模块介绍：

1. main.lua：主程序入口,以下两个脚本按自己的需求选择其一使用即可，另外两个注释。

2. raw_spi：通过原始spi接口对flash模块进行读写数据操作，详细逻辑请看raw_spi.lua 文件

3. lf_fs：通过littleFS文件系统,对flash模块以文件系统的方式进行读写数据操作，详细逻辑请看lf_fs.lua 文件

4. sfud_test:通过sfud核心库和io文件系统,对flash模块以文件系统的方式进行读写数据操作，详细逻辑请看sfud.lua 文件

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

3.用 lf 库挂载 flash 设备对象为文件系统

4.读取文件系统的信息

5.操作文件读写，并验证写入一致性，追加文件等。

### sfud_test.lua：

1.以对象的方式配置参数，初始化启用SPI，返回SPI对象

2.用SPI对象初始化sfud，

3.用sfud库挂载flash设备为文件系统

4.读取文件系统的信息

5.操作文件读写，擦除，并验证写入一致性，追加文件等。

## 演示硬件环境：

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/780EHV.jpg)

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/norflash.jpg)

1. 合宙 Air780EHV/EHM/EGH 核心板一块

2. 合宙 AirSPINORFLASH_1000 一块

3. TYPE-C USB 数据线一根 ，Air780EHV/EHM/EGH 核心板和数据线的硬件接线方式为：
- Air780EHV/EHM/EGH 核心板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；
4. 杜邦线 6 根

    Air780EHV/EHM/EGH 核心板与 AirSPINORFLASH_1000 按以下方式接线：

<table>
<tr>
<td>Air780EHV/EHM/EGH核心板<br/></td><td>AirSPINORFLASH_1000配件版<br/></td></tr>
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

3. 固件版本：LuatOS-SoC_V2018_Air780EHV_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/Air780EHV/luatos/firmware/version/](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

4. 固件版本：LuatOS-SoC_V2018_Air780EGH_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780egh/luatos/firmware/version/](https://docs.openluat.com/air780egh/luatos/firmware/version/)


5. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境
2. main.lua 中加载需要用的功能模块，三个功能模块同时只能选择一个使用，另两个注释。
3. Luatools 烧录内核固件和修改后的 demo 脚本代码
4. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，spi 初始化，数据读写，文件操作等。
5. raw_spi.lua 如下 log 显示：

```bash
[2025-09-11 12:12:04.093][000000000.249] I/user.main AirSPINORFLASH_1000 001.000.000
[2025-09-11 12:12:04.097][000000000.257] I/user.raw_spi SPI_ID 0 CS_PIN 8
[2025-09-11 12:12:04.101][000000000.257] SPI_HWInit 552:spi0 speed 2000000,1994805,154
[2025-09-11 12:12:04.105][000000000.257] I/user.硬件spi 初始化，波特率: 0 2000000
[2025-09-11 12:12:04.109][000000000.258] I/user.spi 芯片ID: 0x%02X 0x%02X 0x%02X 239 64 23
[2025-09-11 12:12:04.119][000000000.258] I/user.spi 寄存器状态为: 0x%02X 0
[2025-09-11 12:12:04.125][000000000.258] I/user.spi 擦除扇区 0x000000...
[2025-09-11 12:12:04.131][000000000.322] I/user.spi 擦除后数据: FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF 32
[2025-09-11 12:12:04.135][000000000.323] I/user.spi 写入数据: Hello, SPI Flash! 
[2025-09-11 12:12:04.138][000000000.324] I/user.spi 正在验证数据...
[2025-09-11 12:12:04.142][000000000.326] I/user.spi 数据验证成功!,读取到数据为：Hello, SPI Flash! 
[2025-09-11 12:12:04.145][000000000.326] I/user.关闭spi 0


```

6. lf_fs.lua 如下 log 显示：

```bash
[2025-09-11 12:01:07.533][000000000.366] I/user.main AirSPINORFLASH_1000 001.000.000
[2025-09-11 12:01:07.549][000000000.373] I/user.lf_fs SPI_ID 0 CS_PIN 8
[2025-09-11 12:01:07.566][000000000.374] SPI_HWInit 552:spi0 speed 2000000,1994805,154
[2025-09-11 12:01:07.586][000000000.374] I/user.硬件spi 初始化，波特率: SPI*: 0C7F5D18 2000000
[2025-09-11 12:01:07.606][000000000.374] I/user.SPI初始化 成功，波特率:20MHz
[2025-09-11 12:01:07.620][000000000.375] I/user.Flash初始化 开始
[2025-09-11 12:01:07.632][000000000.375] I/little_flash Welcome to use little flash V0.0.1 .
[2025-09-11 12:01:07.646][000000000.375] I/little_flash Github Repositories https://github.com/Dozingfiretruck/little_flash .
[2025-09-11 12:01:07.663][000000000.375] I/little_flash Gitee Repositories https://gitee.com/Dozingfiretruck/little_flash .
[2025-09-11 12:01:07.681][000000000.376] I/little_flash Found SFDP Header. The Revision is V1.5, NPN is 0, Access Protocol is 0xFF.
[2025-09-11 12:01:07.690][000000000.376] I/little_flash Parameter Header is OK. The Parameter ID is 0xFF00, Revision is V5.1, Length is 16,Parameter Table Pointer is 0x000080.
[2025-09-11 12:01:07.704][000000000.377] I/little_flash Found a flash chip. Size is 8388608 bytes.
[2025-09-11 12:01:07.714][000000000.427] I/user.Flash初始化 成功，设备: userdata: 0C10B3C0
[2025-09-11 12:01:07.728][000000000.427] I/user.文件系统 开始挂载: /little_flash
[2025-09-11 12:01:07.740][000000000.495] D/little_flash lfs_mount 0
[2025-09-11 12:01:07.755][000000000.496] D/little_flash vfs mount /little_flash ret 0
[2025-09-11 12:01:07.767][000000000.496] I/user.文件系统 挂载成功: /little_flash
[2025-09-11 12:01:07.778][000000000.496] I/user.文件系统信息 开始查询: /little_flash
[2025-09-11 12:01:07.792][000000000.557] I/user.  总block数: 2048
[2025-09-11 12:01:07.807][000000000.557] I/user.  已用block数: 2
[2025-09-11 12:01:07.819][000000000.557] I/user.  block大小: 4096 字节
[2025-09-11 12:01:07.829][000000000.557] I/user.  文件系统类型: lfs
[2025-09-11 12:01:07.843][000000000.558] I/user.文件操作测试 开始
[2025-09-11 12:01:07.929][000000000.984] I/user.  写入成功 /little_flash/test.txt 内容: 当前时间: Sun Jan  0 08:00:00 1900
[2025-09-11 12:01:07.944][000000000.990] I/user.  读取成功 /little_flash/test.txt 内容: 当前时间: Sun Jan  0 08:00:00 1900
[2025-09-11 12:01:07.956][000000001.039] I/user.  追加后内容: LuatOS 测试 - 追加时间: Sun Jan  0 08:00:00 1900
[2025-09-11 12:01:07.967][000000001.039] I/user.文件操作测试 完成
[2025-09-11 12:01:07.978][000000001.039] I/user.关闭spi true


```

7. sfud_test.lua 如下 log 显示：

```bash
[2025-10-17 17:01:21.762][000000000.250] I/user.main AirSPINORFLASH_1000 001.000.000
[2025-10-17 17:01:21.769][000000000.257] I/user.sfud SPI_ID 0 CS_PIN 8
[2025-10-17 17:01:21.778][000000000.258] SPI_HWInit 552:spi0 speed 200000,200000,64
[2025-10-17 17:01:21.788][000000000.258] I/user.硬件spi 初始化，波特率: SPI*: 0C7F5C38 200000
[2025-10-17 17:01:21.797][000000000.259] I/user.SPI初始化 成功，波特率: 200000
[2025-10-17 17:01:21.804][000000000.259] I/user.sfud初始化 开始
[2025-10-17 17:01:21.811][000000000.263] I/sfud Found a Winbond flash chip. Size is 16777216 bytes.
[2025-10-17 17:01:21.823][000000000.283] I/sfud LuatOS-sfud flash device initialized successfully.
[2025-10-17 17:01:21.833][000000000.284] I/user.获取flash设备信息表: userdata: 0C0E0340
[2025-10-17 17:01:21.845][000000000.284] I/user.获取 Flash 容量和page大小： 16777216 4096
[2025-10-17 17:01:21.853][000000000.346] I/user.擦除一个块的数据： 0
[2025-10-17 17:01:21.865][000000000.349] I/user.写入数据： 0
[2025-10-17 17:01:21.875][000000000.546] I/user.读取数据： 
[2025-10-17 17:01:21.886][000000000.546] testdata
[2025-10-17 17:01:21.942][000000000.603] I/user.先擦除再写入数据： 0
[2025-10-17 17:01:21.954][000000000.603] I/user.文件系统 开始挂载: /sfud_flash
[2025-10-17 17:01:21.962][000000000.643] D/sfud lfs_mount -84
[2025-10-17 17:01:22.020][000000000.954] D/sfud lfs_mount 0
[2025-10-17 17:01:22.037][000000000.954] D/sfud vfs mount /sfud_flash ret 0
[2025-10-17 17:01:22.045][000000000.955] I/user.文件系统 挂载成功: /sfud_flash
[2025-10-17 17:01:22.054][000000000.955] I/user.文件系统信息 开始查询: /sfud_flash
[2025-10-17 17:01:22.061][000000001.008] I/user.  总block数: 4096
[2025-10-17 17:01:22.071][000000001.008] I/user.  已用block数: 2
[2025-10-17 17:01:22.079][000000001.009] I/user.  block大小: 4096 字节
[2025-10-17 17:01:22.085][000000001.009] I/user.  文件系统类型: lfs
[2025-10-17 17:01:22.089][000000001.009] I/user.文件操作测试 开始
[2025-10-17 17:01:22.099][000000001.130] I/user.  写入成功 /sfud_flash/test.txt 内容: 当前时间: Sun Jan  0 08:00:00 1900
[2025-10-17 17:01:22.153][000000001.222] I/user.  读取成功 /sfud_flash/test.txt 内容: 当前时间: Sun Jan  0 08:00:00 1900
[2025-10-17 17:01:22.681][000000001.747] I/user.  追加后内容: LuatOS 测试 - 追加时间: Sun Jan  0 08:00:01 1900
[2025-10-17 17:01:22.688][000000001.747] I/user.文件操作测试 完成
[2025-10-17 17:01:22.693][000000001.748] I/user.关闭spi true



```

