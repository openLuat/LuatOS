## 功能模块介绍：

1. main.lua：主程序入口,以下三个脚本按自己的需求选择其一使用即可，另外两个注释。

2. raw_spi：通过原始spi接口对flash模块进行读写数据操作，详细逻辑请看raw_spi.lua 文件

3. lf_fs：通过littleFS文件系统,对flash模块以文件系统的方式进行读写数据操作，详细逻辑请看lf_fs.lua 文件

4. sfud_test:通过sfud核心库和io文件系统,对flash模块以文件系统的方式进行读写数据操作，详细逻辑请看sfud_test.lua 文件

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

### sfud_test.lua：

1.以对象的方式配置参数，初始化启用SPI，返回SPI对象

2.用SPI对象初始化sfud，

3.用sfud库挂载flash设备为FatFS文件系统

4.读取文件系统的信息

5.操作文件读写，擦除，并验证写入一致性，追加文件等。

## 演示硬件环境：

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/8101.jpg)

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/norflash.jpg)

1. 合宙 Air8101 核心板一块

2. 合宙 AirSPINORFLASH_1000 一块

3. TYPE-C USB 数据线一根 ，Air8101 核心板和数据线的硬件接线方式为：
- Air8101核心板通过 TYPE-C USB 口供电；（背面usb开关拨到off）

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；
4. 杜邦线 6 根

   Air8101 核心板与 AirSPINORFLASH_1000 按以下方式接线：

<table>
<tr>
<td>  Air8101核心板<br/></td><td>AirSPINORFLASH_1000配件版<br/></td></tr>
<tr>
<td>GND(任意)          <br/></td><td>GND<br/></td></tr>
<tr>
<td>3.3V<br/></td><td>VCC<br/></td></tr>
<tr>
<td>SPI0_CS/p54/GPIO15<br/></td><td>CS<br/></td></tr>
<tr>
<td>SPI0_SCK/p28/GPIO14<br/></td><td>SCK<br/></td></tr>
<tr>
<td>SPI0_MOSI/p57/GPIO16<br/></td><td>MOSI<br/></td></tr>
<tr>
<td>SPI0_MISO/p55/GPIO17<br/></td><td>MISO<br/></td></tr>
</table>

## 演示软件环境：

1. Luatools 下载调试工具

