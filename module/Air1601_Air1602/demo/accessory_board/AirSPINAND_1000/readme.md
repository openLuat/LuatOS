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

[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)

1. 合宙 Air1601 开发板一块

2. 合宙 AirSPINAND_1000配件板 一块

3. TYPE-C USB 数据线一根 ，Air8000 核心板和数据线的硬件接线方式为：

- Air1601 开发板 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）

- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

4. 杜邦线 6 根

    Air1601 开发板 与 AirSPINAND_1000配件板 按以下方式接线：

<table>
<tr>
<td>Air1601 开发板 <br/></td><td>AirSPINAND_1000配件板<br/></td></tr>
<tr>
<td>GND(任意)          <br/></td><td>GND<br/></td></tr>
<tr>
<td>VDD_EXT<br/></td><td>VCC<br/></td></tr>
<tr>
<td>38/SPI1_CS<br/></td><td>CS<br/></td></tr>
<tr>
<td>39/SPI1_SLK<br/></td><td>SCK<br/></td></tr>
<tr>
<td>41/SPI1_MOSI<br/></td><td>MOSI<br/></td></tr>
<tr>
<td>40/SPI1_MISO<br/></td><td>MISO<br/></td></tr>
</table>

## 演示软件环境：

1. Luatools 下载调试工具

2. 固件版本：LuatOS-SoC_V1013_Air1601.soc正式版，固件地址，如有最新固件请用最新 [Air1601/Air1602LuatOS固件和Demo](https://docs.openluat.com/air1601/luatos/)

3. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1. 搭建好硬件环境

2. main.lua 中加载lf_fs功能模块

3. Luatools 烧录内核固件和  demo 脚本

4. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，spi 初始化，数据读写，文件操作等。

5. lf_fs.lua 如下 log 显示：

```lua
[2026-04-29 11:13:58.426][LTOS/N][000000000.014]:I/user.main SPI_NAND 001.999.000
[2026-04-29 11:13:58.427][CAPP/N][000000000.017]:luat_gpio_open 209:38
[2026-04-29 11:13:58.430][LTOS/N][000000000.018]:I/user.lf_fs SPI_ID 1 CS_PIN 8
[2026-04-29 11:13:58.431][CAPP/N][000000000.018]:spi_set_new_config 386:spi1 目标速度4000000 实际速度3750000 BR 71
[2026-04-29 11:13:58.433][LTOS/N][000000000.018]:I/user.硬件spi 初始化，波特率: SPI*: 1C3969E0 4000000
[2026-04-29 11:13:58.438][LTOS/N][000000000.018]:I/user.SPI初始化 成功，波特率 4000000
[2026-04-29 11:13:58.440][LTOS/N][000000000.019]:I/user.Flash初始化 开始
[2026-04-29 11:13:58.442][LTOS/N][000000000.019]:I/little_flash SFDP header not found.
[2026-04-29 11:13:58.444][LTOS/N][000000000.019]:I/little_flash JEDEC ID: manufacturer_id:0xEF device_id:0xAA23 
[2026-04-29 11:13:58.446][LTOS/N][000000000.019]:I/little_flash little flash found flash W25N04KVZEIR
[2026-04-29 11:13:58.448][LTOS/N][000000000.069]:I/user.Flash初始化 成功，设备: userdata: 1C3B05E0
[2026-04-29 11:13:58.451][LTOS/N][000000000.069]:I/user.文件系统 开始挂载: /little_flash
[2026-04-29 11:13:58.712][LTOS/N][000000000.395]:D/little_flash lfs_mount 0
[2026-04-29 11:13:58.716][LTOS/N][000000000.395]:D/little_flash vfs mount /little_flash ret 0
[2026-04-29 11:13:58.717][LTOS/N][000000000.395]:I/user.文件系统 挂载成功: /little_flash
[2026-04-29 11:13:58.719][LTOS/N][000000000.396]:I/user.文件系统信息 开始查询: /little_flash
[2026-04-29 11:13:58.930][LTOS/N][000000000.642]:I/user.  总block数: 4096
[2026-04-29 11:13:58.933][LTOS/N][000000000.642]:I/user.  已用block数: 2
[2026-04-29 11:13:58.934][LTOS/N][000000000.642]:I/user.  block大小: 131072 字节
[2026-04-29 11:13:58.936][LTOS/N][000000000.642]:I/user.  文件系统类型: lfs
[2026-04-29 11:13:58.937][LTOS/N][000000000.642]:I/user.文件操作测试 开始
[2026-04-29 11:13:59.085][LTOS/N][000000000.779]:I/user.  写入成功 /little_flash/test.txt 内容: hello,  W25N01GV！
[2026-04-29 11:13:59.227][LTOS/N][000000000.910]:I/user.  读取成功 /little_flash/test.txt 内容: hello,  W25N01GV！
[2026-04-29 11:13:59.841][LTOS/N][000000001.525]:I/user.  追加后内容: LuatOS 测试 这是追加的内容 
[2026-04-29 11:13:59.844][LTOS/N][000000001.525]:I/user.文件操作测试 完成
[2026-04-29 11:13:59.846][LTOS/N][000000001.525]:I/user.关闭spi true
```
