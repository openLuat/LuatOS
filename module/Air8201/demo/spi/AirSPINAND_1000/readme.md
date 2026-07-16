## 适配说明

本demo已适配 **Air8201G** 。**Air8201H 不支持此demo**，因为其 BTB 扩展板未引出 SPI 总线。

---

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

1. 合宙 Air8201G 板子一块

2. 合宙 AirSPINAND_1000配件板 一块

3. 杜邦线 6 根

    Air8201G 模块与 AirSPINAND_1000配件板 按以下方式接线：

| Air8201G BTB引脚 | AirSPINAND_1000配件板 |
| ---------------- | --------------------- |
| GND              | GND                   |
| VDD_EXT          | VCC                   |
| GPIO8 / SPI0_CS  | CS                    |
| SPI0_SCLK        | SCK / CLK             |
| SPI0_MOSI        | MOSI / DI             |
| SPI0_MISO        | MISO / DO             |

## 演示软件环境：

1. Luatools 下载调试工具

2、[Air8201G固件(基于Air780EGH)](https://docs.openluat.com/air780egh/luatos/firmware/version/)

3. pc 系统 win10 及以上

## 演示核心步骤：

1. 搭建好硬件环境

2. main.lua 中加载lf_fs功能模块

3. Luatools 烧录内核固件和 demo 脚本

4. 烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关信息，spi 初始化，数据读写，文件操作等。

5. lf_fs.lua 如下 log 显示：

```bash
[2026-07-15 20:27:01.706][000000000.262] SPI_HWInit 556:spi0 speed 2000000,1994805,154
[2026-07-15 20:27:01.713][000000000.262] I/user.硬件spi 初始化，波特率: SPI*: 0C7F4D78 2000000
[2026-07-15 20:27:01.719][000000000.262] I/user.SPI初始化 成功，波特率 2000000
[2026-07-15 20:27:01.732][000000000.263] I/user.Flash初始化 开始
[2026-07-15 20:27:01.747][000000000.263] I/little_flash SFDP header not found.
[2026-07-15 20:27:01.759][000000000.263] I/little_flash JEDEC ID: manufacturer_id:0xEF device_id:0xAA21 
[2026-07-15 20:27:01.776][000000000.263] I/little_flash little flash found flash W25N01GVZEIG
[2026-07-15 20:27:01.788][000000000.264] I/little_flash little_flash_reset start
[2026-07-15 20:27:01.794][000000000.264] I/little_flash little_flash_reset after wait_busy #1 result=0
[2026-07-15 20:27:01.799][000000000.314] I/little_flash little_flash_reset after wait_busy #2 result=0
[2026-07-15 20:27:01.808][000000000.314] I/little_flash little_flash_reset done
[2026-07-15 20:27:01.814][000000000.314] I/user.Flash初始化 成功，设备: userdata: 0C13B794
[2026-07-15 20:27:01.825][000000000.315] I/user.文件系统 开始挂载: /little_flash
[2026-07-15 20:27:01.984][000000000.828] D/little_flash lfs_mount 0
[2026-07-15 20:27:01.994][000000000.828] D/little_flash vfs mount start /little_flash fs lfs2 offset 0 size 0
[2026-07-15 20:27:02.001][000000000.828] D/little_flash vfs mount /little_flash fs lfs2 ret 0
[2026-07-15 20:27:02.013][000000000.829] I/user.文件系统 挂载成功: /little_flash
[2026-07-15 20:27:02.018][000000000.829] I/user.文件系统信息 开始查询: /little_flash
[2026-07-15 20:27:02.027][000000001.220] I/user.  总block数: 1024
[2026-07-15 20:27:02.031][000000001.221] I/user.  已用block数: 2
[2026-07-15 20:27:02.039][000000001.221] I/user.  block大小: 131072 字节
[2026-07-15 20:27:02.044][000000001.221] I/user.  文件系统类型: lfs
[2026-07-15 20:27:02.048][000000001.222] I/user.文件操作测试 开始
[2026-07-15 20:27:02.563][000000001.466] I/user.  写入成功 /little_flash/test.txt 内容: 当前时间: Sat Jan  1 08:00:01 2000
[2026-07-15 20:27:02.580][000000001.680] I/user.  读取成功 /little_flash/test.txt 内容: 当前时间: Sat Jan  1 08:00:01 2000
[2026-07-15 20:27:03.533][000000002.728] I/user.  追加后内容: LuatOS 测试 - 追加时间: Sat Jan  1 08:00:02 2000
[2026-07-15 20:27:03.538][000000002.728] I/user.文件操作测试 完成
[2026-07-15 20:27:03.540][000000002.728] I/user.关闭spi true


```