2. 固件版本：LuatOS-SoC_V1006_Air8101_1.soc，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air8101/luatos/firmware/version/](https://docs.openluat.com/air8101/luatos/firmware/)

3. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境
2. main.lua 中加载需要用的功能模块，三个功能模块同时只能选择一个使用，另两个注释。
3. Luatools 烧录内核固件和修改后的 demo 脚本代码
4. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，spi 初始化，数据读写，文件操作等。
5. raw_spi.lua 如下 log 显示：

```bash
[2025-11-19 14:47:55.490] luat:U(253):I/user.main AirSPINORFLASH_1000 001.000.000
[2025-11-19 14:47:55.490] luat:U(258):I/user.raw_spi SPI_ID 0 CS_PIN 15
[2025-11-19 14:47:55.490] luat:I(259):spi:spi初始化为主机模式 id=0
[2025-11-19 14:47:55.490] luat:D(259):spi:半双工模式 0 0
[2025-11-19 14:47:55.490] luat:D(259):spi:SPI(0) gpio init : wire 3 clk 14 cs 15 mosi 16 miso 17
[2025-11-19 14:47:55.490] luat:U(260):I/user.硬件spi 初始化，波特率: 0 4000000
[2025-11-19 14:47:55.490] luat:U(260):I/user.spi 芯片ID: 0x%02X 0x%02X 0x%02X 239 64 23
[2025-11-19 14:47:55.490] luat:U(261):I/user.spi 寄存器状态为: 0x%02X 0
[2025-11-19 14:47:55.490] luat:U(261):I/user.spi 擦除扇区 0x000000...
[2025-11-19 14:47:55.577] luat:U(330):I/user.spi 擦除后数据: FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF 32
[2025-11-19 14:47:55.577] luat:U(330):I/user.spi 写入数据: Hello, SPI Flash! 
[2025-11-19 14:47:55.577] luat:U(338):I/user.spi 正在验证数据... 18
[2025-11-19 14:47:55.577] luat:U(339):I/user.spi 数据验证成功!,读取到数据为：Hello, SPI Flash! 
[2025-11-19 14:47:55.589] luat:U(339):I/user.关闭spi 0




```

6. lf_fs.lua 如下 log 显示：

```bash
[2025-11-19 14:45:07.840] luat:U(254):I/user.main AirSPINORFLASH_1000 001.000.000
[2025-11-19 14:45:07.854] luat:U(259):I/user.lf_fs SPI_ID 0 CS_PIN 15
[2025-11-19 14:45:07.854] luat:D(259):spi:SPI(0) gpio init : wire 3 clk 14 cs 15 mosi 16 miso 17
[2025-11-19 14:45:07.854] luat:U(260):I/user.硬件spi 初始化，波特率: SPI*: 60C7E6D0 4000000
[2025-11-19 14:45:07.854] luat:U(260):I/user.SPI初始化 成功，波特率: 4000000
[2025-11-19 14:45:07.854] luat:U(261):I/user.Flash初始化 开始
[2025-11-19 14:45:07.854] luat:I(261):little_flash:Welcome to use little flash V0.0.1 .
[2025-11-19 14:45:07.854] luat:I(261):little_flash:Github Repositories https://github.com/Dozingfiretruck/little_flash .
[2025-11-19 14:45:07.854] luat:I(261):little_flash:Gitee Repositories https://gitee.com/Dozingfiretruck/little_flash .
[2025-11-19 14:45:07.854] luat:I(261):little_flash:Found SFDP Header. The Revision is V1.5, NPN is 0, Access Protocol is 0xFF.
[2025-11-19 14:45:07.854] luat:I(262):little_flash:Parameter Header is OK. The Parameter ID is 0xFF00, Revision is V5.1, Length is 16,Parameter Table Pointer is 0x000080.
[2025-11-19 14:45:07.854] luat:I(262):little_flash:Found a flash chip. Size is 8388608 bytes.
[2025-11-19 14:45:07.948] luat:U(361):I/user.Flash初始化 成功，设备: userdata: 60C8B6B8
[2025-11-19 14:45:07.948] luat:U(361):I/user.文件系统 开始挂载: /little_flash
[2025-11-19 14:45:07.961] luat:D(384):little_flash:lfs_mount 0
[2025-11-19 14:45:07.961] luat:D(384):little_flash:vfs mount /little_flash ret 0
[2025-11-19 14:45:07.961] luat:U(385):I/user.文件系统 挂载成功: /little_flash
[2025-11-19 14:45:07.961] luat:U(385):I/user.文件系统信息 开始查询: /little_flash
[2025-11-19 14:45:07.978] luat:U(405):I/user.  总block数: 2048
[2025-11-19 14:45:07.978] luat:U(405):I/user.  已用block数: 2
[2025-11-19 14:45:07.978] luat:U(405):I/user.  block大小: 4096 字节
[2025-11-19 14:45:07.978] luat:U(405):I/user.  文件系统类型: lfs
[2025-11-19 14:45:07.978] luat:U(406):I/user.文件操作测试 开始
[2025-11-19 14:45:08.001] luat:U(419):I/user.  写入成功 /little_flash/test.txt 内容: 当前时间: Sat Jan  1 00:00:00 2000
[2025-11-19 14:45:08.001] luat:U(430):I/user.  读取成功 /little_flash/test.txt 内容: 当前时间: Sat Jan  1 00:00:00 2000
[2025-11-19 14:45:08.088] luat:U(490):I/user.  追加后内容: LuatOS 测试 - 追加时间: Sat Jan  1 00:00:00 2000
[2025-11-19 14:45:08.088] luat:U(491):I/user.文件操作测试 完成
[2025-11-19 14:45:08.088] luat:U(491):I/user.关闭spi true


```

7. sfud_test.lua 如下 log 显示：

```bash
[2025-11-19 14:39:12.075] luat:I(205):sfud:LuatOS-sfud flash device initialized successfully.
[2025-11-19 14:39:12.082] luat:U(205):I/user.获取flash设备信息表: userdata: 280032B4
[2025-11-19 14:39:12.082] luat:U(205):I/user.获取 Flash 容量和page大小： 8388608 4096
[2025-11-19 14:39:12.169] luat:U(285):I/user.擦除一个块的数据： 0
[2025-11-19 14:39:12.169] luat:U(287):I/user.写入数据： 0
[2025-11-19 14:39:12.178] luat:U(299):I/user.读取数据： luat:U(299):testdatluat:U(300):

[2025-11-19 14:39:12.262] luat:U(379):I/user.先擦除再写入数据： 0
[2025-11-19 14:39:12.262] luat:U(379):I/user.文件系统 开始挂载: /sfud_flash
[2025-11-19 14:39:12.307] luat:D(432):sfud:lfs_mount 0
[2025-11-19 14:39:12.307] luat:D(432):sfud:vfs mount /sfud_flash ret 0
[2025-11-19 14:39:12.307] luat:U(432):I/user.文件系统 挂载成功: /sfud_flash
[2025-11-19 14:39:12.307] luat:U(433):I/user.文件系统信息 开始查询: /sfud_flash
[2025-11-19 14:39:12.354] luat:U(478):I/user.  总block数: 2048
[2025-11-19 14:39:12.354] luat:U(478):I/user.  已用block数: 2
[2025-11-19 14:39:12.354] luat:U(479):I/user.  block大小: 4096 字节
[2025-11-19 14:39:12.354] luat:U(479):I/user.  文件系统类型: lfs
[2025-11-19 14:39:12.354] luat:U(479):I/user.文件操作测试 开始
[2025-11-19 14:39:12.365] luat:U(508):I/user.  写入成功 /sfud_flash/test.txt 内容: 当前时间: Sat Jan  1 00:00:00 2000
[2025-11-19 14:39:12.416] luat:U(536):I/user.  读取成功 /sfud_flash/test.txt 内容: 当前时间: Sat Jan  1 00:00:00 2000
[2025-11-19 14:39:12.571] luat:U(693):I/user.  追加后内容: LuatOS 测试 - 追加时间: Sat Jan  1 00:00:00 2000
[2025-11-19 14:39:12.571] luat:U(693):I/user.文件操作测试 完成
[2025-11-19 14:39:12.571] luat:U(693):I/user.关闭spi true


```
