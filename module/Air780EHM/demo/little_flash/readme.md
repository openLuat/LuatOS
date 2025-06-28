
## 演示功能概述

使用Air780EHM核心板对SPI FLASH来挂载成lfs文件系统，并通过文件系统相关接口去操作lfs文件系统中的文件，将演示文件的读写、删除、追加等操作

## 演示硬件环境

1、Air780EHM核心板一块

2、TYPE-C USB数据线一根

3、spi flash模块一个

4、Air780EHM核心板和数据线的硬件接线方式为

- Air780EHM核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；
5、Air780EHM核心板和spi flash模块接线方式
``` lua
--[[
Air780EHM            SPI_FLASH
GND(任意)            GND
VDD_EXT              VCC
GPIO8/SPI0_CS        CS,片选
SPI0_SLK             CLK,时钟
SPI0_MOSI            DI,主机输出,从机输入
SPI0_MISO            DO,主机输入,从机输出
]]
```

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHM V2007版本固件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM/core)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V2007固件对比验证）

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

```lua
[2025-06-28 14:36:58.809][000000001.402] I/user.lf.init ok	userdata: 0C0C318C
[2025-06-28 14:36:58.815][000000001.410] D/little_flash vfs mount /little_flash ret 0
[2025-06-28 14:36:58.826][000000001.410] I/user.lf.mount	true
[2025-06-28 14:36:58.835][000000001.410] I/user.little_flash	挂载成功
[2025-06-28 14:36:58.847][000000001.417] I/user.fsstat	true	1024	2	4096	lfs
[2025-06-28 14:36:58.854][000000001.426] I/user.little_flash	Sun   0 08:00:01
[2025-06-28 14:36:58.861][000000001.446] I/user.little_flash	LuatOS - Sun   0 08:00:01

```